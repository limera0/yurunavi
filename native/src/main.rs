mod api;
use api::{
    calc_tortuosity, calc_winding_score, check_destination_reachable,
    check_gps_accuracy, check_route_similarity, fun_score_v2, fun_score_v3, haversine_m,
    is_off_route, GpsPoint, GpsQuality, WindingScore,
};

const VALHALLA_URL: &str = "http://localhost:8002/route";

static HTTP_CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
fn http_client() -> &'static reqwest::Client {
    HTTP_CLIENT.get_or_init(reqwest::Client::new)
}

// POI(카페/편의점/주유소/마트/식당) SQLite DB — `native/src/bin/ingest_poi.rs`가 분기별로
// 전체 재적재하는 파일. `ingest_poi`의 기본 --output 경로와 동일하게 고정 상수로 둔다
// (기존 VALHALLA_URL과 동일한 하드코딩 관례를 따름 — 배포 설정은 별도 스텝 소관).
const POI_DB_PATH: &str = "/data/poi/poi.db";

use axum::{
    extract::{Json, Query},
    http::StatusCode,
    routing::{get, post},
    Router,
};
use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};

// ── Serde-compatible DTOs ──────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
struct GpsPointDto {
    lat: f64,
    lng: f64,
}

impl From<GpsPointDto> for GpsPoint {
    fn from(p: GpsPointDto) -> Self {
        GpsPoint { lat: p.lat, lng: p.lng }
    }
}

impl From<GpsPoint> for GpsPointDto {
    fn from(p: GpsPoint) -> Self {
        GpsPointDto { lat: p.lat, lng: p.lng }
    }
}

// ── Valhalla polyline6 decoder ─────────────────────────────────

fn decode_polyline6(encoded: &str) -> Vec<GpsPointDto> {
    let mut result = Vec::new();
    let bytes = encoded.as_bytes();
    let mut i = 0usize;
    let mut lat = 0i64;
    let mut lng = 0i64;
    while i < bytes.len() {
        for coord in [&mut lat, &mut lng] {
            let mut acc = 0i64;
            let mut shift = 0u32;
            loop {
                if i >= bytes.len() { break; }
                let b = bytes[i] as i64 - 63;
                i += 1;
                acc |= (b & 0x1f) << shift;
                shift += 5;
                if b < 0x20 { break; }
            }
            let delta = if acc & 1 != 0 { !(acc >> 1) } else { acc >> 1 };
            *coord += delta;
        }
        result.push(GpsPointDto { lat: lat as f64 / 1e6, lng: lng as f64 / 1e6 });
    }
    result
}

fn extract_trip_points(resp: &serde_json::Value) -> Vec<GpsPointDto> {
    let legs = match resp["trip"]["legs"].as_array() {
        Some(l) => l,
        None => return Vec::new(),
    };
    let mut pts: Vec<GpsPointDto> = Vec::new();
    for (i, leg) in legs.iter().enumerate() {
        let shape = leg["shape"].as_str().unwrap_or("");
        let decoded = decode_polyline6(shape);
        if i == 0 {
            pts.extend(decoded);
        } else {
            pts.extend(decoded.into_iter().skip(1));
        }
    }
    pts
}

// ── trace_attributes helpers ───────────────────────────────────

fn road_class_to_fc(road_class: &str) -> f64 {
    match road_class {
        "motorway"  => 1.0,
        "trunk"     => 2.0,
        "primary"   => 3.0,
        "secondary" => 4.0,
        _ => 5.0, // tertiary, unclassified, residential, service_other
    }
}

fn weighted_avg_fc(ta_resp: &serde_json::Value) -> f64 {
    let edges = match ta_resp["edges"].as_array() {
        Some(e) => e,
        None => return 3.0,
    };
    let mut total_len = 0.0_f64;
    let mut weighted = 0.0_f64;
    for edge in edges {
        let rc = edge["road_class"].as_str().unwrap_or("primary");
        let fc = road_class_to_fc(rc);
        let len = edge["length"].as_f64().unwrap_or(0.1);
        weighted += fc * len;
        total_len += len;
    }
    if total_len > 0.0 { weighted / total_len } else { 3.0 }
}

fn weighted_avg_speed(ta_resp: &serde_json::Value) -> f64 {
    let edges = match ta_resp["edges"].as_array() {
        Some(e) => e,
        None => return 50.0,
    };
    let mut total_len = 0.0_f64;
    let mut weighted = 0.0_f64;
    for edge in edges {
        let speed = edge["speed"].as_f64().unwrap_or(50.0);
        let len   = edge["length"].as_f64().unwrap_or(0.1);
        weighted += speed * len;
        total_len += len;
    }
    if total_len > 0.0 { weighted / total_len } else { 50.0 }
}

async fn trace_attributes_fc(client: &reqwest::Client, pts: &[GpsPointDto]) -> (f64, f64) {
    if pts.is_empty() { return (3.0, 50.0); }
    let step = (pts.len() / 80).max(1);
    let shape: Vec<serde_json::Value> = pts.iter().step_by(step)
        .map(|p| serde_json::json!({"lat": p.lat, "lon": p.lng}))
        .collect();
    let payload = serde_json::json!({
        "shape": shape,
        "costing": "motorcycle",
        "shape_match": "map_snap",
        "filters": {
            "attributes": ["edge.road_class", "edge.length", "edge.speed"],
            "action": "include"
        }
    });
    let ta_resp: serde_json::Value = match client
        .post("http://localhost:8002/trace_attributes")
        .json(&payload)
        .send()
        .await
    {
        Ok(r) => r.json().await.unwrap_or_default(),
        Err(_) => return (3.0, 50.0),
    };
    (weighted_avg_fc(&ta_resp), weighted_avg_speed(&ta_resp))
}

// ── /calc_route ────────────────────────────────────────────────

#[derive(Deserialize)]
struct CalcRouteReq {
    origin: GpsPointDto,
    destination: GpsPointDto,
    #[serde(default)]
    waypoints: Vec<GpsPointDto>,
    #[serde(default)]
    route_type: i32,
}

#[derive(Serialize)]
struct CalcRouteResp {
    points: Vec<GpsPointDto>,
    total_distance_m: f64,
    winding_score: f64,
    road_type: String,
    fun_score_v2: f64,    // curvature 60% + FC road class 40%
    avg_fc: f64,          // Valhalla Functional Class average (1.0-5.0)
    avg_speed_kmh: f64,   // edge speed weighted average (km/h)
    fun_score_v3: f64,    // curvature 50% + FC 30% + traffic(speed) 20%
}

