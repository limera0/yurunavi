// ingest_poi — 소상공인시장진흥공단 상가(상권)정보 CSV(17개 광역시도) → poi.db(SQLite) 일괄 적재.
//
// 매 분기 전체 재적재(full rebuild) 방식이라 증분 upsert가 아니라 출력 DB 파일을
// 통째로 지우고 새로 만든다. `native/src/main.rs`의 `/poi/nearby`는 이 DB를
// read-only로 열어서 서빙한다.
//
// 사용법:
//   ingest_poi [--input-dir <dir>] [--output <path>]
//   기본값: --input-dir /data/poi/raw, --output /data/poi/poi.db

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use csv::StringRecord;
use rusqlite::{params, Connection};

// ── 카테고리 매핑 ────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum Category {
    Cafe,
    ConvenienceStore,
    GasStation,
    Supermarket,
    Restaurant,
}

impl Category {
    fn as_str(self) -> &'static str {
        match self {
            Category::Cafe => "cafe",
            Category::ConvenienceStore => "convenience_store",
            Category::GasStation => "gas_station",
            Category::Supermarket => "supermarket",
            Category::Restaurant => "restaurant",
        }
    }

    /// 요약 출력 순서 고정용.
    const ALL: [Category; 5] = [
        Category::Cafe,
        Category::ConvenienceStore,
        Category::GasStation,
        Category::Supermarket,
        Category::Restaurant,
    ];
}

/// restaurant(I2 대분류) 중 "식당"으로 취급하지 않는 중분류
/// (구내식당/출장음식/이동음식/기타간이/주점/카페). `lib/services/poi_service.dart`의
/// `_restaurantExcludeMcls`와 동일.
const RESTAURANT_EXCLUDE_MCLS: [&str; 6] = ["I207", "I208", "I209", "I210", "I211", "I212"];

/// 소분류 → 대분류/중분류 순으로 우리 앱 5종 카테고리에 매핑한다.
/// 매핑되지 않으면(범위 밖) None.
fn map_category(large: &str, mid: &str, small: &str) -> Option<Category> {
    match small {
        "I21201" => return Some(Category::Cafe),
        "G20405" => return Some(Category::ConvenienceStore),
        "G21401" => return Some(Category::GasStation),
        "G20404" => return Some(Category::Supermarket),
        _ => {}
    }
    if large == "I2" && !RESTAURANT_EXCLUDE_MCLS.contains(&mid) {
        return Some(Category::Restaurant);
    }
    None
}

// ── 오분류 필터 (lib/services/poi_service.dart `looksMisclassified` 포팅) ───

/// 어떤 카테고리든 실제 소비자 대상 매장이 아닌 행정/사업체성 명칭.
const NON_STOREFRONT_KEYWORDS: [&str; 6] = ["협동조합", "협회", "조합", "컨설팅", "사무소", "재단"];

/// 카페(cafe) 소분류에 섞여 들어오는 식당류 업소명 키워드.
const CAFE_RESTAURANT_KEYWORDS: [&str; 21] = [
    "닭발", "곱창", "국밥", "삼겹살", "갈비", "냉면", "순대", "족발", "보쌈", "횟집", "참치",
    "감자탕", "해장국", "추어탕", "매운탕", "닭갈비", "곰탕", "설렁탕", "육개장", "삼계탕", "육회",
];

/// `name`이 `category`로 분류되기엔 업소명상 명백히 어색한지 판정한다.
fn looks_misclassified(name: &str, category: Category) -> bool {
    for kw in NON_STOREFRONT_KEYWORDS {
        if name.contains(kw) {
            return true;
        }
    }
    if category == Category::Cafe {
        for kw in CAFE_RESTAURANT_KEYWORDS {
            if name.contains(kw) {
                return true;
            }
        }
    }
    false
}

// ── CSV 행 파싱 ─────────────────────────────────────────────────

// 1-indexed 컬럼 → 0-indexed 배열 인덱스.
const COL_BIZES_ID: usize = 0; // 1. 상가업소번호
const COL_NAME: usize = 1; // 2. 상호명
const COL_LARGE: usize = 3; // 4. 상권업종대분류코드
const COL_MID: usize = 5; // 6. 상권업종중분류코드
const COL_SMALL: usize = 7; // 8. 상권업종소분류코드
const COL_LOT_ADDR: usize = 24; // 25. 지번주소
const COL_ROAD_ADDR: usize = 31; // 32. 도로명주소
const COL_LON: usize = 37; // 38. 경도
const COL_LAT: usize = 38; // 39. 위도

