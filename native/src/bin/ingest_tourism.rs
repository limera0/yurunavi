// ingest_tourism — 관광지/전망대 POI를 tourism.db(SQLite)로 일괄 적재한다.
//
// 입력 2종:
//   1. OSM 추출분(1순위) — `osmium tags-filter` + `osmium export -f geojsonseq`로 만든
//      GeoJSON Text Sequence 파일(RFC 8142, 각 줄 앞에 0x1e RS 바이트). 라이선스 ODbL.
//   2. data.go.kr 전국관광지정보표준데이터(2순위, 한글 명칭 보강용) CSV — 컬럼 순서는
//      docker/refresh_tourism_data.sh가 생성하는 그대로:
//      name,category_raw,road_addr,lot_addr,lat,lon,description,institution
//      없어도(파일 미존재) 실패로 취급하지 않고 OSM 단독으로 진행한다.
//
// ⚠️ 라이선스 분리 원칙: 이 DB(`tourism.db`)는 소상공인 POI(`poi.db`, 공공누리)와
// 물리적으로 완전히 별도 파일이어야 한다. ODbL(OSM) 데이터를 poi.db와 병합하면 그 DB
// 전체가 ODbL 파생 데이터베이스가 되어 share-alike 의무가 걸릴 수 있다 — 절대 병합 금지.
//
// 매 실행마다 전체 재적재(full rebuild) — 출력 DB 파일을 통째로 지우고 새로 만든다.
//
// 사용법:
//   ingest_tourism [--osm-geojsonseq <path>] [--std-csv <path>] [--output <path>]
//                   [--match-radius-m <f64>]
//   기본값: --osm-geojsonseq /data/poi/tourism_raw/osm_tourism.geojsonseq
//           --std-csv        /data/poi/tourism_raw/tourism_std.csv (없으면 스킵)
//           --output         /data/poi/tourism.db
//           --match-radius-m 80.0

use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader};
use std::path::{Path, PathBuf};

use csv::StringRecord;
use rusqlite::{params, Connection};
use serde_json::{Map, Value};

// ── 카테고리 ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum Category {
    TouristSpot,
    Viewpoint,
}

impl Category {
    fn as_str(self) -> &'static str {
        match self {
            Category::TouristSpot => "tourist_spot",
            Category::Viewpoint => "viewpoint",
        }
    }

    const ALL: [Category; 2] = [Category::TouristSpot, Category::Viewpoint];
}

// ── OSM 태그 → 카테고리 분류 ────────────────────────────────────

/// OSM 태그(raw properties, `@type`/`@id` 포함 가능)에서 카테고리를 판정한다.
/// `tourism=viewpoint`가 최우선(전망대 = 라이더 핵심 가치, RECON §9-1).
/// `natural=peak`은 이름이 있을 때만 채택한다(무명 봉우리 제외) — 단, 다른 조건으로
/// 이미 채택된 경우(예: historic과 중복 태깅) 이 이름 제약이 적용되지 않는데, 그건
/// 의도된 동작이다(그 경우 "무명 봉우리"가 아니라 다른 근거로 관광지인 것).
fn classify_osm_tags(tags: &Map<String, Value>, name: Option<&str>) -> Option<Category> {
    let get = |k: &str| tags.get(k).and_then(Value::as_str);

    if get("tourism") == Some("viewpoint") {
        return Some(Category::Viewpoint);
    }
    if get("boundary") == Some("national_park") {
        return Some(Category::TouristSpot);
    }
    if get("tourism") == Some("attraction") {
        return Some(Category::TouristSpot);
    }
    if get("tourism") == Some("museum") {
        return Some(Category::TouristSpot);
    }
    if tags.contains_key("historic") {
        return Some(Category::TouristSpot);
    }
    if get("leisure") == Some("nature_reserve") {
        return Some(Category::TouristSpot);
    }
    if get("natural") == Some("peak") {
        return match name {
            Some(n) if !n.trim().is_empty() => Some(Category::TouristSpot),
            _ => None,
        };
    }
    None
}