#[derive(Deserialize)]
struct ScoreRouteReq {
    points: Vec<GpsPointDto>,
}

#[derive(Serialize)]
struct ScoreRouteResp {
    fun_score_v2: f64,
    fun_score_v3: f64,
    avg_fc: f64,
    avg_speed_kmh: f64,
    curvature_tau: f64,
}

async fn handle_calc_route(
    Json(req): Json<CalcRouteReq>,
) -> Result<Json<CalcRouteResp>, StatusCode> {
    let client = http_client();

    // Build Valhalla locations array
    let locs: serde_json::Value = {
        let mut v = vec![serde_json::json!({"lat": req.origin.lat, "lon": req.origin.lng})];
        for w in &req.waypoints {
            v.push(serde_json::json!({"lat": w.lat, "lon": w.lng}));
        }
        v.push(serde_json::json!({"lat": req.destination.lat, "lon": req.destination.lng}));
        serde_json::Value::Array(v)
    };

    // Valhalla payloads (matching routing_service.dart profiles)
    let rural_payload = serde_json::json!({
        "locations": locs.clone(),
        "costing": "motorcycle",
        "costing_options": { "motorcycle": {
            "use_highways": 0.0, "use_living_streets": 1.0, "use_tracks": 0.8, "top_speed": 40,
            "class_factors": {"1": 100.0, "2": 5.0, "3": 2.5, "4": 1.0, "5": 0.2},
            "urban_penalty": 50.0
        }}
    });
    let prov_payload = serde_json::json!({
        "locations": locs.clone(),
        "costing": "motorcycle",
        "costing_options": { "motorcycle": {
            "use_highways": 0.0, "use_living_streets": 0.5, "use_tracks": 0.2,
            "class_factors": {"1": 100.0, "2": 2.0, "3": 0.5, "4": 0.7, "5": 1.5}
        }}
    });
    let natl_payload = serde_json::json!({
        "locations": locs.clone(),
        "costing": "motorcycle",
        "costing_options": { "motorcycle": {
            "use_highways": 0.0, "use_living_streets": 0.0, "use_tracks": 0.0, "shortest": true,
            "class_factors": {"1": 100.0, "2": 0.4, "3": 1.0, "4": 2.0, "5": 10.0}
        }}
    });

    let winner: serde_json::Value = if req.route_type == 0 {
        // 시골길: parallel rural + provincial, then 1.3x fallback check
        let (r_res, p_res) = tokio::try_join!(
            client.post(VALHALLA_URL).json(&rural_payload).send(),
            client.post(VALHALLA_URL).json(&prov_payload).send(),
        ).map_err(|_| StatusCode::BAD_GATEWAY)?;

        let r_json: serde_json::Value = r_res.json().await.map_err(|_| StatusCode::BAD_GATEWAY)?;
        let p_json: serde_json::Value = p_res.json().await.map_err(|_| StatusCode::BAD_GATEWAY)?;

        let t_rural = r_json["trip"]["summary"]["time"].as_f64().unwrap_or(f64::MAX);
        let t_prov  = p_json["trip"]["summary"]["time"].as_f64().unwrap_or(1.0);

        if t_rural / t_prov >= 1.3 {
            // Balanced: soften rural FC constraints toward provincial
            let balanced = serde_json::json!({
                "locations": locs,
                "costing": "motorcycle",
                "costing_options": { "motorcycle": {
                    "use_highways": 0.0,
                    "class_factors": {"1": 100.0, "2": 4.0, "3": 1.2, "4": 0.8, "5": 0.5}
                }}
            });
            client.post(VALHALLA_URL).json(&balanced).send().await
                .map_err(|_| StatusCode::BAD_GATEWAY)?
                .json().await
                .map_err(|_| StatusCode::BAD_GATEWAY)?
        } else {
            r_json
        }
    } else {
        let payload = if req.route_type == 1 { prov_payload } else { natl_payload };
        client.post(VALHALLA_URL).json(&payload).send().await
            .map_err(|_| StatusCode::BAD_GATEWAY)?
            .json().await
            .map_err(|_| StatusCode::BAD_GATEWAY)?
    };

    let pts = extract_trip_points(&winner);
    let km: f64 = winner["trip"]["legs"].as_array()
        .map(|legs| {
            legs.iter()
                .map(|l| l["summary"]["length"].as_f64().unwrap_or(0.0))
                .sum()
        })
        .unwrap_or(0.0);

    let api_pts: Vec<GpsPoint> = pts.iter().map(|p| GpsPoint { lat: p.lat, lng: p.lng }).collect();
    let winding = if api_pts.len() >= 3 {
        calc_winding_score(api_pts.clone())
    } else {
        WindingScore { score: 0.0, road_type: "national".to_string() }
    };

    let (avg_fc, avg_speed) = trace_attributes_fc(client, &pts).await;
    let f_score_v2 = fun_score_v2(&api_pts, avg_fc);
    let f_score_v3 = fun_score_v3(&api_pts, avg_fc, avg_speed);

    Ok(Json(CalcRouteResp {
        points: pts,
        total_distance_m: km * 1000.0,
        winding_score: winding.score,
        road_type: winding.road_type,
        fun_score_v2: f_score_v2,
        avg_fc,
        avg_speed_kmh: avg_speed,
        fun_score_v3: f_score_v3,
    }))
}

// ── /score_route ───────────────────────────────────────────────

async fn handle_score_route(
    Json(req): Json<ScoreRouteReq>,
) -> Json<ScoreRouteResp> {
    let client = http_client();
    let (avg_fc, avg_speed) = trace_attributes_fc(client, &req.points).await;
    let api_pts: Vec<GpsPoint> = req.points.iter()
        .map(|p| GpsPoint { lat: p.lat, lng: p.lng })
        .collect();
    let f_score_v2 = if api_pts.len() >= 2 {
        fun_score_v2(&api_pts, avg_fc)
    } else {
        0.0
    };
    let f_score_v3 = if api_pts.len() >= 2 {
        fun_score_v3(&api_pts, avg_fc, avg_speed)
    } else {
        0.0
    };
    let tau = if api_pts.len() >= 2 {
        calc_tortuosity(&api_pts)
    } else {
        1.0
    };
    Json(ScoreRouteResp {
        fun_score_v2: f_score_v2,
        fun_score_v3: f_score_v3,
        avg_fc,
        avg_speed_kmh: avg_speed,
        curvature_tau: tau,
    })
}