struct ParsedRow {
    bizes_id: String,
    name: String,
    category: Category,
    lat: f64,
    lon: f64,
    address: Option<String>,
}

enum RowOutcome {
    Kept(ParsedRow),
    OutOfScope,
    Misclassified,
    Invalid,
}

fn parse_row(record: &StringRecord) -> RowOutcome {
    let get = |idx: usize| record.get(idx).unwrap_or("").trim();

    let bizes_id = get(COL_BIZES_ID);
    let name = get(COL_NAME);

    if bizes_id.is_empty() || name.is_empty() {
        return RowOutcome::Invalid;
    }

    let large = get(COL_LARGE);
    let mid = get(COL_MID);
    let small = get(COL_SMALL);

    let category = match map_category(large, mid, small) {
        Some(c) => c,
        None => return RowOutcome::OutOfScope,
    };

    let lat: f64 = match get(COL_LAT).parse() {
        Ok(v) => v,
        Err(_) => return RowOutcome::Invalid,
    };
    let lon: f64 = match get(COL_LON).parse() {
        Ok(v) => v,
        Err(_) => return RowOutcome::Invalid,
    };

    if looks_misclassified(name, category) {
        return RowOutcome::Misclassified;
    }

    let road_addr = get(COL_ROAD_ADDR);
    let lot_addr = get(COL_LOT_ADDR);
    let address = if !road_addr.is_empty() {
        Some(road_addr.to_string())
    } else if !lot_addr.is_empty() {
        Some(lot_addr.to_string())
    } else {
        None
    };

    RowOutcome::Kept(ParsedRow {
        bizes_id: bizes_id.to_string(),
        name: name.to_string(),
        category,
        lat,
        lon,
        address,
    })
}

// ── 통계 ─────────────────────────────────────────────────────────

#[derive(Default)]
struct IngestStats {
    total_rows: u64,
    kept_by_category: HashMap<Category, u64>,
    misclassified_rows: u64,
    out_of_scope_rows: u64,
    invalid_rows: u64,
    duplicate_id_rows: u64,
}

fn print_summary(stats: &IngestStats, db_size_bytes: u64) {
    println!("────────────────────────────────────────────");
    println!("[ingest_poi] 처리 완료");
    println!("총 읽은 행: {}", stats.total_rows);
    let mut total_kept = 0u64;
    for cat in Category::ALL {
        let n = *stats.kept_by_category.get(&cat).unwrap_or(&0);
        total_kept += n;
        println!("  {}: {}", cat.as_str(), n);
    }
    println!("총 저장된 행: {total_kept}");
    println!("오분류 필터로 제외된 행: {}", stats.misclassified_rows);
    println!("범위 밖(카테고리 불일치) 행: {}", stats.out_of_scope_rows);
    println!("유효하지 않은 행(좌표/필수값 누락): {}", stats.invalid_rows);
    if stats.duplicate_id_rows > 0 {
        println!("중복 상가업소번호로 무시된 행: {}", stats.duplicate_id_rows);
    }
    println!(
        "최종 DB 파일 크기: {:.2} MB ({} bytes)",
        db_size_bytes as f64 / 1_048_576.0,
        db_size_bytes
    );
    println!("────────────────────────────────────────────");
}

// ── DB 스키마 ────────────────────────────────────────────────────

fn create_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE poi (
            id INTEGER PRIMARY KEY,
            bizes_id TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            address TEXT
        );
        CREATE INDEX idx_poi_category ON poi(category);
        CREATE VIRTUAL TABLE poi_rtree USING rtree(
            id,
            min_lat, max_lat,
            min_lon, max_lon
        );",
    )
}

// ── 파일 처리 ────────────────────────────────────────────────────

fn list_csv_files(dir: &Path) -> std::io::Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let is_csv = path
            .extension()
            .map(|e| e.eq_ignore_ascii_case("csv"))
            .unwrap_or(false);
        if path.is_file() && is_csv {
            files.push(path);
        }
    }
    files.sort();
    Ok(files)
}