/// `name` → `name:ko` → `int_name` → `name:en` 순 폴백.
fn extract_name(tags: &Map<String, Value>) -> Option<String> {
    for key in ["name", "name:ko", "int_name", "name:en"] {
        if let Some(v) = tags.get(key).and_then(Value::as_str) {
            let trimmed = v.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    None
}

// ── 지오메트리 → 중심점(centroid) ──────────────────────────────

/// GeoJSON 지오메트리(Point/LineString/Polygon/MultiPolygon)에서 대표 좌표를 뽑는다.
/// Polygon/MultiPolygon은 정확한 폴리곤 중심(area-weighted centroid)이 아니라 외곽
/// 링 정점들의 단순 평균이다 — POI 마커 위치로는 충분한 근사치(정밀 라우팅용 아님).
fn centroid_of_geometry(geometry: &Value) -> Option<(f64, f64)> {
    let gtype = geometry.get("type")?.as_str()?;
    let coords = geometry.get("coordinates")?;
    match gtype {
        "Point" => point_from_coord(coords),
        "LineString" => centroid_of_point_list(coords.as_array()?),
        "Polygon" => {
            let outer_ring = coords.as_array()?.first()?.as_array()?;
            centroid_of_point_list(outer_ring)
        }
        "MultiPolygon" => {
            let first_poly = coords.as_array()?.first()?.as_array()?;
            let outer_ring = first_poly.first()?.as_array()?;
            centroid_of_point_list(outer_ring)
        }
        _ => None,
    }
}

fn point_from_coord(coord: &Value) -> Option<(f64, f64)> {
    let arr = coord.as_array()?;
    let lon = arr.first()?.as_f64()?;
    let lat = arr.get(1)?.as_f64()?;
    Some((lat, lon))
}

fn centroid_of_point_list(points: &[Value]) -> Option<(f64, f64)> {
    if points.is_empty() {
        return None;
    }
    let mut sum_lat = 0.0f64;
    let mut sum_lon = 0.0f64;
    let mut n = 0u32;
    for p in points {
        let arr = p.as_array()?;
        let lon = arr.first()?.as_f64()?;
        let lat = arr.get(1)?.as_f64()?;
        sum_lat += lat;
        sum_lon += lon;
        n += 1;
    }
    if n == 0 {
        return None;
    }
    Some((sum_lat / f64::from(n), sum_lon / f64::from(n)))
}

// ── 거리 계산(좌표 근접 매칭용) ─────────────────────────────────

fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const EARTH_RADIUS_M: f64 = 6_371_000.0;
    let phi1 = lat1.to_radians();
    let phi2 = lat2.to_radians();
    let dphi = (lat2 - lat1).to_radians();
    let dlambda = (lon2 - lon1).to_radians();
    let a = (dphi / 2.0).sin().powi(2) + phi1.cos() * phi2.cos() * (dlambda / 2.0).sin().powi(2);
    2.0 * EARTH_RADIUS_M * a.sqrt().asin()
}

// ── OSM geojsonseq 읽기 ─────────────────────────────────────────

/// RFC 8142 GeoJSON Text Sequence: 각 레코드 앞에 0x1e(RS) 바이트가 붙는다.
fn read_osm_geojsonseq(path: &Path) -> io::Result<Vec<Value>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    let mut features = Vec::new();
    for line in reader.lines() {
        let line = line?;
        let trimmed = line.trim_start_matches('\u{1e}').trim();
        if trimmed.is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(trimmed) {
            Ok(v) => features.push(v),
            Err(e) => eprintln!("[ingest_tourism]   geojsonseq 파싱 오류(행 건너뜀): {e}"),
        }
    }
    Ok(features)
}

struct OsmEntry {
    category: Category,
    name: Option<String>,
    lat: f64,
    lon: f64,
    osm_type: String,
    osm_id: i64,
    tags_json: String,
}

fn process_osm_feature(feature: &Value, stats: &mut IngestStats) -> Option<OsmEntry> {
    let properties = feature.get("properties")?.as_object()?;
    let osm_type = properties.get("@type")?.as_str()?.to_string();
    let osm_id = properties.get("@id")?.as_i64()?;

    let name = extract_name(properties);

    let category = match classify_osm_tags(properties, name.as_deref()) {
        Some(c) => c,
        None => {
            stats.osm_skipped_no_category += 1;
            return None;
        }
    };

    let geometry = feature.get("geometry")?;
    let (lat, lon) = match centroid_of_geometry(geometry) {
        Some(v) => v,
        None => {
            stats.osm_skipped_invalid_geometry += 1;
            return None;
        }
    };

    // `@type`/`@id`는 osmium이 붙인 메타데이터지 OSM 태그가 아니므로 원본 태그
    // 저장분(osm_tags 컬럼)에서는 제외한다.
    let mut clean_tags = properties.clone();
    clean_tags.remove("@type");
    clean_tags.remove("@id");
    let tags_json = serde_json::to_string(&clean_tags).unwrap_or_default();

    Some(OsmEntry {
        category,
        name,
        lat,
        lon,
        osm_type,
        osm_id,
        tags_json,
    })
}