// ── /calc_winding_score ────────────────────────────────────────

#[derive(Deserialize)]
struct WindingReq {
    route: Vec<GpsPointDto>,
}

#[derive(Serialize)]
struct WindingResp {
    score: f64,
    road_type: String,
}

async fn handle_winding(Json(req): Json<WindingReq>) -> Json<WindingResp> {
    let result = calc_winding_score(req.route.into_iter().map(Into::into).collect());
    Json(WindingResp { score: result.score, road_type: result.road_type })
}

// ── /check_route_similarity ────────────────────────────────────

#[derive(Deserialize)]
struct SimilarityReq {
    route_a: Vec<GpsPointDto>,
    route_b: Vec<GpsPointDto>,
}

#[derive(Serialize)]
struct SimilarityResp {
    score: f64,
    is_duplicate: bool,
}

async fn handle_similarity(Json(req): Json<SimilarityReq>) -> Json<SimilarityResp> {
    let result = check_route_similarity(
        req.route_a.into_iter().map(Into::into).collect(),
        req.route_b.into_iter().map(Into::into).collect(),
    );
    Json(SimilarityResp { score: result.score, is_duplicate: result.is_duplicate })
}

// ── /check_gps_accuracy ────────────────────────────────────────

#[derive(Deserialize)]
struct GpsAccuracyReq {
    accuracy_m: f64,
    age_ms: u64,
}

#[derive(Serialize)]
struct GpsAccuracyResp {
    quality: String,
}

async fn handle_gps_accuracy(Json(req): Json<GpsAccuracyReq>) -> Json<GpsAccuracyResp> {
    let quality = check_gps_accuracy(req.accuracy_m, req.age_ms);
    let quality_str = match quality {
        GpsQuality::Good => "good",
        GpsQuality::Degraded => "degraded",
        GpsQuality::Poor => "poor",
    };
    Json(GpsAccuracyResp { quality: quality_str.to_string() })
}

// ── /is_off_route ──────────────────────────────────────────────

#[derive(Deserialize)]
struct OffRouteReq {
    current: GpsPointDto,
    route: Vec<GpsPointDto>,
    #[serde(default = "default_threshold")]
    threshold_m: f64,
}

fn default_threshold() -> f64 { 150.0 }

#[derive(Serialize)]
struct OffRouteResp {
    is_off_route: bool,
    closest_point_distance_m: f64,
    threshold_m: f64,
}

async fn handle_off_route(Json(req): Json<OffRouteReq>) -> Json<OffRouteResp> {
    let result = is_off_route(
        req.current.into(),
        req.route.into_iter().map(Into::into).collect(),
        req.threshold_m,
    );
    Json(OffRouteResp {
        is_off_route: result.is_off_route,
        closest_point_distance_m: result.closest_point_distance_m,
        threshold_m: result.threshold_m,
    })
}

// ── /check_destination_reachable ──────────────────────────────

#[derive(Deserialize)]
struct ReachabilityReq {
    origin: GpsPointDto,
    destination: GpsPointDto,
}

#[derive(Serialize)]
struct ReachabilityResp {
    is_reachable: bool,
    reason: String,
}

async fn handle_reachability(Json(req): Json<ReachabilityReq>) -> Json<ReachabilityResp> {
    let result = check_destination_reachable(req.origin.into(), req.destination.into());
    Json(ReachabilityResp { is_reachable: result.is_reachable, reason: result.reason })
}

// ── /poi/nearby ────────────────────────────────────────────────

/// POI DB 연결 상태. `None`이면 DB 파일이 없거나 열 수 없는 상태 —
/// 서버 전체를 죽이지 않고 `/poi/nearby`만 503을 반환한다(다른 엔드포인트는 정상 동작).
static POI_DB: std::sync::OnceLock<Option<std::sync::Mutex<Connection>>> =
    std::sync::OnceLock::new();

fn poi_db() -> &'static Option<std::sync::Mutex<Connection>> {
    POI_DB.get_or_init(|| {
        match Connection::open_with_flags(POI_DB_PATH, OpenFlags::SQLITE_OPEN_READ_ONLY) {
            Ok(conn) => {
                println!("[YuruNavi/Rust] POI DB 연결 성공: {POI_DB_PATH}");
                Some(std::sync::Mutex::new(conn))
            }
            Err(e) => {
                eprintln!(
                    "[YuruNavi/Rust] 경고: POI DB 연결 실패({POI_DB_PATH}): {e} \
                     — /poi/nearby 는 503을 반환합니다 (다른 엔드포인트는 정상 동작)"
                );
                None
            }
        }
    })
}

const ALL_POI_CATEGORIES: [&str; 5] = [
    "cafe",
    "convenience_store",
    "gas_station",
    "supermarket",
    "restaurant",
];
const MAX_POI_RADIUS_M: f64 = 5000.0;

/// 응답에 담을 최대 POI 개수(거리순 정렬 후 상위 N개만). 클라이언트는 ambient
/// 레이어에서 최대 20개만 화면에 그리고(`selectForAmbientDisplay`), 검색시트도
/// 스크롤 리스트일 뿐이라 수천 건을 다 받을 이유가 없다 — 실측(2026-07-15,
/// 서울 중심가 반경 1500m 전카테고리) 6,125건/1.1MB 응답이 확인됨. 500이면
/// ambient 레이어의 grid 기반 분산 선택(gridSize=4=16칸)에 칸당 평균 30개
/// 이상 후보가 남아 다양성엔 지장이 없고, 응답 크기는 최악의 경우에도
/// 수십 KB대로 줄어든다.
const MAX_POI_RESULTS: usize = 500;

/// bbox 모드에서 위도/경도 폭 각각의 상한(도). 클라이언트가 국가 전체 같은
/// 비현실적으로 큰 영역을 한 번에 요청하지 못하도록 막는 가드레일 — 오토바이
/// 내비 지도 뷰포트는 절대 이 크기에 도달하지 않으므로 실제로는 발동하지 않아야 정상.
/// 초과 시 자르지 않고 명시적으로 400을 반환한다(자르면 클라이언트가 예상한
/// 사각형과 다른 모양의 응답을 받게 되어 오히려 헷갈림).
const MAX_BBOX_SPAN_DEG: f64 = 0.5;