fn ingest_file(
    path: &Path,
    poi_stmt: &mut rusqlite::Statement,
    rtree_stmt: &mut rusqlite::Statement,
    tx: &rusqlite::Transaction,
    stats: &mut IngestStats,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(true)
        .flexible(true) // 일부 지역 파일에 트레일링 필드 수 편차가 있을 수 있어 방어적으로 허용
        .from_path(path)?;

    for result in reader.records() {
        let record = match result {
            Ok(r) => r,
            Err(e) => {
                stats.invalid_rows += 1;
                eprintln!("[ingest_poi]   CSV 파싱 오류(행 건너뜀): {e}");
                continue;
            }
        };
        stats.total_rows += 1;

        match parse_row(&record) {
            RowOutcome::Invalid => stats.invalid_rows += 1,
            RowOutcome::OutOfScope => stats.out_of_scope_rows += 1,
            RowOutcome::Misclassified => stats.misclassified_rows += 1,
            RowOutcome::Kept(row) => {
                let changed = poi_stmt.execute(params![
                    row.bizes_id,
                    row.name,
                    row.category.as_str(),
                    row.lat,
                    row.lon,
                    row.address,
                ])?;
                if changed == 0 {
                    // UNIQUE(bizes_id) 충돌 → INSERT OR IGNORE로 무시됨.
                    // 스펙상 "전국적으로 고유"라 확인됐지만 방어적으로 카운트만 하고 계속 진행.
                    stats.duplicate_id_rows += 1;
                    continue;
                }
                let id = tx.last_insert_rowid();
                rtree_stmt.execute(params![id, row.lat, row.lat, row.lon, row.lon])?;
                *stats.kept_by_category.entry(row.category).or_insert(0) += 1;
            }
        }
    }
    Ok(())
}

// ── CLI 인자 파싱 ────────────────────────────────────────────────

struct Args {
    input_dir: PathBuf,
    output: PathBuf,
}

fn parse_args() -> Args {
    let mut input_dir = PathBuf::from("/data/poi/raw");
    let mut output = PathBuf::from("/data/poi/poi.db");

    let cli_args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < cli_args.len() {
        match cli_args[i].as_str() {
            "--input-dir" => {
                i += 1;
                if let Some(v) = cli_args.get(i) {
                    input_dir = PathBuf::from(v);
                } else {
                    eprintln!("[ingest_poi] --input-dir 뒤에 값이 없습니다");
                    std::process::exit(1);
                }
            }
            "--output" => {
                i += 1;
                if let Some(v) = cli_args.get(i) {
                    output = PathBuf::from(v);
                } else {
                    eprintln!("[ingest_poi] --output 뒤에 값이 없습니다");
                    std::process::exit(1);
                }
            }
            other => {
                eprintln!("[ingest_poi] 알 수 없는 인자 무시: {other}");
            }
        }
        i += 1;
    }

    Args { input_dir, output }
}

// ── main ─────────────────────────────────────────────────────────

