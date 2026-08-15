// refresh_gasstations — 오피넷 전국 주유소 일일 스냅샷 수집기.
//
// 전국 229개 시도/시군구 쌍을 순회하며 오피넷에서 주유소 목록을 수집하고,
// GIS 좌표 기준으로 중복을 제거한 뒤 JSON 파일로 저장한다.
// 저장은 staging 파일에 먼저 쓰고 성공 시에만 rename해서
// 기존 파일을 보호한다.
//
// 사용법:
//   refresh_gasstations [--output <path>]
//   기본값: --output /data/gasstations/gasstations.json

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── 출력 JSON 레코드 ────────────────────────────────────────────

#[derive(Serialize, Deserialize, Clone)]
struct GasStationRecord {
    name: String,
    brand: String,
    address: String,
    lat: f64,
    lon: f64,
    price: Option<i32>,
    premium_price: Option<i32>,
}

// ── 좌표 변환 (main.rs 복사 — lib 리팩터 불필요) ───────────────

fn meridional_arc(a: f64, e2: f64, lat_rad: f64) -> f64 {
    let e4 = e2 * e2;
    let e6 = e4 * e2;
    a * ((1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * lat_rad
        - (3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * (2.0 * lat_rad).sin()
        + (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * (4.0 * lat_rad).sin()
        - (35.0 * e6 / 3072.0) * (6.0 * lat_rad).sin())
}

fn gis_to_wgs84(gis_x: f64, gis_y: f64) -> (f64, f64) {
    let a = 6_378_137.0_f64;
    let f = 1.0 / 298.257_223_563_f64;
    let e2 = 2.0 * f - f * f;
    let k0 = 1.0_f64;
    let lat0 = 38.0_f64.to_radians();
    let lon0 = 128.0_f64.to_radians();

    let m0 = meridional_arc(a, e2, lat0);
    let x = gis_x - 400_000.0;
    let y = gis_y - 600_000.0;
    let m1 = m0 + y / k0;

    let mu = m1 / (a * (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0));

    let e1 = (1.0 - (1.0 - e2).sqrt()) / (1.0 + (1.0 - e2).sqrt());
    let e1_2 = e1 * e1;
    let e1_3 = e1_2 * e1;
    let e1_4 = e1_3 * e1;

    let phi1 = mu
        + (3.0 * e1 / 2.0 - 27.0 * e1_3 / 32.0) * (2.0 * mu).sin()
        + (21.0 * e1_2 / 16.0 - 55.0 * e1_4 / 32.0) * (4.0 * mu).sin()
        + (151.0 * e1_3 / 96.0) * (6.0 * mu).sin()
        + (1097.0 * e1_4 / 512.0) * (8.0 * mu).sin();

    let sin_phi1 = phi1.sin();
    let cos_phi1 = phi1.cos();
    let tan_phi1 = phi1.tan();
    let ep2 = e2 / (1.0 - e2);

    let n1 = a / (1.0 - e2 * sin_phi1 * sin_phi1).sqrt();
    let t1 = tan_phi1 * tan_phi1;
    let c1 = ep2 * cos_phi1 * cos_phi1;
    let r1 = a * (1.0 - e2) / (1.0 - e2 * sin_phi1 * sin_phi1).powf(1.5);
    let d = x / (n1 * k0);
    let d2 = d * d;

    let lat = phi1
        - (n1 * tan_phi1 / r1)
            * (d2 / 2.0
                - (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * ep2) * d2 * d2 / 24.0
                + (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * ep2
                    - 3.0 * c1 * c1)
                    * d2 * d2 * d2 / 720.0);

    let lon = lon0
        + (d - (1.0 + 2.0 * t1 + c1) * d2 * d / 6.0
            + (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * ep2 + 24.0 * t1 * t1)
                * d2 * d2 * d / 120.0)
            / cos_phi1;

    (lat.to_degrees(), lon.to_degrees())
}

// ── 오피넷 가격 파싱 (main.rs 복사) ───────────────────────────

fn parse_opinet_price(v: &serde_json::Value) -> Option<i32> {
    v.as_str()?.trim().parse::<i32>().ok().filter(|&p| p > 0 && p != 99999)
}

// ── 오피넷 시도/시군구 조회 ────────────────────────────────────

async fn fetch_opinet_region(
    client: &reqwest::Client,
    sido_nm: &str,
    sigungu_nm: &str,
) -> Vec<serde_json::Value> {
    let params = [
        ("BTN_DIV", "os_btn"),
        ("SIDO_NM", sido_nm),
        ("SIGUNGU_NM", sigungu_nm),
        ("POLL_ALL", "all"),
        ("NORM_YN", "on"),
        ("SEARCH_MOD", "addr"),
        ("LPG_YN", "N"),
    ];
    let resp = client
        .post("https://www.opinet.co.kr/searRgPlaceAjax.do")
        .header("Referer", "https://www.opinet.co.kr/searRgSelect.do")
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        )
        .form(&params)
        .timeout(std::time::Duration::from_secs(15))
        .send()
        .await;
    match resp {
        Err(e) => {
            eprintln!("[refresh_gasstations] 오피넷 요청 실패 ({sido_nm} {sigungu_nm}): {e}");
            vec![]
        }
        Ok(r) => match r.json::<serde_json::Value>().await {
            Err(e) => {
                eprintln!("[refresh_gasstations] 파싱 실패 ({sido_nm} {sigungu_nm}): {e}");
                vec![]
            }
            Ok(v) => v["list"].as_array().cloned().unwrap_or_default(),
        },
    }
}

// ── 전국 시도/시군구 쌍 (229개) ───────────────────────────────
// Opinet은 시군구가 있어야 결과를 반환함. 세종은 시군구 없음(빈 문자열).

const REGIONS: &[(&str, &str)] = &[
    // 서울특별시 (25개 구)
    ("서울특별시", "강남구"), ("서울특별시", "강동구"), ("서울특별시", "강북구"),
    ("서울특별시", "강서구"), ("서울특별시", "관악구"), ("서울특별시", "광진구"),
    ("서울특별시", "구로구"), ("서울특별시", "금천구"), ("서울특별시", "노원구"),
    ("서울특별시", "도봉구"), ("서울특별시", "동대문구"), ("서울특별시", "동작구"),
    ("서울특별시", "마포구"), ("서울특별시", "서대문구"), ("서울특별시", "서초구"),
    ("서울특별시", "성동구"), ("서울특별시", "성북구"), ("서울특별시", "송파구"),
    ("서울특별시", "양천구"), ("서울특별시", "영등포구"), ("서울특별시", "용산구"),
    ("서울특별시", "은평구"), ("서울특별시", "종로구"), ("서울특별시", "중구"),
    ("서울특별시", "중랑구"),
    // 부산광역시 (16개)
    ("부산광역시", "강서구"), ("부산광역시", "금정구"), ("부산광역시", "기장군"),
    ("부산광역시", "남구"), ("부산광역시", "동구"), ("부산광역시", "동래구"),
    ("부산광역시", "부산진구"), ("부산광역시", "북구"), ("부산광역시", "사상구"),
    ("부산광역시", "사하구"), ("부산광역시", "서구"), ("부산광역시", "수영구"),
    ("부산광역시", "연제구"), ("부산광역시", "영도구"), ("부산광역시", "중구"),
    ("부산광역시", "해운대구"),
    // 대구광역시 (8개)
    ("대구광역시", "남구"), ("대구광역시", "달서구"), ("대구광역시", "달성군"),
    ("대구광역시", "동구"), ("대구광역시", "북구"), ("대구광역시", "서구"),
    ("대구광역시", "수성구"), ("대구광역시", "중구"),
    // 인천광역시 (10개)
    ("인천광역시", "강화군"), ("인천광역시", "계양구"), ("인천광역시", "남동구"),
    ("인천광역시", "동구"), ("인천광역시", "미추홀구"), ("인천광역시", "부평구"),
    ("인천광역시", "서구"), ("인천광역시", "연수구"), ("인천광역시", "옹진군"),
    ("인천광역시", "중구"),
    // 광주광역시 (5개)
    ("광주광역시", "광산구"), ("광주광역시", "남구"), ("광주광역시", "동구"),
    ("광주광역시", "북구"), ("광주광역시", "서구"),
    // 대전광역시 (5개)
    ("대전광역시", "대덕구"), ("대전광역시", "동구"), ("대전광역시", "서구"),
    ("대전광역시", "유성구"), ("대전광역시", "중구"),
    // 울산광역시 (5개)
    ("울산광역시", "남구"), ("울산광역시", "동구"), ("울산광역시", "북구"),
    ("울산광역시", "울주군"), ("울산광역시", "중구"),
    // 세종특별자치시 (시군구 없음)
    ("세종특별자치시", ""),
    // 경기도 (31개)
    ("경기도", "가평군"), ("경기도", "고양시"), ("경기도", "과천시"),
    ("경기도", "광명시"), ("경기도", "광주시"), ("경기도", "구리시"),
    ("경기도", "군포시"), ("경기도", "김포시"), ("경기도", "남양주시"),
    ("경기도", "동두천시"), ("경기도", "부천시"), ("경기도", "성남시"),
    ("경기도", "수원시"), ("경기도", "시흥시"), ("경기도", "안산시"),
    ("경기도", "안성시"), ("경기도", "안양시"), ("경기도", "양주시"),
    ("경기도", "양평군"), ("경기도", "여주시"), ("경기도", "연천군"),
    ("경기도", "오산시"), ("경기도", "용인시"), ("경기도", "의왕시"),
    ("경기도", "의정부시"), ("경기도", "이천시"), ("경기도", "파주시"),
    ("경기도", "평택시"), ("경기도", "포천시"), ("경기도", "하남시"),
    ("경기도", "화성시"),
    // 강원특별자치도 (18개)
    ("강원특별자치도", "강릉시"), ("강원특별자치도", "고성군"), ("강원특별자치도", "동해시"),
    ("강원특별자치도", "삼척시"), ("강원특별자치도", "속초시"), ("강원특별자치도", "양구군"),
    ("강원특별자치도", "양양군"), ("강원특별자치도", "영월군"), ("강원특별자치도", "원주시"),
    ("강원특별자치도", "인제군"), ("강원특별자치도", "정선군"), ("강원특별자치도", "철원군"),
    ("강원특별자치도", "춘천시"), ("강원특별자치도", "태백시"), ("강원특별자치도", "평창군"),
    ("강원특별자치도", "홍천군"), ("강원특별자치도", "화천군"), ("강원특별자치도", "횡성군"),
    // 충청북도 (11개)
    ("충청북도", "괴산군"), ("충청북도", "단양군"), ("충청북도", "보은군"),
    ("충청북도", "영동군"), ("충청북도", "옥천군"), ("충청북도", "음성군"),
    ("충청북도", "제천시"), ("충청북도", "증평군"), ("충청북도", "진천군"),
    ("충청북도", "청주시"), ("충청북도", "충주시"),
    // 충청남도 (15개)
    ("충청남도", "계룡시"), ("충청남도", "공주시"), ("충청남도", "금산군"),
    ("충청남도", "논산시"), ("충청남도", "당진시"), ("충청남도", "보령시"),
    ("충청남도", "부여군"), ("충청남도", "서산시"), ("충청남도", "서천군"),
    ("충청남도", "아산시"), ("충청남도", "예산군"), ("충청남도", "천안시"),
    ("충청남도", "청양군"), ("충청남도", "태안군"), ("충청남도", "홍성군"),
    // 전북특별자치도 (14개)
    ("전북특별자치도", "고창군"), ("전북특별자치도", "군산시"), ("전북특별자치도", "김제시"),
    ("전북특별자치도", "남원시"), ("전북특별자치도", "무주군"), ("전북특별자치도", "부안군"),
    ("전북특별자치도", "순창군"), ("전북특별자치도", "완주군"), ("전북특별자치도", "익산시"),
    ("전북특별자치도", "임실군"), ("전북특별자치도", "장수군"), ("전북특별자치도", "전주시"),
    ("전북특별자치도", "정읍시"), ("전북특별자치도", "진안군"),
    // 전라남도 (22개)
    ("전라남도", "강진군"), ("전라남도", "고흥군"), ("전라남도", "곡성군"),
    ("전라남도", "광양시"), ("전라남도", "구례군"), ("전라남도", "나주시"),
    ("전라남도", "담양군"), ("전라남도", "목포시"), ("전라남도", "무안군"),
    ("전라남도", "보성군"), ("전라남도", "순천시"), ("전라남도", "신안군"),
    ("전라남도", "여수시"), ("전라남도", "영광군"), ("전라남도", "영암군"),
    ("전라남도", "완도군"), ("전라남도", "장성군"), ("전라남도", "장흥군"),
    ("전라남도", "진도군"), ("전라남도", "함평군"), ("전라남도", "해남군"),
    ("전라남도", "화순군"),
    // 경상북도 (23개)
    ("경상북도", "경산시"), ("경상북도", "경주시"), ("경상북도", "고령군"),
    ("경상북도", "구미시"), ("경상북도", "군위군"), ("경상북도", "김천시"),
    ("경상북도", "문경시"), ("경상북도", "봉화군"), ("경상북도", "상주시"),
    ("경상북도", "성주군"), ("경상북도", "안동시"), ("경상북도", "영덕군"),
    ("경상북도", "영양군"), ("경상북도", "영주시"), ("경상북도", "영천시"),
    ("경상북도", "예천군"), ("경상북도", "울릉군"), ("경상북도", "울진군"),
    ("경상북도", "의성군"), ("경상북도", "청도군"), ("경상북도", "청송군"),
    ("경상북도", "칠곡군"), ("경상북도", "포항시"),
    // 경상남도 (18개)
    ("경상남도", "거제시"), ("경상남도", "거창군"), ("경상남도", "고성군"),
    ("경상남도", "김해시"), ("경상남도", "남해군"), ("경상남도", "밀양시"),
    ("경상남도", "사천시"), ("경상남도", "산청군"), ("경상남도", "양산시"),
    ("경상남도", "의령군"), ("경상남도", "진주시"), ("경상남도", "창녕군"),
    ("경상남도", "창원시"), ("경상남도", "통영시"), ("경상남도", "하동군"),
    ("경상남도", "함안군"), ("경상남도", "함양군"), ("경상남도", "합천군"),
    // 제주특별자치도 (2개)
    ("제주특별자치도", "서귀포시"), ("제주특별자치도", "제주시"),
];

// ── dedup 키 생성: GIS 좌표를 정수 격자로 반올림 ──────────────

fn dedup_key(gis_x: f64, gis_y: f64) -> (i64, i64) {
    (gis_x.round() as i64, gis_y.round() as i64)
}

// ── main ──────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let output_path = {
        let mut out = "/data/gasstations/gasstations.json".to_string();
        let mut i = 1;
        while i < args.len() {
            if args[i] == "--output" && i + 1 < args.len() {
                out = args[i + 1].clone();
                i += 2;
            } else {
                i += 1;
            }
        }
        out
    };

    println!("[refresh_gasstations] 시작 — 지역 {} 개, output: {output_path}", REGIONS.len());

    let client = reqwest::Client::builder()
        .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .build()
        .expect("HTTP 클라이언트 생성 실패");

    let mut seen: HashMap<(i64, i64), ()> = HashMap::new();
    let mut records: Vec<GasStationRecord> = Vec::new();

    for (idx, (sido, sigungu)) in REGIONS.iter().enumerate() {
        let label = if sigungu.is_empty() { sido.to_string() } else { format!("{sido} {sigungu}") };
        let raw = fetch_opinet_region(&client, sido, sigungu).await;
        let count_before = records.len();

        for s in &raw {
            let gis_x = match s["GIS_X_COOR"].as_f64() { Some(v) => v, None => continue };
            let gis_y = match s["GIS_Y_COOR"].as_f64() { Some(v) => v, None => continue };

            let key = dedup_key(gis_x, gis_y);
            if seen.contains_key(&key) { continue; }
            seen.insert(key, ());

            let (lat, lon) = gis_to_wgs84(gis_x, gis_y);
            records.push(GasStationRecord {
                name: s["OS_NM"].as_str().unwrap_or("").to_string(),
                brand: s["POLL_DIV_CD"].as_str().unwrap_or("").to_string(),
                address: s["VAN_ADR"].as_str().unwrap_or("").to_string(),
                lat,
                lon,
                price: parse_opinet_price(&s["B027_P"]),
                premium_price: parse_opinet_price(&s["B034_P"]),
            });
        }

        let added = records.len() - count_before;
        println!("[refresh_gasstations] ({}/{}) {label} — {added}건 추가 (누계 {}건)", idx + 1, REGIONS.len(), records.len());

        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
    }

    println!("[refresh_gasstations] 총 {} 건 수집 완료, 파일 저장 중...", records.len());

    if records.is_empty() {
        eprintln!("[refresh_gasstations] 경고: 수집된 주유소 0건 — 기존 파일 유지");
        std::process::exit(1);
    }

    let json = match serde_json::to_string(&records) {
        Ok(j) => j,
        Err(e) => { eprintln!("[refresh_gasstations] JSON 직렬화 실패: {e}"); std::process::exit(1); }
    };

    if let Some(parent) = std::path::Path::new(&output_path).parent() {
        if let Err(e) = std::fs::create_dir_all(parent) {
            eprintln!("[refresh_gasstations] 디렉터리 생성 실패: {e}"); std::process::exit(1);
        }
    }

    let staging_path = format!("{output_path}.tmp");
    if let Err(e) = std::fs::write(&staging_path, &json) {
        eprintln!("[refresh_gasstations] staging 쓰기 실패: {e}"); std::process::exit(1);
    }
    if let Err(e) = std::fs::rename(&staging_path, &output_path) {
        eprintln!("[refresh_gasstations] rename 실패: {e}");
        let _ = std::fs::remove_file(&staging_path);
        std::process::exit(1);
    }

    println!("[refresh_gasstations] 완료 — {} bytes, {} 건", json.len(), records.len());
}