/// `/poi/nearby`는 두 가지 쿼리 모드를 지원한다:
/// - bbox 모드: south/west/north/east 4개 모두 존재 — 뷰포트 사각형을 그대로 rtree 쿼리에 사용.
/// - radius 모드: lat/lon/radius_m 모두 존재 — 기존 중심점+반경 모드(변경 없음).
/// 둘 다 아니거나 bbox 4개 중 일부만 있으면 400 (조용히 추측하지 않는다).
#[derive(Deserialize)]
struct PoiNearbyQuery {
    lat: Option<f64>,
    lon: Option<f64>,
    radius_m: Option<f64>,
    south: Option<f64>,
    west: Option<f64>,
    north: Option<f64>,
    east: Option<f64>,
    #[serde(default)]
    types: Option<String>,
}

/// `PoiNearbyQuery`에서 뽑아낸, 모호함이 없는 쿼리 모드.
#[derive(Debug, PartialEq)]
enum PoiQueryMode {
    Bbox { south: f64, west: f64, north: f64, east: f64 },
    Radius { lat: f64, lon: f64, radius_m: f64 },
}

/// 쿼리 파라미터에서 실제로 어떤 모드를 쓸지 결정한다. HTTP/axum 없이 단위
/// 테스트 가능하도록 순수 함수로 분리했다.
///
/// - south/west/north/east 4개 모두 존재 → Bbox
/// - 4개 중 1~3개만 존재 → Err (부분 bbox는 조용히 추측하지 않고 명시적으로 거부)
/// - lat/lon/radius_m 모두 존재 → Radius
/// - 그 외(완전히 비어있거나 radius 필드 일부만 존재) → Err
fn resolve_poi_query_mode(q: &PoiNearbyQuery) -> Result<PoiQueryMode, ()> {
    let bbox_present = [q.south, q.west, q.north, q.east]
        .iter()
        .filter(|v| v.is_some())
        .count();

    if bbox_present == 4 {
        return Ok(PoiQueryMode::Bbox {
            south: q.south.unwrap(),
            west: q.west.unwrap(),
            north: q.north.unwrap(),
            east: q.east.unwrap(),
        });
    }
    if bbox_present > 0 {
        return Err(()); // 일부만 지정 — 애매하므로 거부
    }

    if let (Some(lat), Some(lon), Some(radius_m)) = (q.lat, q.lon, q.radius_m) {
        return Ok(PoiQueryMode::Radius { lat, lon, radius_m });
    }

    Err(())
}

/// bbox 모드의 면적 가드레일. south>=north 또는 west>=east(뒤집힌/퇴화된 bbox)이거나
/// 위도/경도 폭이 [MAX_BBOX_SPAN_DEG]를 초과하면 false.
fn bbox_span_valid(south: f64, west: f64, north: f64, east: f64) -> bool {
    let lat_span = north - south;
    let lon_span = east - west;
    lat_span > 0.0
        && lon_span > 0.0
        && lat_span <= MAX_BBOX_SPAN_DEG
        && lon_span <= MAX_BBOX_SPAN_DEG
}

#[derive(Serialize)]
struct PoiDto {
    id: String,
    name: String,
    category: String,
    lat: f64,
    lon: f64,
    address: Option<String>,
}

/// 반경(m) 기반 bbox 근사 계산. 등장방형(equirectangular) 근사를 사용한다
/// (반경이 커도 5km로 클램프되므로 위도 왜곡이 크지 않음).
/// 반환: (min_lat, max_lat, min_lon, max_lon).
fn bbox_from_radius(lat: f64, lon: f64, radius_m: f64) -> (f64, f64, f64, f64) {
    let d_lat = radius_m / 111_320.0;
    let cos_lat = lat.to_radians().cos();
    let d_lon = if cos_lat.abs() > 1e-9 {
        radius_m / (111_320.0 * cos_lat)
    } else {
        // 극지방 근방(cos(lat)≈0): 경도 폭이 사실상 무의미해지므로 전체 범위로 개방.
        180.0
    };
    (lat - d_lat, lat + d_lat, lon - d_lon, lon + d_lon)
}

/// rtree bbox 후보 조회 + IN 카테고리 필터 + 정확한 haversine 거리 필터/정렬.
/// `conn`을 인자로 받아 전역 상태(OnceLock/Mutex) 없이 단위 테스트 가능하게 분리했다.
fn query_poi_nearby(
    conn: &Connection,
    lat: f64,
    lon: f64,
    radius_m: f64,
    types: &[String],
) -> rusqlite::Result<Vec<PoiDto>> {
    let (min_lat, max_lat, min_lon, max_lon) = bbox_from_radius(lat, lon, radius_m);

    // category IN (...) — 값 개수만큼 바인드 파라미터를 만들고, 값 자체는 절대
    // 문자열로 SQL에 직접 삽입하지 않는다.
    //
    // ⚠️ CROSS JOIN 필수(일반 JOIN 아님): SQLite 쿼리 플래너가 category 인덱스를
    // driving table로 잘못 선택해 poi_rtree를 행마다 SCAN하는 계획을 세우는
    // 경우가 실측 확인됨(2026-07-15, all-5-categories 조회에서 ~1.1초 — R-tree
    // 인덱스가 사실상 무용지물이 됨). CROSS JOIN은 SQLite 플래너의 테이블 순서
    // 재배치를 비활성화해 작성된 순서(rtree 먼저)를 강제한다 — 같은 쿼리가
    // 33~60배 빨라짐(1150ms → 19~35ms, EXPLAIN QUERY PLAN으로 R-tree 자체
    // 공간 인덱스가 실제로 쓰이는지 확인 완료). 카테고리 1개짜리 좁은 쿼리도
    // 동일하게 개선됨(198ms → 9.6ms) — 이 변경으로 손해 보는 케이스는 없었다.
    let placeholders: Vec<String> = (0..types.len()).map(|i| format!("?{}", i + 5)).collect();
    let sql = format!(
        "SELECT p.bizes_id, p.name, p.category, p.lat, p.lon, p.address \
         FROM poi_rtree r CROSS JOIN poi p ON p.id = r.id \
         WHERE r.min_lat <= ?2 AND r.max_lat >= ?1 \
           AND r.min_lon <= ?4 AND r.max_lon >= ?3 \
           AND p.category IN ({})",
        placeholders.join(",")
    );

    let mut stmt = conn.prepare(&sql)?;

    let mut params: Vec<&dyn rusqlite::ToSql> = vec![&min_lat, &max_lat, &min_lon, &max_lon];
    for t in types {
        params.push(t);
    }

    let rows = stmt.query_map(params.as_slice(), |row| {
        Ok(PoiDto {
            id: row.get(0)?,
            name: row.get(1)?,
            category: row.get(2)?,
            lat: row.get(3)?,
            lon: row.get(4)?,
            address: row.get(5)?,
        })
    })?;

    let mut candidates: Vec<PoiDto> = Vec::new();
    for row in rows {
        match row {
            Ok(dto) => candidates.push(dto),
            Err(e) => eprintln!("[YuruNavi/Rust] /poi/nearby row 파싱 실패(건너뜀): {e}"),
        }
    }

    // rtree는 bbox 후보만 골라주므로, 실제 반경 밖(bbox 모서리) 후보를 정확한 haversine
    // 거리로 걸러내고 거리순 오름차순 정렬한다 (기존 외부 API는 정렬이 없었던 버그 수정).
    let center = GpsPoint { lat, lng: lon };
    let mut with_dist: Vec<(f64, PoiDto)> = candidates
        .into_iter()
        .filter_map(|dto| {
            let d = haversine_m(&center, &GpsPoint { lat: dto.lat, lng: dto.lon });
            if d <= radius_m {
                Some((d, dto))
            } else {
                None
            }
        })
        .collect();
    with_dist.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    Ok(with_dist.into_iter().take(MAX_POI_RESULTS).map(|(_, dto)| dto).collect())
}