fn main() {
    let args = parse_args();
    println!(
        "[ingest_poi] input_dir={} output={}",
        args.input_dir.display(),
        args.output.display()
    );

    // 매 분기 전체 재적재: 기존 출력 파일(및 WAL/SHM 사이드카)이 있으면 삭제하고 새로 만든다.
    if args.output.exists() {
        if let Err(e) = fs::remove_file(&args.output) {
            eprintln!(
                "[ingest_poi] 기존 DB 파일 삭제 실패({}): {e}",
                args.output.display()
            );
            std::process::exit(1);
        }
    }
    for suffix in ["-wal", "-shm"] {
        let sidecar = PathBuf::from(format!("{}{}", args.output.display(), suffix));
        let _ = fs::remove_file(sidecar);
    }

    let mut conn = match Connection::open(&args.output) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[ingest_poi] DB 파일 생성 실패({}): {e}", args.output.display());
            std::process::exit(1);
        }
    };

    if let Err(e) = create_schema(&conn) {
        eprintln!("[ingest_poi] 스키마 생성 실패: {e}");
        std::process::exit(1);
    }

    let csv_files = match list_csv_files(&args.input_dir) {
        Ok(f) => f,
        Err(e) => {
            eprintln!(
                "[ingest_poi] 입력 디렉터리 읽기 실패({}): {e}",
                args.input_dir.display()
            );
            std::process::exit(1);
        }
    };
    if csv_files.is_empty() {
        eprintln!(
            "[ingest_poi] 경고: {}에 *.csv 파일이 없습니다",
            args.input_dir.display()
        );
    }

    let mut stats = IngestStats::default();

    {
        let tx = conn.transaction().expect("[ingest_poi] 트랜잭션 시작 실패");
        {
            let mut poi_stmt = tx
                .prepare(
                    "INSERT OR IGNORE INTO poi (bizes_id, name, category, lat, lon, address) \
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                )
                .expect("[ingest_poi] poi INSERT 준비 실패");
            let mut rtree_stmt = tx
                .prepare(
                    "INSERT INTO poi_rtree (id, min_lat, max_lat, min_lon, max_lon) \
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                )
                .expect("[ingest_poi] poi_rtree INSERT 준비 실패");

            for path in &csv_files {
                println!("[ingest_poi] 처리 중: {}", path.display());
                if let Err(e) = ingest_file(path, &mut poi_stmt, &mut rtree_stmt, &tx, &mut stats) {
                    eprintln!("[ingest_poi]   파일 처리 실패({}): {e}", path.display());
                }
            }
        }
        tx.commit().expect("[ingest_poi] 커밋 실패");
    }

    let db_size = fs::metadata(&args.output).map(|m| m.len()).unwrap_or(0);
    print_summary(&stats, db_size);
}

// ── 단위 테스트 ───────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── 카테고리 매핑 ──────────────────────────────────────────

    #[test]
    fn maps_cafe_small_code() {
        assert_eq!(map_category("I2", "I212", "I21201"), Some(Category::Cafe));
    }

    #[test]
    fn maps_convenience_store_small_code() {
        assert_eq!(
            map_category("G2", "G204", "G20405"),
            Some(Category::ConvenienceStore)
        );
    }

    #[test]
    fn maps_gas_station_small_code() {
        assert_eq!(
            map_category("G2", "G214", "G21401"),
            Some(Category::GasStation)
        );
    }

    #[test]
    fn maps_supermarket_small_code() {
        assert_eq!(
            map_category("G2", "G204", "G20404"),
            Some(Category::Supermarket)
        );
    }

    #[test]
    fn maps_restaurant_from_i2_large_excluding_cafe_mid() {
        // I2 대분류이지만 소분류가 카페 전용 코드가 아닌 일반 식당류.
        assert_eq!(
            map_category("I2", "I201", "I20101"),
            Some(Category::Restaurant)
        );
    }

    #[test]
    fn i2_excluded_mid_classes_are_out_of_scope() {
        // I207~I212(구내식당/출장음식/이동음식/기타간이/주점/카페)는 restaurant가 아님.
        for mid in ["I207", "I208", "I209", "I210", "I211", "I212"] {
            assert_eq!(
                map_category("I2", mid, "I29999"),
                None,
                "mid={mid}는 restaurant 제외 대상이어야 함"
            );
        }
    }

    #[test]
    fn g20402_large_mart_is_out_of_scope() {
        // 대형마트(G20402)는 의도적으로 스코프 밖 — 실제 결과 0건으로 검증됨(스펙 참조).
        assert_eq!(map_category("G2", "G204", "G20402"), None);
    }

    #[test]
    fn unrelated_category_is_out_of_scope() {
        assert_eq!(map_category("D1", "D101", "D10101"), None);
    }

    // ── 오분류 필터 (lib/services/poi_service.dart 테스트 포팅) ──

    #[test]
    fn cafe_slot_restaurant_keywords_are_misclassified() {
        assert!(looks_misclassified("할매국물닭발", Category::Cafe));
        assert!(looks_misclassified("영동곱창", Category::Cafe));
        assert!(looks_misclassified("원조순대국밥", Category::Cafe));
    }

    #[test]
    fn normal_cafe_names_are_not_misclassified() {
        assert!(!looks_misclassified("스타벅스 강남점", Category::Cafe));
        assert!(!looks_misclassified("동네카페", Category::Cafe));
    }

    #[test]
    fn restaurant_keywords_not_applied_to_restaurant_category() {
        // restaurant 카테고리는 애초에 식당이 맞으므로 같은 키워드로 걸러내면 안 됨.
        assert!(!looks_misclassified("할매국물닭발", Category::Restaurant));
    }

    #[test]
    fn non_storefront_keywords_apply_regardless_of_category() {
        assert!(looks_misclassified("OO협동조합", Category::GasStation));
        assert!(looks_misclassified("OO컨설팅", Category::GasStation));
        assert!(looks_misclassified("OO협회", Category::Cafe));
    }

    #[test]
    fn normal_gas_and_convenience_names_are_not_misclassified() {
        assert!(!looks_misclassified("GS칼텍스 오산주유소", Category::GasStation));
        assert!(!looks_misclassified("CU 오산점", Category::ConvenienceStore));
    }

    #[test]
    fn regression_yeonguso_cafe_branding_not_misclassified() {
        // 회귀 가드: "OO연구소"류 카페 브랜딩은 오분류로 판정하지 않는다.
        assert!(!looks_misclassified("OO커피연구소", Category::Cafe));
        // "조합"은 의도적으로 필터에 남겨둠 — 정식 법인명을 상호로 쓰는 식당까지 걸러내는
        // 반대 방향 회귀는 사용자 확인(2026-07-14)에 따라 의도된 동작.
        assert!(looks_misclassified("산머루영농조합법인", Category::Restaurant));
    }

    // ── 행 유효성 / 주소 폴백 ──────────────────────────────────

    fn record_from(fields: &[&str]) -> StringRecord {
        StringRecord::from(fields.to_vec())
    }

    /// 39개 컬럼짜리 최소 유효 레코드를 만든다. `overrides`로 특정 인덱스만 덮어쓴다.
    fn make_row(overrides: &[(usize, &str)]) -> StringRecord {
        let mut fields = vec![""; 39];
        fields[COL_BIZES_ID] = "MA010120220000001";
        fields[COL_NAME] = "테스트카페";
        fields[COL_LARGE] = "I2";
        fields[COL_MID] = "I212";
        fields[COL_SMALL] = "I21201";
        fields[COL_LOT_ADDR] = "서울특별시 종로구 1-1";
        fields[COL_ROAD_ADDR] = "서울특별시 종로구 세종대로 1";
        fields[COL_LON] = "126.9780";
        fields[COL_LAT] = "37.5665";
        for (idx, val) in overrides {
            fields[*idx] = val;
        }
        record_from(&fields)
    }

    #[test]
    fn valid_row_is_kept_with_road_address_preferred() {
        let rec = make_row(&[]);
        match parse_row(&rec) {
            RowOutcome::Kept(row) => {
                assert_eq!(row.bizes_id, "MA010120220000001");
                assert_eq!(row.category, Category::Cafe);
                assert_eq!(row.address.as_deref(), Some("서울특별시 종로구 세종대로 1"));
            }
            _ => panic!("정상 행은 Kept여야 함"),
        }
    }

    #[test]
    fn empty_road_address_falls_back_to_lot_address() {
        // 도로명주소가 빈 문자열(NULL 아님)인 경우 지번주소로 폴백해야 한다.
        let rec = make_row(&[(COL_ROAD_ADDR, "")]);
        match parse_row(&rec) {
            RowOutcome::Kept(row) => {
                assert_eq!(row.address.as_deref(), Some("서울특별시 종로구 1-1"));
            }
            _ => panic!("정상 행은 Kept여야 함"),
        }
    }

    #[test]
    fn both_addresses_empty_yields_none() {
        let rec = make_row(&[(COL_ROAD_ADDR, ""), (COL_LOT_ADDR, "")]);
        match parse_row(&rec) {
            RowOutcome::Kept(row) => assert_eq!(row.address, None),
            _ => panic!("정상 행은 Kept여야 함"),
        }
    }

    #[test]
    fn invalid_lat_lon_is_dropped() {
        let rec = make_row(&[(COL_LAT, "not_a_number")]);
        assert!(matches!(parse_row(&rec), RowOutcome::Invalid));
    }

    #[test]
    fn missing_bizes_id_is_dropped() {
        let rec = make_row(&[(COL_BIZES_ID, "")]);
        assert!(matches!(parse_row(&rec), RowOutcome::Invalid));
    }

    #[test]
    fn missing_name_is_dropped() {
        let rec = make_row(&[(COL_NAME, "")]);
        assert!(matches!(parse_row(&rec), RowOutcome::Invalid));
    }

    #[test]
    fn out_of_scope_category_is_dropped() {
        let rec = make_row(&[(COL_LARGE, "D1"), (COL_MID, "D101"), (COL_SMALL, "D10101")]);
        assert!(matches!(parse_row(&rec), RowOutcome::OutOfScope));
    }

    #[test]
    fn misclassified_row_is_dropped() {
        let rec = make_row(&[(COL_NAME, "할매국물닭발")]);
        assert!(matches!(parse_row(&rec), RowOutcome::Misclassified));
    }
}