// ── data.go.kr 표준데이터 CSV 읽기 ──────────────────────────────

// docker/refresh_tourism_data.sh가 생성하는 CSV 컬럼 순서(0-indexed).
const COL_STD_NAME: usize = 0;
const COL_STD_CATEGORY_RAW: usize = 1;
const COL_STD_ROAD_ADDR: usize = 2;
const COL_STD_LOT_ADDR: usize = 3;
const COL_STD_LAT: usize = 4;
const COL_STD_LON: usize = 5;
const COL_STD_DESC: usize = 6;
const COL_STD_INSTITUTION: usize = 7;

struct StdRow {
    name: String,
    category: Category,
    road_addr: Option<String>,
    lot_addr: Option<String>,
    lat: f64,
    lon: f64,
    description: Option<String>,
    #[allow(dead_code)]
    institution: Option<String>,
}

enum StdRowOutcome {
    Kept(StdRow),
    Invalid,
}

fn non_empty(s: &str) -> Option<String> {
    if s.is_empty() {
        None
    } else {
        Some(s.to_string())
    }
}

/// "관광지구분" 필드에 전망대성 구분이 있으면 viewpoint, 없으면 tourist_spot 기본값.
/// 2026-08-06 실측 기준 이 데이터셋의 관광지구분 값은 "관광지"/"관광단지"뿐이라 실제로는
/// 항상 tourist_spot으로 떨어지지만, 향후 지자체가 "전망대"류 구분을 추가할 가능성에
/// 대비해 방어적으로 남겨둔다.
fn classify_std_category(category_raw: &str) -> Category {
    if category_raw.contains("전망대") {
        Category::Viewpoint
    } else {
        Category::TouristSpot
    }
}

fn parse_std_row(record: &StringRecord) -> StdRowOutcome {
    let get = |idx: usize| record.get(idx).unwrap_or("").trim();

    let name = get(COL_STD_NAME);
    if name.is_empty() {
        return StdRowOutcome::Invalid;
    }

    let lat: f64 = match get(COL_STD_LAT).parse() {
        Ok(v) => v,
        Err(_) => return StdRowOutcome::Invalid,
    };
    let lon: f64 = match get(COL_STD_LON).parse() {
        Ok(v) => v,
        Err(_) => return StdRowOutcome::Invalid,
    };

    let category = classify_std_category(get(COL_STD_CATEGORY_RAW));

    StdRowOutcome::Kept(StdRow {
        name: name.to_string(),
        category,
        road_addr: non_empty(get(COL_STD_ROAD_ADDR)),
        lot_addr: non_empty(get(COL_STD_LOT_ADDR)),
        lat,
        lon,
        description: non_empty(get(COL_STD_DESC)),
        institution: non_empty(get(COL_STD_INSTITUTION)),
    })
}

fn read_std_csv(path: &Path, stats: &mut IngestStats) -> Result<Vec<StdRow>, Box<dyn std::error::Error>> {
    let mut reader = csv::ReaderBuilder::new()
        .has_headers(true)
        .flexible(true)
        .from_path(path)?;

    let mut rows = Vec::new();
    for result in reader.records() {
        let record = match result {
            Ok(r) => r,
            Err(e) => {
                stats.std_invalid_rows += 1;
                eprintln!("[ingest_tourism]   표준데이터 CSV 파싱 오류(행 건너뜀): {e}");
                continue;
            }
        };
        stats.std_total_rows += 1;
        match parse_std_row(&record) {
            StdRowOutcome::Kept(row) => rows.push(row),
            StdRowOutcome::Invalid => stats.std_invalid_rows += 1,
        }
    }
    Ok(rows)
}

// ── 최종 레코드 + 병합(좌표 근접 매칭) ───────────────────────────

struct TourismEntry {
    category: Category,
    name: Option<String>,
    lat: f64,
    lon: f64,
    source: &'static str,
    osm_type: Option<String>,
    osm_id: Option<i64>,
    osm_tags: Option<String>,
    address: Option<String>,
    description: Option<String>,
}