/// bbox 후보 조회 + IN 카테고리 필터 + (중심점 기준) 거리 정렬.
///
/// `query_poi_nearby`와 달리 이 bbox는 이미 정확한 목표 영역 그 자체이므로
/// haversine 반경 필터를 적용하지 않는다 — bbox 안에 있으면 전부 정답이다.
/// 정렬만 응답 순서를 기존 radius 모드(가까운 순)와 일관되게 맞추기 위해 수행한다.
fn query_poi_in_bbox(
    conn: &Connection,
    south: f64,
    west: f64,
    north: f64,
    east: f64,
    types: &[String],
) -> rusqlite::Result<Vec<PoiDto>> {
    // CROSS JOIN 필수 — query_poi_nearby와 동일 이유(위 함수 주석 참조):
    // 일반 JOIN이면 SQLite 플래너가 category 인덱스를 driving table로 잘못
    // 선택해 R-tree를 사실상 무용지물로 만든다(실측 33~60배 저하).
    let placeholders: Vec<String> = (0..types.len()).map(|i| format!("?{}", i + 5)).collect();
    let sql = format!(
        "SELECT p.bizes_id, p.name, p.category, p.lat, p.lon, p.address \
         FROM poi_rtree r CROSS JOIN poi p ON p.id = r.id \
         WHERE r.min_lat <= ?2 AND r.max_lat >= ?1 \
           AND r.min_lon <= ?4 AND r.max_lon >= ?3 \
           AND p.category IN ({})",
        placeholders.join(",")
    );

    let mut stmt = conn.prepare(&sql)?;

    let mut params: Vec<&dyn rusqlite::ToSql> = vec![&south, &north, &west, &east];
    for t in types {
        params.push(t);
    }

    let rows = stmt.query_map(params.as_slice(), |row| {
        Ok(PoiDto {
            id: row.get(0)?,
            name: row.get(1)?,
            category: row.get(2)?,
            lat: row.get(3)?,
            lon: row.get(4)?,
            address: row.get(5)?,
        })
    })?;

    let mut candidates: Vec<PoiDto> = Vec::new();
    for row in rows {
        match row {
            Ok(dto) => candidates.push(dto),
            Err(e) => eprintln!("[YuruNavi/Rust] /poi/nearby(bbox) row 파싱 실패(건너뜀): {e}"),
        }
    }

    let center = GpsPoint { lat: (south + north) / 2.0, lng: (west + east) / 2.0 };
    let mut with_dist: Vec<(f64, PoiDto)> = candidates
        .into_iter()
        .map(|dto| {
            let d = haversine_m(&center, &GpsPoint { lat: dto.lat, lng: dto.lon });
            (d, dto)
        })
        .collect();
    with_dist.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));

    Ok(with_dist.into_iter().take(MAX_POI_RESULTS).map(|(_, dto)| dto).collect())
}