impl From<OsmEntry> for TourismEntry {
    fn from(e: OsmEntry) -> Self {
        TourismEntry {
            category: e.category,
            name: e.name,
            lat: e.lat,
            lon: e.lon,
            source: "osm",
            osm_type: Some(e.osm_type),
            osm_id: Some(e.osm_id),
            osm_tags: Some(e.tags_json),
            address: None,
            description: None,
        }
    }
}

#[derive(Default)]
struct MergeStats {
    std_total: u64,
    std_matched_into_osm: u64,
    std_added_standalone: u64,
}

/// OSM 추출분에 표준데이터를 좌표 근접 매칭(반경 `radius_m`)으로 병합한다.
/// 매칭되면 OSM 엔트리의 이름/주소/설명을 표준데이터로 보강(한국어 공식 명칭 우선).
/// 매칭 안 되면 표준데이터 항목을 독립 엔트리로 추가한다(지자체 지정 관광지 등
/// OSM에 없는 것).
fn merge_osm_and_std(
    osm_entries: Vec<OsmEntry>,
    std_rows: Vec<StdRow>,
    radius_m: f64,
) -> (Vec<TourismEntry>, MergeStats) {
    let mut entries: Vec<TourismEntry> = osm_entries.into_iter().map(TourismEntry::from).collect();
    let mut stats = MergeStats::default();

    // 사전 필터용 대략적인 위도 1도 거리(적도 기준 약 111.32km) — 후보를 좁혀서
    // haversine 호출 수를 줄인다. 정확도에는 영향 없음(최종 판정은 haversine으로).
    let radius_deg_lat = radius_m / 111_320.0;

    for std in std_rows {
        stats.std_total += 1;

        let mut best: Option<(usize, f64)> = None;
        for (idx, entry) in entries.iter().enumerate() {
            if (entry.lat - std.lat).abs() > radius_deg_lat {
                continue;
            }
            let d = haversine_m(entry.lat, entry.lon, std.lat, std.lon);
            if d <= radius_m && best.map(|(_, bd)| d < bd).unwrap_or(true) {
                best = Some((idx, d));
            }
        }

        match best {
            Some((idx, _)) => {
                let e = &mut entries[idx];
                e.name = Some(std.name.clone());
                e.address = std.road_addr.clone().or_else(|| std.lot_addr.clone());
                e.description = std.description.clone();
                e.source = "osm+data_go_kr";
                stats.std_matched_into_osm += 1;
            }
            None => {
                entries.push(TourismEntry {
                    category: std.category,
                    name: Some(std.name.clone()),
                    lat: std.lat,
                    lon: std.lon,
                    source: "data_go_kr",
                    osm_type: None,
                    osm_id: None,
                    osm_tags: None,
                    address: std.road_addr.clone().or_else(|| std.lot_addr.clone()),
                    description: std.description.clone(),
                });
                stats.std_added_standalone += 1;
            }
        }
    }

    (entries, stats)
}

// ── 통계 / 요약 출력 ─────────────────────────────────────────────

#[derive(Default)]
struct IngestStats {
    osm_total_features: u64,
    osm_kept_by_category: HashMap<Category, u64>,
    osm_skipped_no_category: u64,
    osm_skipped_invalid_geometry: u64,
    std_total_rows: u64,
    std_invalid_rows: u64,
}

fn print_summary(stats: &IngestStats, merge: &MergeStats, final_by_category: &HashMap<Category, u64>, db_size_bytes: u64) {
    println!("────────────────────────────────────────────");
    println!("[ingest_tourism] 처리 완료");
    println!("OSM 원본 매칭 피처 수(geojsonseq 총 라인): {}", stats.osm_total_features);
    let mut osm_kept_total = 0u64;
    for cat in Category::ALL {
        let n = *stats.osm_kept_by_category.get(&cat).unwrap_or(&0);
        osm_kept_total += n;
    }
    println!("OSM 채택(카테고리 매칭+지오메트리 유효): {osm_kept_total}");
    println!("  카테고리 불일치/무명 봉우리 등으로 제외: {}", stats.osm_skipped_no_category);
    println!("  지오메트리 무효로 제외: {}", stats.osm_skipped_invalid_geometry);
    println!("표준데이터(data.go.kr) 총 읽은 행: {}", stats.std_total_rows);
    println!("  유효하지 않은 행: {}", stats.std_invalid_rows);
    println!("  OSM 엔트리에 병합(이름/주소 보강): {}", merge.std_matched_into_osm);
    println!("  OSM에 없어 독립 추가: {}", merge.std_added_standalone);
    println!("최종 저장 카테고리별 건수:");
    let mut final_total = 0u64;
    for cat in Category::ALL {
        let n = *final_by_category.get(&cat).unwrap_or(&0);
        final_total += n;
        println!("  {}: {}", cat.as_str(), n);
    }
    println!("최종 저장 총 건수: {final_total}");
    println!(
        "최종 DB 파일 크기: {:.2} MB ({} bytes)",
        db_size_bytes as f64 / 1_048_576.0,
        db_size_bytes
    );
    println!("────────────────────────────────────────────");
}

// ── DB 스키마 / 적재 ─────────────────────────────────────────────

fn create_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE tourism (
            id INTEGER PRIMARY KEY,
            category TEXT NOT NULL,
            name TEXT,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            source TEXT NOT NULL,
            osm_type TEXT,
            osm_id INTEGER,
            osm_tags TEXT,
            address TEXT,
            description TEXT
        );
        CREATE INDEX idx_tourism_category ON tourism(category);
        CREATE VIRTUAL TABLE tourism_rtree USING rtree(
            id,
            min_lat, max_lat,
            min_lon, max_lon
        );",
    )
}

fn write_db(
    output: &Path,
    entries: &[TourismEntry],
) -> Result<HashMap<Category, u64>, Box<dyn std::error::Error>> {
    if output.exists() {
        fs::remove_file(output)?;
    }
    for suffix in ["-wal", "-shm"] {
        let sidecar = PathBuf::from(format!("{}{}", output.display(), suffix));
        let _ = fs::remove_file(sidecar);
    }

    let mut conn = Connection::open(output)?;
    create_schema(&conn)?;

    let mut final_by_category: HashMap<Category, u64> = HashMap::new();
    {
        let tx = conn.transaction()?;
        {
            let mut tourism_stmt = tx.prepare(
                "INSERT INTO tourism (category, name, lat, lon, source, osm_type, osm_id, osm_tags, address, description) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            )?;
            let mut rtree_stmt = tx.prepare(
                "INSERT INTO tourism_rtree (id, min_lat, max_lat, min_lon, max_lon) \
                 VALUES (?1, ?2, ?3, ?4, ?5)",
            )?;

            for entry in entries {
                tourism_stmt.execute(params![
                    entry.category.as_str(),
                    entry.name,
                    entry.lat,
                    entry.lon,
                    entry.source,
                    entry.osm_type,
                    entry.osm_id,
                    entry.osm_tags,
                    entry.address,
                    entry.description,
                ])?;
                let id = tx.last_insert_rowid();
                rtree_stmt.execute(params![id, entry.lat, entry.lat, entry.lon, entry.lon])?;
                *final_by_category.entry(entry.category).or_insert(0) += 1;
            }
        }
        tx.commit()?;
    }

    Ok(final_by_category)
}

// ── CLI 인자 파싱 ────────────────────────────────────────────────

struct Args {
    osm_geojsonseq: PathBuf,
    std_csv: PathBuf,
    output: PathBuf,
    match_radius_m: f64,
}

fn parse_args() -> Args {
    let mut osm_geojsonseq = PathBuf::from("/data/poi/tourism_raw/osm_tourism.geojsonseq");
    let mut std_csv = PathBuf::from("/data/poi/tourism_raw/tourism_std.csv");
    let mut output = PathBuf::from("/data/poi/tourism.db");
    let mut match_radius_m = 80.0f64;

    let cli_args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < cli_args.len() {
        match cli_args[i].as_str() {
            "--osm-geojsonseq" => {
                i += 1;
                match cli_args.get(i) {
                    Some(v) => osm_geojsonseq = PathBuf::from(v),
                    None => {
                        eprintln!("[ingest_tourism] --osm-geojsonseq 뒤에 값이 없습니다");
                        std::process::exit(1);
                    }
                }
            }
            "--std-csv" => {
                i += 1;
                match cli_args.get(i) {
                    Some(v) => std_csv = PathBuf::from(v),
                    None => {
                        eprintln!("[ingest_tourism] --std-csv 뒤에 값이 없습니다");
                        std::process::exit(1);
                    }
                }
            }
            "--output" => {
                i += 1;
                match cli_args.get(i) {
                    Some(v) => output = PathBuf::from(v),
                    None => {
                        eprintln!("[ingest_tourism] --output 뒤에 값이 없습니다");
                        std::process::exit(1);
                    }
                }
            }
            "--match-radius-m" => {
                i += 1;
                match cli_args.get(i).and_then(|v| v.parse::<f64>().ok()) {
                    Some(v) => match_radius_m = v,
                    None => {
                        eprintln!("[ingest_tourism] --match-radius-m 뒤에 유효한 숫자가 없습니다");
                        std::process::exit(1);
                    }
                }
            }
            other => {
                eprintln!("[ingest_tourism] 알 수 없는 인자 무시: {other}");
            }
        }
        i += 1;
    }

    Args {
        osm_geojsonseq,
        std_csv,
        output,
        match_radius_m,
    }
}

// ── main ─────────────────────────────────────────────────────────

fn main() {
    let args = parse_args();
    println!(
        "[ingest_tourism] osm_geojsonseq={} std_csv={} output={} match_radius_m={}",
        args.osm_geojsonseq.display(),
        args.std_csv.display(),
        args.output.display(),
        args.match_radius_m
    );

    let mut stats = IngestStats::default();

    let features = match read_osm_geojsonseq(&args.osm_geojsonseq) {
        Ok(f) => f,
        Err(e) => {
            eprintln!(
                "[ingest_tourism] OSM geojsonseq 읽기 실패({}): {e}",
                args.osm_geojsonseq.display()
            );
            std::process::exit(1);
        }
    };

    let mut osm_entries = Vec::new();
    for feature in &features {
        stats.osm_total_features += 1;
        if let Some(entry) = process_osm_feature(feature, &mut stats) {
            *stats.osm_kept_by_category.entry(entry.category).or_insert(0) += 1;
            osm_entries.push(entry);
        }
    }

    if osm_entries.is_empty() {
        eprintln!("[ingest_tourism] 경고: OSM에서 채택된 관광지 항목이 0건입니다 — 태그 필터를 확인하세요.");
    }

    let std_rows = if args.std_csv.exists() {
        match read_std_csv(&args.std_csv, &mut stats) {
            Ok(rows) => {
                println!(
                    "[ingest_tourism] 표준데이터 CSV 읽음: {}행 ({}건 유효)",
                    stats.std_total_rows,
                    rows.len()
                );
                Some(rows)
            }
            Err(e) => {
                eprintln!(
                    "[ingest_tourism] 표준데이터 CSV 읽기 실패({}): {e} — OSM 단독으로 진행합니다.",
                    args.std_csv.display()
                );
                None
            }
        }
    } else {
        println!(
            "[ingest_tourism] 표준데이터 CSV 없음({}) — OSM 단독으로 진행합니다.",
            args.std_csv.display()
        );
        None
    };

    let (entries, merge_stats) = match std_rows {
        Some(rows) => merge_osm_and_std(osm_entries, rows, args.match_radius_m),
        None => (
            osm_entries.into_iter().map(TourismEntry::from).collect(),
            MergeStats::default(),
        ),
    };

    let final_by_category = match write_db(&args.output, &entries) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("[ingest_tourism] DB 쓰기 실패({}): {e}", args.output.display());
            std::process::exit(1);
        }
    };

    let db_size = fs::metadata(&args.output).map(|m| m.len()).unwrap_or(0);
    print_summary(&stats, &merge_stats, &final_by_category, db_size);
}