async fn handle_poi_nearby(
    Query(q): Query<PoiNearbyQuery>,
) -> Result<Json<Vec<PoiDto>>, StatusCode> {
    let mutex = match poi_db() {
        Some(m) => m,
        None => return Err(StatusCode::SERVICE_UNAVAILABLE),
    };
    let conn = mutex.lock().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mode = resolve_poi_query_mode(&q).map_err(|_| StatusCode::BAD_REQUEST)?;

    let types: Vec<String> = match q.types.as_deref() {
        Some(s) if !s.trim().is_empty() => s
            .split(',')
            .map(|t| t.trim().to_string())
            .filter(|t| !t.is_empty())
            .collect(),
        _ => ALL_POI_CATEGORIES.iter().map(|s| s.to_string()).collect(),
    };
    if types.is_empty() {
        return Ok(Json(Vec::new()));
    }

    let results = match mode {
        PoiQueryMode::Bbox { south, west, north, east } => {
            if !bbox_span_valid(south, west, north, east) {
                return Err(StatusCode::BAD_REQUEST);
            }
            query_poi_in_bbox(&conn, south, west, north, east, &types)
        }
        PoiQueryMode::Radius { lat, lon, radius_m } => {
            let radius_m = radius_m.clamp(0.0, MAX_POI_RADIUS_M);
            query_poi_nearby(&conn, lat, lon, radius_m, &types)
        }
    }
    .map_err(|e| {
        eprintln!("[YuruNavi/Rust] /poi/nearby 쿼리 실패: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(results))
}

// ── /health ────────────────────────────────────────────────────

#[derive(Serialize)]
struct HealthResp {
    status: &'static str,
}

async fn handle_health() -> Json<HealthResp> {
    Json(HealthResp { status: "ok" })
}

// ── Main ───────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    // POI DB는 여기서 한 번 열어둔다(OnceLock 초기화). 실패해도 서버는 계속 뜨고
    // /poi/nearby만 503을 반환한다 — poi_db() 내부에서 로그로 알린다.
    poi_db();

    let app = Router::new()
        .route("/health", get(handle_health))
        .route("/calc_route", post(handle_calc_route))
        .route("/score_route", post(handle_score_route))
        .route("/calc_winding_score", post(handle_winding))
        .route("/check_route_similarity", post(handle_similarity))
        .route("/check_gps_accuracy", post(handle_gps_accuracy))
        .route("/is_off_route", post(handle_off_route))
        .route("/check_destination_reachable", post(handle_reachability))
        .route("/poi/nearby", get(handle_poi_nearby));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8003")
        .await
        .expect("포트 8003 바인딩 실패");
    println!("[YuruNavi/Rust] 서버 시작 — http://0.0.0.0:8003");
    axum::serve(listener, app).await.unwrap();
}

// ── 단위 테스트 ───────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::params;

    #[test]
    fn bbox_from_radius_seoul_1km_is_symmetric_and_reasonable() {
        // 서울시청 부근, 반경 1000m.
        let (min_lat, max_lat, min_lon, max_lon) = bbox_from_radius(37.5665, 126.9780, 1000.0);
        assert!(min_lat < 37.5665 && max_lat > 37.5665);
        assert!(min_lon < 126.9780 && max_lon > 126.9780);
        // 위도 1km ≈ 0.00898도.
        assert!((37.5665 - min_lat - 0.00898).abs() < 0.001);
        assert!((max_lat - 37.5665 - 0.00898).abs() < 0.001);
        // 경도 폭은 cos(lat) 보정으로 위도 폭보다 넓어야 한다(고위도일수록).
        assert!((max_lon - min_lon) > (max_lat - min_lat));
    }

    #[test]
    fn bbox_from_radius_zero_radius_collapses_to_point() {
        let (min_lat, max_lat, min_lon, max_lon) = bbox_from_radius(37.0, 127.0, 0.0);
        assert!((min_lat - 37.0).abs() < 1e-9);
        assert!((max_lat - 37.0).abs() < 1e-9);
        assert!((min_lon - 127.0).abs() < 1e-9);
        assert!((max_lon - 127.0).abs() < 1e-9);
    }

    #[test]
    fn bbox_from_radius_at_pole_does_not_panic_or_produce_nan() {
        // cos(90°)≈0 — 분모 0 근접 가드가 없으면 경도 폭이 발산(NaN/Inf)할 수 있음.
        let (min_lat, max_lat, min_lon, max_lon) = bbox_from_radius(90.0, 127.0, 1000.0);
        assert!(min_lat.is_finite() && max_lat.is_finite());
        assert!(min_lon.is_finite() && max_lon.is_finite());
        // 가드 발동 시 경도 폭을 전체 범위(360도)로 개방한다.
        assert!((max_lon - min_lon - 360.0).abs() < 1e-6);
    }

    #[test]
    fn poi_radius_clamped_to_max() {
        assert_eq!(50_000.0_f64.clamp(0.0, MAX_POI_RADIUS_M), MAX_POI_RADIUS_M);
        assert_eq!((-10.0_f64).clamp(0.0, MAX_POI_RADIUS_M), 0.0);
        assert_eq!(2000.0_f64.clamp(0.0, MAX_POI_RADIUS_M), 2000.0);
    }

    #[test]
    fn all_poi_categories_has_five_entries() {
        assert_eq!(ALL_POI_CATEGORIES.len(), 5);
    }

    // ── query_poi_nearby: 실제 rusqlite(bundled, rtree) 기반 end-to-end 검증 ──
    //
    // 파일시스템/네트워크에 손대지 않도록 in-memory DB를 사용한다(이미 8003 포트에
    // 운영 중인 yurunavi_server 프로세스가 있어 실제 HTTP 스모크 테스트는 생략).

    fn setup_in_memory_poi_db() -> Connection {
        let conn = Connection::open_in_memory().expect("in-memory DB 생성 실패");
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
        .expect("스키마 생성 실패");

        // 서울시청(37.5665, 126.9780) 근방 고정 데이터.
        let seed: &[(&str, &str, &str, f64, f64)] = &[
            ("id1", "아주가까운카페", "cafe", 37.5666, 126.9781), // ~13m
            ("id2", "500m편의점", "convenience_store", 37.5710, 126.9780), // ~500m
            ("id3", "카테고리제외주유소", "gas_station", 37.5670, 126.9785), // 가까움, but types에서 제외 예정
            ("id4", "멀리떨어진카페", "cafe", 37.7000, 127.2000), // 반경 밖 (수십 km)
        ];
        for (id, name, category, lat, lon) in seed {
            conn.execute(
                "INSERT INTO poi (bizes_id, name, category, lat, lon, address) VALUES (?1, ?2, ?3, ?4, ?5, NULL)",
                params![id, name, category, lat, lon],
            )
            .expect("poi insert 실패");
            let rowid = conn.last_insert_rowid();
            conn.execute(
                "INSERT INTO poi_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?1, ?2, ?2, ?3, ?3)",
                params![rowid, lat, lon],
            )
            .expect("rtree insert 실패");
        }
        conn
    }

    #[test]
    fn query_poi_nearby_filters_by_radius_and_sorts_by_distance() {
        let conn = setup_in_memory_poi_db();
        let types = vec!["cafe".to_string(), "convenience_store".to_string()];
        let results = query_poi_nearby(&conn, 37.5665, 126.9780, 1000.0, &types)
            .expect("쿼리 실패");

        // gas_station은 types에서 빠졌으니 제외, 멀리 떨어진 카페는 반경 밖이라 제외.
        let ids: Vec<&str> = results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, vec!["id1", "id2"], "거리순 정렬 + 카테고리/반경 필터 결과: {ids:?}");
    }

    #[test]
    fn query_poi_nearby_category_filter_excludes_other_types() {
        let conn = setup_in_memory_poi_db();
        let types = vec!["gas_station".to_string()];
        let results = query_poi_nearby(&conn, 37.5665, 126.9780, 1000.0, &types)
            .expect("쿼리 실패");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "id3");
    }

    #[test]
    fn query_poi_nearby_empty_radius_returns_nothing() {
        let conn = setup_in_memory_poi_db();
        let types: Vec<String> = ALL_POI_CATEGORIES.iter().map(|s| s.to_string()).collect();
        let results = query_poi_nearby(&conn, 0.0, 0.0, 1000.0, &types).expect("쿼리 실패");
        assert!(results.is_empty(), "서울과 무관한 좌표(0,0)에서는 결과가 없어야 함");
    }

    /// MAX_POI_RESULTS(500)보다 많은 후보를 반경 안에 심어서 응답이 실제로
    /// 잘리는지, 그리고 잘린 뒤에도 "가장 가까운 것부터" 유지되는지 확인한다.
    /// (2026-07-15 실측: 서울 중심가 1500m 반경 전카테고리 조회가 6,125건/1.1MB로
    /// 응답한 게 실제 지연의 상당 부분이었음 — 회귀 방지용 테스트.)
    #[test]
    fn query_poi_nearby_caps_results_and_keeps_nearest_first() {
        let conn = Connection::open_in_memory().expect("in-memory DB 생성 실패");
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
            CREATE VIRTUAL TABLE poi_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);",
        )
        .expect("스키마 생성 실패");

        // 서울시청 중심으로 600개를 촘촘히 흩뿌린다 — 인덱스가 커질수록 중심에서
        // 살짝씩 더 멀어지게 해서(0.0001도 ≈ 11m 씩) "가장 가까운 500개"가
        // id_0..id_499여야 함을 명확히 검증할 수 있게 한다.
        for i in 0..600 {
            let lat = 37.5665 + (i as f64) * 0.0001;
            let lon = 126.9780;
            let bizes_id = format!("id_{i}");
            conn.execute(
                "INSERT INTO poi (bizes_id, name, category, lat, lon, address) VALUES (?1, ?1, 'cafe', ?2, ?3, NULL)",
                params![bizes_id, lat, lon],
            )
            .expect("poi insert 실패");
            let rowid = conn.last_insert_rowid();
            conn.execute(
                "INSERT INTO poi_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?1, ?2, ?2, ?3, ?3)",
                params![rowid, lat, lon],
            )
            .expect("rtree insert 실패");
        }

        let types = vec!["cafe".to_string()];
        // 반경을 넉넉히 잡아 600개 전부 반경 안에 들어오게 한다(가장 먼 것도 ~6.6km 미만).
        let results = query_poi_nearby(&conn, 37.5665, 126.9780, 10_000.0, &types)
            .expect("쿼리 실패");

        assert_eq!(results.len(), MAX_POI_RESULTS, "MAX_POI_RESULTS로 잘려야 함");
        assert_eq!(results.first().unwrap().id, "id_0", "가장 가까운 후보가 1번이어야 함");
        assert_eq!(
            results.last().unwrap().id,
            format!("id_{}", MAX_POI_RESULTS - 1),
            "잘린 뒤 마지막 항목은 501번째로 가까운 후보(인덱스 499)여야 함"
        );
    }

    // ── bbox 모드: query_poi_in_bbox / bbox_span_valid / resolve_poi_query_mode ──

    fn setup_bbox_test_db() -> Connection {
        let conn = Connection::open_in_memory().expect("in-memory DB 생성 실패");
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
        .expect("스키마 생성 실패");

        // 쿼리 bbox: south=37.0, west=127.0, north=37.02, east=127.02 → center=(37.01, 127.01).
        let seed: &[(&str, &str, &str, f64, f64)] = &[
            ("b1", "가까운카페", "cafe", 37.01, 127.011), // 중심에서 가장 가까움 (~89m)
            ("b2", "중간거리편의점", "convenience_store", 37.015, 127.01), // 중간 거리 (~557m)
            // bbox 모서리 근방 — "중심+반경" 근사였다면 원(circle) 밖으로 잘렸을 후보.
            // bbox 모드는 반경 필터를 하지 않으므로 사각형 안이면 그대로 포함되어야 한다.
            ("b3", "모서리카페", "cafe", 37.0199, 127.0199), // (~1411m, 그러나 bbox 안)
            ("b4", "bbox밖", "cafe", 37.03, 127.03), // north 경계 초과 — 제외
            ("b5", "카테고리제외", "restaurant", 37.01, 127.012), // types에서 제외 예정
        ];
        for (id, name, category, lat, lon) in seed {
            conn.execute(
                "INSERT INTO poi (bizes_id, name, category, lat, lon, address) VALUES (?1, ?2, ?3, ?4, ?5, NULL)",
                params![id, name, category, lat, lon],
            )
            .expect("poi insert 실패");
            let rowid = conn.last_insert_rowid();
            conn.execute(
                "INSERT INTO poi_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?1, ?2, ?2, ?3, ?3)",
                params![rowid, lat, lon],
            )
            .expect("rtree insert 실패");
        }
        conn
    }

    #[test]
    fn query_poi_in_bbox_includes_corner_excludes_outside_and_sorts_by_center_distance() {
        let conn = setup_bbox_test_db();
        let types = vec!["cafe".to_string(), "convenience_store".to_string()];
        let results = query_poi_in_bbox(&conn, 37.0, 127.0, 37.02, 127.02, &types)
            .expect("쿼리 실패");

        let ids: Vec<&str> = results.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids.len(), 3, "b4(bbox 밖)/b5(카테고리 제외)는 빠져야 함: {ids:?}");
        assert!(
            ids.contains(&"b3"),
            "모서리 후보 b3는 원 반경 필터라면 잘렸겠지만 bbox 모드에선 포함되어야 함: {ids:?}"
        );
        assert!(!ids.contains(&"b4"), "bbox 밖 후보 b4는 제외되어야 함: {ids:?}");
        assert_eq!(ids[0], "b1", "중심(37.01,127.01)에 가장 가까운 b1이 1순위여야 함: {ids:?}");
    }

    #[test]
    fn query_poi_in_bbox_category_filter_excludes_other_types() {
        let conn = setup_bbox_test_db();
        let types = vec!["restaurant".to_string()];
        let results = query_poi_in_bbox(&conn, 37.0, 127.0, 37.02, 127.02, &types)
            .expect("쿼리 실패");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "b5");
    }

    /// bbox 모드도 radius 모드와 동일하게 MAX_POI_RESULTS로 잘려야 한다
    /// (ambient 레이어가 뷰포트 사각형으로 조회하는 경로라 실제 트래픽에서
    /// 더 흔히 부딪히는 케이스).
    #[test]
    fn query_poi_in_bbox_caps_results_and_keeps_nearest_first() {
        let conn = Connection::open_in_memory().expect("in-memory DB 생성 실패");
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
            CREATE VIRTUAL TABLE poi_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);",
        )
        .expect("스키마 생성 실패");

        // bbox(37.0~37.1, 127.0~127.01)의 중심(37.05, 127.005)에서 시작해 북쪽
        // 한 방향으로만 0.00008도씩 600개를 심는다 — 경도는 고정, 위도만 한
        // 방향으로 증가하므로 "인덱스가 클수록 중심에서 멀어진다"가 haversine
        // 거리 기준으로도 엄격히 단조 증가함이 보장된다(이전 버전은 남서쪽
        // 모서리부터 북쪽 끝까지 쭉 심어서 중심 위도를 가운데서 관통해 거리가
        // V자로 꺾이는 바람에 "가장 가까운 500개"가 인덱스 순서와 무관해지는
        // 버그가 있었음 — 감사에서 지적되어 수정).
        // 600 * 0.00008 = 0.048 < 중심~북쪽 경계 반폭(0.05)이라 전부 bbox 안에 남는다.
        let center_lat = 37.05;
        let center_lon = 127.005;
        for i in 0..600 {
            let lat = center_lat + (i as f64) * 0.00008;
            let lon = center_lon;
            let bizes_id = format!("id_{i}");
            conn.execute(
                "INSERT INTO poi (bizes_id, name, category, lat, lon, address) VALUES (?1, ?1, 'cafe', ?2, ?3, NULL)",
                params![bizes_id, lat, lon],
            )
            .expect("poi insert 실패");
            let rowid = conn.last_insert_rowid();
            conn.execute(
                "INSERT INTO poi_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?1, ?2, ?2, ?3, ?3)",
                params![rowid, lat, lon],
            )
            .expect("rtree insert 실패");
        }

        let types = vec!["cafe".to_string()];
        let results = query_poi_in_bbox(&conn, 37.0, 127.0, 37.1, 127.01, &types)
            .expect("쿼리 실패");

        assert_eq!(results.len(), MAX_POI_RESULTS, "MAX_POI_RESULTS로 잘려야 함");
        assert_eq!(results.first().unwrap().id, "id_0", "중심에 가장 가까운 후보가 1순위여야 함");
        assert_eq!(
            results.last().unwrap().id,
            format!("id_{}", MAX_POI_RESULTS - 1),
            "잘린 뒤 마지막 항목은 501번째로 가까운 후보(인덱스 499)여야 함"
        );
    }

    #[test]
    fn bbox_span_valid_accepts_small_span() {
        assert!(bbox_span_valid(37.0, 127.0, 37.02, 127.02));
    }

    #[test]
    fn bbox_span_valid_accepts_exactly_at_cap() {
        assert!(bbox_span_valid(37.0, 127.0, 37.5, 127.5));
    }

    #[test]
    fn bbox_span_valid_rejects_oversized_lat_span() {
        assert!(!bbox_span_valid(37.0, 127.0, 37.6, 127.02), "위도 폭 0.6도 > 0.5도 상한");
    }

    #[test]
    fn bbox_span_valid_rejects_oversized_lon_span() {
        assert!(!bbox_span_valid(37.0, 127.0, 37.02, 127.6), "경도 폭 0.6도 > 0.5도 상한");
    }

    #[test]
    fn bbox_span_valid_rejects_inverted_bbox() {
        // north < south — 뒤집힌/퇴화된 bbox는 조용히 처리하지 않고 거부한다.
        assert!(!bbox_span_valid(37.02, 127.0, 37.0, 127.02));
    }

    #[test]
    fn resolve_poi_query_mode_all_bbox_fields_present_is_bbox() {
        let q = PoiNearbyQuery {
            lat: None, lon: None, radius_m: None,
            south: Some(37.0), west: Some(127.0), north: Some(37.02), east: Some(127.02),
            types: None,
        };
        assert_eq!(
            resolve_poi_query_mode(&q),
            Ok(PoiQueryMode::Bbox { south: 37.0, west: 127.0, north: 37.02, east: 127.02 })
        );
    }

    #[test]
    fn resolve_poi_query_mode_radius_fields_present_is_radius() {
        let q = PoiNearbyQuery {
            lat: Some(37.5), lon: Some(127.0), radius_m: Some(1000.0),
            south: None, west: None, north: None, east: None,
            types: None,
        };
        assert_eq!(
            resolve_poi_query_mode(&q),
            Ok(PoiQueryMode::Radius { lat: 37.5, lon: 127.0, radius_m: 1000.0 })
        );
    }

    #[test]
    fn resolve_poi_query_mode_partial_bbox_is_rejected() {
        // south/west만 있고 north/east가 빠짐 — 조용히 추측하지 않고 거부.
        let q = PoiNearbyQuery {
            lat: None, lon: None, radius_m: None,
            south: Some(37.0), west: Some(127.0), north: None, east: None,
            types: None,
        };
        assert_eq!(resolve_poi_query_mode(&q), Err(()));
    }

    #[test]
    fn resolve_poi_query_mode_partial_radius_is_rejected() {
        // lat/lon만 있고 radius_m이 빠짐 — 부분 radius도 거부.
        let q = PoiNearbyQuery {
            lat: Some(37.5), lon: Some(127.0), radius_m: None,
            south: None, west: None, north: None, east: None,
            types: None,
        };
        assert_eq!(resolve_poi_query_mode(&q), Err(()));
    }

    #[test]
    fn resolve_poi_query_mode_neither_mode_is_rejected() {
        // 완전히 빈 쿼리 — 400이어야지 패닉/500이면 안 됨.
        let q = PoiNearbyQuery {
            lat: None, lon: None, radius_m: None,
            south: None, west: None, north: None, east: None,
            types: None,
        };
        assert_eq!(resolve_poi_query_mode(&q), Err(()));
    }

    #[test]
    fn resolve_poi_query_mode_both_fully_present_prefers_bbox() {
        // bbox 4개 + radius 3개가 모두 채워진 경우: bbox 경로를 우선한다.
        let q = PoiNearbyQuery {
            lat: Some(37.5), lon: Some(127.0), radius_m: Some(1000.0),
            south: Some(37.0), west: Some(127.0), north: Some(37.02), east: Some(127.02),
            types: None,
        };
        assert_eq!(
            resolve_poi_query_mode(&q),
            Ok(PoiQueryMode::Bbox { south: 37.0, west: 127.0, north: 37.02, east: 127.02 })
        );
    }
}