// ── 단위 테스트 ───────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn tags_map(pairs: &[(&str, &str)]) -> Map<String, Value> {
        let mut m = Map::new();
        for (k, v) in pairs {
            m.insert((*k).to_string(), Value::String((*v).to_string()));
        }
        m
    }

    // ── 카테고리 분류 ──────────────────────────────────────────

    #[test]
    fn viewpoint_takes_priority() {
        let tags = tags_map(&[("tourism", "viewpoint"), ("name", "전망대")]);
        assert_eq!(classify_osm_tags(&tags, Some("전망대")), Some(Category::Viewpoint));
    }

    #[test]
    fn national_park_is_tourist_spot() {
        let tags = tags_map(&[("boundary", "national_park")]);
        assert_eq!(classify_osm_tags(&tags, None), Some(Category::TouristSpot));
    }

    #[test]
    fn attraction_and_museum_are_tourist_spot() {
        assert_eq!(
            classify_osm_tags(&tags_map(&[("tourism", "attraction")]), None),
            Some(Category::TouristSpot)
        );
        assert_eq!(
            classify_osm_tags(&tags_map(&[("tourism", "museum")]), None),
            Some(Category::TouristSpot)
        );
    }

    #[test]
    fn historic_any_value_is_tourist_spot() {
        let tags = tags_map(&[("historic", "memorial")]);
        assert_eq!(classify_osm_tags(&tags, None), Some(Category::TouristSpot));
    }

    #[test]
    fn nature_reserve_is_tourist_spot() {
        let tags = tags_map(&[("leisure", "nature_reserve")]);
        assert_eq!(classify_osm_tags(&tags, None), Some(Category::TouristSpot));
    }

    #[test]
    fn named_peak_is_tourist_spot() {
        let tags = tags_map(&[("natural", "peak")]);
        assert_eq!(
            classify_osm_tags(&tags, Some("설악산")),
            Some(Category::TouristSpot)
        );
    }

    #[test]
    fn unnamed_peak_is_excluded() {
        let tags = tags_map(&[("natural", "peak")]);
        assert_eq!(classify_osm_tags(&tags, None), None);
        assert_eq!(classify_osm_tags(&tags, Some("  ")), None);
    }

    #[test]
    fn unrelated_tags_are_excluded() {
        let tags = tags_map(&[("shop", "bakery")]);
        assert_eq!(classify_osm_tags(&tags, Some("빵집")), None);
    }

    // ── 이름 폴백 ────────────────────────────────────────────────

    #[test]
    fn name_fallback_chain() {
        assert_eq!(
            extract_name(&tags_map(&[("name", "선운산도립공원")])),
            Some("선운산도립공원".to_string())
        );
        assert_eq!(
            extract_name(&tags_map(&[("name:ko", "우도")])),
            Some("우도".to_string())
        );
        assert_eq!(extract_name(&tags_map(&[("shop", "bakery")])), None);
    }

    // ── 지오메트리 centroid ────────────────────────────────────

    #[test]
    fn point_centroid_is_the_point_itself() {
        let geom = json!({"type": "Point", "coordinates": [127.5, 37.5]});
        assert_eq!(centroid_of_geometry(&geom), Some((37.5, 127.5)));
    }

    #[test]
    fn linestring_centroid_is_vertex_average() {
        let geom = json!({"type": "LineString", "coordinates": [[0.0, 0.0], [2.0, 2.0]]});
        assert_eq!(centroid_of_geometry(&geom), Some((1.0, 1.0)));
    }

    #[test]
    fn multipolygon_centroid_is_outer_ring_average() {
        // 사각형 [0,0]-[2,0]-[2,2]-[0,2]-[0,0] (닫힌 링, 첫점=끝점 중복 포함).
        let geom = json!({
            "type": "MultiPolygon",
            "coordinates": [[[[0.0,0.0],[2.0,0.0],[2.0,2.0],[0.0,2.0],[0.0,0.0]]]]
        });
        let (lat, lon) = centroid_of_geometry(&geom).unwrap();
        assert!((lat - 0.8).abs() < 1e-9); // (0+0+2+2+0)/5 = 0.8
        assert!((lon - 0.8).abs() < 1e-9);
    }

    #[test]
    fn unknown_geometry_type_returns_none() {
        let geom = json!({"type": "GeometryCollection", "coordinates": []});
        assert_eq!(centroid_of_geometry(&geom), None);
    }

    // ── 거리 계산 ────────────────────────────────────────────────

    #[test]
    fn haversine_same_point_is_zero() {
        assert!(haversine_m(37.5, 127.0, 37.5, 127.0) < 1e-6);
    }

    #[test]
    fn haversine_one_degree_latitude_is_about_111km() {
        let d = haversine_m(37.0, 127.0, 38.0, 127.0);
        assert!((d - 111_195.0).abs() < 2000.0, "실제 거리: {d}");
    }

    // ── 표준데이터 CSV 파싱 ────────────────────────────────────

    fn std_record(fields: &[&str]) -> StringRecord {
        StringRecord::from(fields.to_vec())
    }

    #[test]
    fn valid_std_row_is_kept() {
        let rec = std_record(&[
            "농월정", "관광지", "경남 함양군 안의면 농월정길 9-35", "경남 함양군 안의면 월림리 727-1",
            "35.62464301", "127.7815571", "화림동 정자 문화의 대표", "함양군청",
        ]);
        match parse_std_row(&rec) {
            StdRowOutcome::Kept(row) => {
                assert_eq!(row.name, "농월정");
                assert_eq!(row.category, Category::TouristSpot);
                assert!((row.lat - 35.62464301).abs() < 1e-9);
            }
            StdRowOutcome::Invalid => panic!("정상 행은 Kept여야 함"),
        }
    }

    #[test]
    fn std_row_with_viewpoint_keyword_is_classified_as_viewpoint() {
        let rec = std_record(&["OO전망대", "전망대", "", "", "35.0", "127.0", "", ""]);
        match parse_std_row(&rec) {
            StdRowOutcome::Kept(row) => assert_eq!(row.category, Category::Viewpoint),
            StdRowOutcome::Invalid => panic!("정상 행은 Kept여야 함"),
        }
    }

    #[test]
    fn std_row_missing_name_is_invalid() {
        let rec = std_record(&["", "관광지", "", "", "35.0", "127.0", "", ""]);
        assert!(matches!(parse_std_row(&rec), StdRowOutcome::Invalid));
    }

    #[test]
    fn std_row_invalid_coords_is_invalid() {
        let rec = std_record(&["농월정", "관광지", "", "", "not_a_number", "127.0", "", ""]);
        assert!(matches!(parse_std_row(&rec), StdRowOutcome::Invalid));
    }

    // ── 좌표 근접 매칭 병합 ────────────────────────────────────

    fn osm_entry(category: Category, name: &str, lat: f64, lon: f64) -> OsmEntry {
        OsmEntry {
            category,
            name: Some(name.to_string()),
            lat,
            lon,
            osm_type: "node".to_string(),
            osm_id: 1,
            tags_json: "{}".to_string(),
        }
    }

    fn std_row(name: &str, lat: f64, lon: f64) -> StdRow {
        StdRow {
            name: name.to_string(),
            category: Category::TouristSpot,
            road_addr: Some("도로명주소".to_string()),
            lot_addr: None,
            lat,
            lon,
            description: Some("설명".to_string()),
            institution: None,
        }
    }

    #[test]
    fn nearby_std_row_merges_into_osm_entry_and_enriches_name() {
        let osm = vec![osm_entry(Category::TouristSpot, "Nongwoljeong", 35.6246, 127.7816)];
        // 약 10m 근처 좌표.
        let std = vec![std_row("농월정", 35.62469, 127.78161)];
        let (entries, stats) = merge_osm_and_std(osm, std, 80.0);
        assert_eq!(entries.len(), 1, "근접 매칭되면 새 엔트리를 추가하지 않아야 함");
        assert_eq!(entries[0].name.as_deref(), Some("농월정"));
        assert_eq!(entries[0].source, "osm+data_go_kr");
        assert_eq!(entries[0].address.as_deref(), Some("도로명주소"));
        assert_eq!(stats.std_matched_into_osm, 1);
        assert_eq!(stats.std_added_standalone, 0);
    }

    #[test]
    fn far_std_row_is_added_standalone() {
        let osm = vec![osm_entry(Category::TouristSpot, "OSM곳", 35.0, 127.0)];
        // 약 100km 이상 떨어진 좌표 — 매칭 안 됨.
        let std = vec![std_row("먼관광지", 36.0, 128.0)];
        let (entries, stats) = merge_osm_and_std(osm, std, 80.0);
        assert_eq!(entries.len(), 2);
        assert_eq!(stats.std_added_standalone, 1);
        assert_eq!(stats.std_matched_into_osm, 0);
        let standalone = entries.iter().find(|e| e.name.as_deref() == Some("먼관광지")).unwrap();
        assert_eq!(standalone.source, "data_go_kr");
        assert!(standalone.osm_id.is_none());
    }

    #[test]
    fn radius_boundary_is_respected() {
        // 정확히 반경 밖(약 90m)에 있는 경우 매칭되지 않아야 한다.
        let osm = vec![osm_entry(Category::TouristSpot, "지점", 35.0, 127.0)];
        let std = vec![std_row("근처아님", 35.00081, 127.0)]; // 위도 0.00081도 ≈ 90m
        let (entries, stats) = merge_osm_and_std(osm, std, 80.0);
        assert_eq!(stats.std_matched_into_osm, 0);
        assert_eq!(entries.len(), 2);
    }
}
