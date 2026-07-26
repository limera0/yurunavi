mod api;
use api::{
    calc_tortuosity, calc_winding_score, check_destination_reachable,
    check_gps_accuracy, check_route_similarity, fun_score_v2, fun_score_v3, haversine_m,
    is_off_route, GpsPoint, GpsQuality, WindingScore,
};

const VALHALLA_URL: &str = "http://localhost:8002/route";

// V-World(국토교통부 브이월드) Search API — 도로명/지번 주소 → 좌표, 다중 후보(최대 10건)
// 반환. `/geocode/search`가 프록시하는 대상. 자체 호스팅 주소 DB(정부 데이터 신청 승인 후,
// Phase 2)로 교체되기 전까지의 임시 프록시다. VALHALLA_URL과 동일하게 하드코딩 관례를
// 따른다. (이전에는 GetCoord 단일-결과 API를 썼으나, 사용자가 "58-2/58-4/58-6"처럼 같은
// 도로명의 여러 건물 중 하나를 고를 수 있어야 한다는 요청으로 다중 후보를 주는 Search로
// 교체했다.)
const VWORLD_SEARCH_URL: &str = "https://api.vworld.kr/req/search";

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
    response::Html,
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

// ── /geocode/search ───────────────────────────────────────────

/// V-World API 키. `.env`(native/.env, docker-compose가 `env_file`로 컨테이너에 주입)를
/// 통해 설정된 `VWORLD_API_KEY` 환경변수를 한 번만 읽는다. `None`이면(환경변수 없음)
/// 서버 전체를 죽이지 않고 `/geocode/search`만 503을 반환한다(다른 엔드포인트는 정상
/// 동작) — `poi_db()`와 동일한 degrade-gracefully 패턴.
static VWORLD_API_KEY: std::sync::OnceLock<Option<String>> = std::sync::OnceLock::new();

fn vworld_api_key() -> &'static Option<String> {
    VWORLD_API_KEY.get_or_init(|| match std::env::var("VWORLD_API_KEY") {
        Ok(key) if !key.trim().is_empty() => Some(key),
        _ => {
            eprintln!(
                "[YuruNavi/Rust] 경고: VWORLD_API_KEY 환경변수 없음 \
                 — /geocode/search 는 503을 반환합니다 (다른 엔드포인트는 정상 동작)"
            );
            None
        }
    })
}

#[derive(Deserialize)]
struct GeocodeSearchQuery {
    q: Option<String>,
}

/// 클라이언트(Flutter)에 돌려주는 자체 DTO — V-World 원본 응답 포맷을 그대로 노출하지
/// 않는다. Search API가 최대 10건까지 후보를 줄 수 있어 배열로 반환한다(기존
/// `/poi/nearby`의 배열-of-DTO 관례와 동일) — 클라이언트는 이미 이 배열을 그대로
/// 렌더링하므로 0~1개였다가 0~10개로 늘어나도 클라이언트 쪽 변경이 필요 없다.
#[derive(Serialize, Clone, Debug, PartialEq)]
struct GeocodeResultDto {
    address: String,
    lat: f64,
    lon: f64,
}

/// V-World Search 응답(`serde_json::Value`)에서 후보 목록을 뽑아낸다. axum/reqwest
/// 타입이 시그니처에 없는 순수 함수라 네트워크 없이 고정 픽스처로 단위 테스트할 수
/// 있다(아래 tests 모듈의 OK/4건, NOT_FOUND, ERROR 픽스처).
///
/// - `status == "OK"`: `result.items[]`를 순회해 각 항목의 `address.road`를 주소로
///   사용한다(비어 있으면 `address.parcel`로 폴백 — `category=road` 결과에서는
///   사실상 발생하지 않아야 하지만 방어적으로 둔다), `point.x`/`.y`를 각각 lon/lat으로
///   사용한다. V-World가 이미 요청의 `size=10`으로 상한을 걸어 보내므로 여기서 별도로
///   자르지 않는다.
/// - `status == "NOT_FOUND"` / `"ERROR"` / 그 외(필드 누락 등 예상 밖 형태): 빈 `Vec`.
///   `ERROR`일 때의 code/text는 이 함수가 아니라 [`vworld_error_info`]로 별도 추출해
///   호출부가 서버 로그에 남기게 한다(클라이언트에는 V-World 원본 에러를 노출하지 않음).
fn parse_vworld_search_items(resp: &serde_json::Value) -> Vec<GeocodeResultDto> {
    let response = &resp["response"];
    if response["status"].as_str() != Some("OK") {
        return Vec::new();
    }
    let items = match response["result"]["items"].as_array() {
        Some(items) => items,
        None => return Vec::new(),
    };
    items
        .iter()
        .filter_map(|item| {
            let road = item["address"]["road"].as_str().unwrap_or("");
            let parcel = item["address"]["parcel"].as_str().unwrap_or("");
            let address = if !road.trim().is_empty() { road } else { parcel };
            if address.trim().is_empty() {
                return None;
            }
            let lon: f64 = item["point"]["x"].as_str()?.parse().ok()?;
            let lat: f64 = item["point"]["y"].as_str()?.parse().ok()?;
            Some(GeocodeResultDto { address: address.to_string(), lat, lon })
        })
        .collect()
}

/// `status == "ERROR"`일 때 V-World가 돌려준 원인 코드/메시지를 뽑아낸다(서버 로그 전용 —
/// 클라이언트 응답에는 절대 그대로 노출하지 않는다). ERROR가 아니면 `None`.
/// GetCoord/Search 두 API가 동일한 에러 응답 형태(`status:"ERROR"`, `error:{code,text}`)를
/// 쓰는 걸 실측으로 확인해(둘 다 같은 V-World API family) 그대로 재사용한다.
fn vworld_error_info(resp: &serde_json::Value) -> Option<(String, String)> {
    let response = &resp["response"];
    if response["status"].as_str() != Some("ERROR") {
        return None;
    }
    let code = response["error"]["code"].as_str().unwrap_or("UNKNOWN").to_string();
    let text = response["error"]["text"].as_str().unwrap_or("").to_string();
    Some((code, text))
}

/// V-World Search 엔드포인트를 한 번 호출한다(`category`는 "road" 또는 "parcel").
/// 최대 10건(`size=10`)까지 요청 — 이 상한은 요청 파라미터 자체에 있으므로 응답 쪽에서
/// 추가로 자를 필요가 없다. 5초 타임아웃. 준수사항: V-World 응답을 디스크/SQLite/TTL
/// 캐시 등 어디에도 저장하지 않는다(서비스 약관상 실시간 pass-through만 허용) — 이
/// 함수는 매 호출마다 그대로 새 요청을 보낼 뿐 아무것도 캐시하지 않는다.
async fn fetch_vworld_search(
    client: &reqwest::Client,
    api_key: &str,
    query: &str,
    category: &str,
) -> Result<serde_json::Value, StatusCode> {
    let resp = client
        .get(VWORLD_SEARCH_URL)
        .query(&[
            ("service", "search"),
            ("request", "search"),
            ("version", "2.0"),
            ("crs", "EPSG:4326"),
            ("size", "10"),
            ("page", "1"),
            ("query", query),
            ("type", "address"),
            ("category", category),
            ("format", "json"),
            ("errorformat", "json"),
            ("key", api_key),
        ])
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .map_err(|e| {
            // ⚠️ `{e}`로 그대로 찍으면 안 됨: reqwest::Error의 Display는 실패한 요청의
            // URL을 포함하는데, 그 URL은 `.query()`로 실은 `key=<VWORLD_API_KEY>`까지
            // 그대로 담고 있다 — DNS/연결/TLS 실패 시 실키가 stderr에 평문으로 남는다.
            // `.without_url()`로 URL을 떼어낸 뒤에만 로그로 남긴다.
            eprintln!(
                "[YuruNavi/Rust] /geocode/search V-World 요청 실패(category={category}): {}",
                e.without_url()
            );
            StatusCode::BAD_GATEWAY
        })?;

    resp.json::<serde_json::Value>().await.map_err(|e| {
        eprintln!(
            "[YuruNavi/Rust] /geocode/search V-World 응답 파싱 실패(category={category}): {e}"
        );
        StatusCode::BAD_GATEWAY
    })
}

/// `category`(= "road" 또는 "parcel") 하나로 V-World Search를 호출해 후보 목록을 얻는다.
/// `status:"ERROR"`면 code/text를 로그로 남기고 즉시 502로 중단한다(재시도 대상 아님 —
/// 예: 잘못된 키). 그 외에는 [`parse_vworld_search_items`] 결과(0~10건)를 그대로 돌려준다.
async fn try_vworld_search(
    client: &reqwest::Client,
    api_key: &str,
    query: &str,
    category: &str,
) -> Result<Vec<GeocodeResultDto>, StatusCode> {
    let resp = fetch_vworld_search(client, api_key, query, category).await?;

    if let Some((code, text)) = vworld_error_info(&resp) {
        eprintln!(
            "[YuruNavi/Rust] /geocode/search V-World 오류 응답(category={category}): {code} - {text}"
        );
        return Err(StatusCode::BAD_GATEWAY);
    }

    Ok(parse_vworld_search_items(&resp))
}

/// "OO로N길" ↔ "OO로N번길" 표기 차이를 보정하는 폴백 후보를 만든다. V-World GetCoord는
/// 완전 일치 파서라 이 표기 차이 하나만으로도 NOT_FOUND가 나는 게 실사용자 리포트로
/// 확인됨(예: "신창로55길 29" 입력 → 정식 등록명은 "신창로55번길 29") — 오탈자 1건이
/// 아니라 "번" 누락/과다입력이라는 흔한 한국 도로명주소 입력 클래스 전체를 다룬다.
///
/// - "번길"을 포함하면 → "번길"을 "길"로 바꾼 변형을 돌려준다(번을 과다 입력한 드문
///   경우 대응). 이 함수는 원본 쿼리로 이미 두 유형(ROAD/PARCEL) 다 NOT_FOUND가 난
///   *뒤에만* 폴백으로 호출되므로 — 원본 "번길" 표기가 애초에 맞았다면 원본 시도에서
///   이미 매치되어 이 함수까지 오지 않는다. 즉 "이미 정상인데 왜 번을 지우나" 상황은
///   호출 경로상 발생하지 않는다.
/// - 아니면, 숫자 뒤에 바로 "길"이 오고 그 숫자런 앞에 "번"이 없는 첫 위치를 찾으면 →
///   그 "길" 앞에 "번"을 삽입한 변형을 돌려준다(번 누락 보정 — 실사용자 패턴의 절대
///   다수). 첫 매치만 처리하고 곧장 반환하므로 문자열 뒤쪽에 다른 "길"이 더 있어도
///   중복 삽입하지 않는다.
/// - 둘 다 아니면 → `None`(정규화할 게 없으니 폴백 V-World 호출 자체를 하지 않는다).
fn beon_variant(query: &str) -> Option<String> {
    if let Some(pos) = query.find("번길") {
        let beon_len = '번'.len_utf8();
        let mut variant = String::with_capacity(query.len());
        variant.push_str(&query[..pos]);
        variant.push_str(&query[pos + beon_len..]);
        return Some(variant);
    }

    let chars: Vec<char> = query.chars().collect();
    for i in 0..chars.len() {
        if chars[i] != '길' {
            continue;
        }
        if i == 0 || !chars[i - 1].is_ascii_digit() {
            continue;
        }
        // 숫자런의 시작 인덱스를 뒤로 훑어서 찾는다.
        let mut start = i - 1;
        while start > 0 && chars[start - 1].is_ascii_digit() {
            start -= 1;
        }
        // 숫자런 시작 바로 앞 문자가 이미 '번'이면(위 find("번길")에서 못 잡는 형태는
        // 없지만 방어적으로 유지) 정상 표기이므로 건너뛴다.
        if start > 0 && chars[start - 1] == '번' {
            continue;
        }
        let mut variant: String = chars[..i].iter().collect();
        variant.push('번');
        variant.push_str(&chars[i..].iter().collect::<String>());
        return Some(variant);
    }

    None
}

async fn handle_geocode_search(
    Query(q): Query<GeocodeSearchQuery>,
) -> Result<Json<Vec<GeocodeResultDto>>, StatusCode> {
    let query_text = q.q.unwrap_or_default();
    let query_text = query_text.trim();
    if query_text.is_empty() {
        return Ok(Json(Vec::new()));
    }

    let api_key = match vworld_api_key() {
        Some(k) => k.as_str(),
        None => return Err(StatusCode::SERVICE_UNAVAILABLE),
    };

    let client = http_client();

    // 도로명(road) 우선 조회 — 결과가 하나라도 있으면(최대 10건, V-World size=10으로
    // 상한) 그대로 반환하고 parcel은 시도하지 않는다.
    let road_results = try_vworld_search(client, api_key, query_text, "road").await?;
    if !road_results.is_empty() {
        return Ok(Json(road_results));
    }

    // road가 0건(NOT_FOUND)일 때만 지번(parcel)으로 한 번 더 시도한다(사용자가 지번
    // 주소를 입력했을 가능성 대비).
    let parcel_results = try_vworld_search(client, api_key, query_text, "parcel").await?;
    if !parcel_results.is_empty() {
        return Ok(Json(parcel_results));
    }

    // 원본 쿼리로 road/parcel 둘 다 0건이면 "OO로N길"/"OO로N번길" 표기 차이 보정 변형으로
    // 한 번 더 시도한다(beon_variant 문서 참조 — Search API도 GetCoord와 마찬가지로 이
    // 표기 차이를 스스로 보정해주지 않는 걸 실측으로 확인했다). 정규화할 게 없으면
    // (None) V-World를 더 호출하지 않고 그대로 빈 배열로 끝낸다.
    if let Some(variant) = beon_variant(query_text) {
        let road_variant = try_vworld_search(client, api_key, &variant, "road").await?;
        if !road_variant.is_empty() {
            return Ok(Json(road_variant));
        }
        let parcel_variant = try_vworld_search(client, api_key, &variant, "parcel").await?;
        if !parcel_variant.is_empty() {
            return Ok(Json(parcel_variant));
        }
    }

    Ok(Json(Vec::new()))
}

// ── /gasstations/nearby (주유소 최저가) ─────────────────────────

const MAX_GAS_RESULTS: usize = 20;

#[derive(Deserialize)]
struct GasStationsQuery {
    lat: f64,
    lon: f64,
    #[serde(default = "default_fuel_code")]
    fuel: String,
    #[serde(default = "default_gas_radius_m")]
    radius_m: f64,
}

fn default_fuel_code() -> String { "B027".to_string() }
fn default_gas_radius_m() -> f64 { 5000.0 }

#[derive(Serialize)]
struct GasStationDto {
    name: String,
    brand: String,
    address: String,
    lat: f64,
    lon: f64,
    distance_m: f64,
    price: Option<i32>,
    premium_price: Option<i32>,
}

fn meridional_arc(a: f64, e2: f64, lat_rad: f64) -> f64 {
    let e4 = e2 * e2;
    let e6 = e4 * e2;
    a * ((1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * lat_rad
        - (3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * (2.0 * lat_rad).sin()
        + (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * (4.0 * lat_rad).sin()
        - (35.0 * e6 / 3072.0) * (6.0 * lat_rad).sin())
}

// Opinet 내부 GIS 좌표(커스텀 TM) → WGS84 (lat, lon)
// TM 파라미터: lat_0=38°N, lon_0=128°E, k=1, FE=400,000m, FN=600,000m, WGS84 타원체
// Snyder (1987) pp.63-65 TM 역변환 공식. pyproj(proj='tmerc') 출력으로 검증함.
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

async fn nominatim_region(
    client: &reqwest::Client,
    lat: f64,
    lon: f64,
) -> Option<(String, String)> {
    let url = format!(
        "https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&accept-language=ko"
    );
    let resp = client
        .get(&url)
        .header("User-Agent", "YuruNavi/1.0 (navi.westinx.com; ceo@westinx.com)")
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await
        .ok()?;
    let v: serde_json::Value = resp.json().await.ok()?;
    let addr = &v["address"];

    // 광역시(서울·부산 등): city=광역시명, borough=구명
    if let (Some(city), Some(gu)) = (addr["city"].as_str(), addr["borough"].as_str()) {
        return Some((city.to_string(), gu.to_string()));
    }
    // 도(경기·강원 등): province=도명, city 또는 county=시군명
    if let Some(prov) = addr["province"].as_str() {
        let sigungu = addr["city"]
            .as_str()
            .or_else(|| addr["county"].as_str())
            .or_else(|| addr["town"].as_str())
            .unwrap_or("");
        if !sigungu.is_empty() {
            return Some((prov.to_string(), sigungu.to_string()));
        }
    }
    // 세종특별자치시 등 단층 광역자치단체
    if let Some(city) = addr["city"].as_str() {
        return Some((city.to_string(), String::new()));
    }
    None
}

fn parse_opinet_price(v: &serde_json::Value) -> Option<i32> {
    v.as_str()?.trim().parse::<i32>().ok().filter(|&p| p > 0)
}

async fn fetch_opinet_region(
    client: &reqwest::Client,
    sido_nm: &str,
    sigungu_nm: &str,
) -> Option<Vec<serde_json::Value>> {
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
        .timeout(std::time::Duration::from_secs(8))
        .send()
        .await
        .map_err(|e| eprintln!("[YuruNavi/Rust] /gasstations Opinet 요청 실패: {e}"))
        .ok()?;
    let v: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| eprintln!("[YuruNavi/Rust] /gasstations Opinet 응답 파싱 실패: {e}"))
        .ok()?;
    Some(v["list"].as_array().cloned().unwrap_or_default())
}

async fn handle_gasstations_nearby(
    Query(q): Query<GasStationsQuery>,
) -> Result<Json<Vec<GasStationDto>>, StatusCode> {
    if !(-90.0..=90.0).contains(&q.lat) || !(-180.0..=180.0).contains(&q.lon) {
        return Err(StatusCode::BAD_REQUEST);
    }
    let radius_m = q.radius_m.clamp(100.0, 10_000.0);
    let client = http_client();

    let (sido, sigungu) = nominatim_region(client, q.lat, q.lon)
        .await
        .ok_or_else(|| {
            eprintln!(
                "[YuruNavi/Rust] /gasstations 역지오코딩 실패 lat={} lon={}",
                q.lat, q.lon
            );
            StatusCode::BAD_GATEWAY
        })?;

    let raw = fetch_opinet_region(client, &sido, &sigungu)
        .await
        .unwrap_or_default();

    let center = GpsPoint { lat: q.lat, lng: q.lon };
    let mut hits: Vec<(i32, f64, GasStationDto)> = raw
        .iter()
        .filter_map(|s| {
            let gis_x = s["GIS_X_COOR"].as_f64()?;
            let gis_y = s["GIS_Y_COOR"].as_f64()?;
            let (lat, lon) = gis_to_wgs84(gis_x, gis_y);
            let dist = haversine_m(&center, &GpsPoint { lat, lng: lon });
            if dist > radius_m {
                return None;
            }
            let gasoline = parse_opinet_price(&s["B027_P"]);
            let premium = parse_opinet_price(&s["B034_P"]);
            let sort_price = match q.fuel.as_str() {
                "B034" => premium.unwrap_or(i32::MAX),
                _ => gasoline.unwrap_or(i32::MAX),
            };
            Some((
                sort_price,
                dist,
                GasStationDto {
                    name: s["OS_NM"].as_str().unwrap_or("").to_string(),
                    brand: s["POLL_DIV_CD"].as_str().unwrap_or("").to_string(),
                    address: s["VAN_ADR"].as_str().unwrap_or("").to_string(),
                    lat,
                    lon,
                    distance_m: (dist * 10.0).round() / 10.0,
                    price: gasoline,
                    premium_price: premium,
                },
            ))
        })
        .collect();

    hits.sort_by(|a, b| {
        a.0.cmp(&b.0)
            .then_with(|| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
    });

    let dtos = hits.into_iter().take(MAX_GAS_RESULTS).map(|(_, _, d)| d).collect();
    Ok(Json(dtos))
}

// ── /privacy ───────────────────────────────────────────────────

async fn handle_privacy() -> Html<&'static str> {
    Html(PRIVACY_HTML)
}

const PRIVACY_HTML: &str = r#"<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>유루나비 개인정보처리방침</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Noto Sans KR', sans-serif;
         max-width: 800px; margin: 0 auto; padding: 24px 16px;
         color: #212121; line-height: 1.7; font-size: 15px; }
  h1 { font-size: 22px; border-bottom: 2px solid #008080; padding-bottom: 12px; }
  h2 { font-size: 17px; margin-top: 32px; color: #004d4d; }
  h3 { font-size: 15px; margin-top: 20px; color: #333; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; margin: 12px 0; }
  th, td { border: 1px solid #ccc; padding: 8px 10px; text-align: left; }
  th { background: #f0f0f0; }
  li { margin-bottom: 6px; }
  strong { color: #004d4d; }
  hr { border: none; border-top: 1px solid #e0e0e0; margin: 32px 0; }
  .notice { background: #fff8e1; border-left: 4px solid #ffb300;
            padding: 12px 16px; margin: 20px 0; font-size: 13px; }
  footer { margin-top: 40px; font-size: 12px; color: #888; }
</style>
</head>
<body>
<h1>유루나비(YuruNavi) 개인정보처리방침</h1>
<p><strong>시행일자: 2026-07-11</strong> (최초 제정)</p>
<p>유루나비(이하 "회사" 또는 "앱")는 이용자의 개인정보를 중요시하며, 「개인정보 보호법」 등 관련 법령을 준수합니다. 회사는 본 개인정보처리방침을 통해 이용자가 제공하는 개인정보가 어떠한 용도와 방식으로 이용되고 있으며, 개인정보 보호를 위해 어떠한 조치가 취해지고 있는지 알려드립니다.</p>

<h2>1. 수집하는 개인정보 항목 및 수집 방법</h2>
<h3>1-1. 위치정보</h3>
<ul>
  <li><strong>수집 항목</strong>: GPS 기반 정밀 위치정보(위도/경도), 이동 속도, 방향</li>
  <li><strong>수집 방법</strong>: 앱 실행 중(포그라운드) 단말기 GPS를 통해 실시간 수집</li>
  <li><strong>특이사항</strong>: 본 앱은 백그라운드 위치정보를 수집하지 않습니다(앱이 꺼져 있거나 화면이 꺼진 상태에서는 위치를 수집하지 않음).</li>
</ul>
<h3>1-2. 이용자가 직접 입력하는 정보</h3>
<ul>
  <li>닉네임, 인스타그램 계정(선택), 보유 오토바이 기종 등 프로필 정보</li>
  <li>저장한 경로(즐겨찾기 코스) 정보</li>
  <li>위 정보는 이용자의 <strong>단말기 내부에만 저장</strong>되며, 회사 서버로 전송되거나 수집되지 않습니다. 앱 삭제 시 함께 삭제됩니다.</li>
</ul>
<h3>1-3. 자동 수집 정보 (충돌 진단)</h3>
<ul>
  <li>앱 비정상 종료(크래시) 시 오류 로그, 단말기 모델명·OS 버전, 앱 버전 등 진단 정보를 Firebase Crashlytics(Google)를 통해 수집합니다. 이는 서비스 안정성 확보 목적이며, 이용자를 특정하는 개인 식별정보(이름, 연락처 등)는 포함하지 않습니다.</li>
</ul>
<h3>1-4. 회사가 운영하는 자체 서버로 전송되는 정보</h3>
<ul>
  <li>경로 탐색·지도 표시를 위해 GPS 좌표가 회사가 직접 운영하는 지도 타일·경로 탐색 서버(westinx.com 하위 도메인)로 전송됩니다. 이 서버는 외부 제3자가 아닌 회사가 직접 관리하며, 수신한 위치 정보를 경로 계산 응답 목적 외에 별도로 저장·분석·활용하지 않습니다. 다만 「위치정보의 보호 및 이용 등에 관한 법률」에 따라 개인위치정보의 수집·이용·제공사실 확인자료(요청 시각 등 최소한의 기록)는 6개월간 보관되며, 그 외 서비스 운영·보안을 위한 최소한의 서버 접속기록이 관련 법령에 따라 일정기간 보관될 수 있습니다.</li>
</ul>

<h2>2. 개인정보의 수집 및 이용 목적</h2>
<ul>
  <li>실시간 내비게이션 경로 안내 및 음성 안내 제공</li>
  <li>사용자 맞춤 코스(재미있는 도로 우선) 추천</li>
  <li>서비스 오류 진단 및 안정성 개선(크래시 리포팅)</li>
  <li>저장된 프로필·경로 정보를 통한 개인화 기능 제공(단말기 내부 저장)</li>
</ul>

<h2>3. 개인정보의 보유 및 이용 기간</h2>
<ul>
  <li><strong>위치정보(경로 계산용 GPS 좌표)</strong>: 실시간 경로 계산에만 이용되며, 계산 완료 후 별도 데이터베이스에 저장하지 않습니다.</li>
  <li><strong>개인위치정보 수집·이용·제공사실 확인자료</strong>: 관련 법령에 따라 6개월간 보관됩니다.</li>
  <li><strong>프로필·저장 경로 정보</strong>: 단말기에 로컬 저장되며, 이용자가 앱을 삭제하거나 직접 삭제할 때까지 보관됩니다. 회사 서버에는 저장되지 않습니다.</li>
  <li><strong>크래시 진단 정보</strong>: Firebase Crashlytics 정책에 따라 최대 90일간 보관 후 자동 삭제됩니다.</li>
</ul>

<h2>4. 개인정보의 제3자 제공</h2>
<p>회사는 이용자의 개인정보를 원칙적으로 외부에 제공하지 않습니다. 다만 아래의 경우는 예외로 합니다.</p>
<ul>
  <li>이용자가 사전에 동의한 경우</li>
  <li>법령의 규정에 의거하거나, 수사 목적으로 법령에 정해진 절차와 방법에 따라 수사기관의 요구가 있는 경우</li>
</ul>

<h2>5. 개인정보 처리의 위탁 및 국외 이전</h2>
<p>서비스 안정성 확보를 위해 아래와 같이 개인정보(진단 정보) 처리 업무를 위탁하고 있으며, 이 과정에서 개인정보가 국외로 이전됩니다.</p>
<table>
  <tr><th>이전받는 자</th><th>이전되는 항목</th><th>이전 국가</th><th>이전 방법</th><th>이용목적 및 보유기간</th></tr>
  <tr><td>Google LLC (Firebase Crashlytics)</td><td>크래시 로그, 단말기 모델명·OS 버전, 앱 버전 등 진단 정보</td><td>미국</td><td>앱 내 SDK를 통한 자동 전송</td><td>앱 크래시·오류 진단, 수집 후 최대 90일</td></tr>
</table>
<ul>
  <li><strong>이전받는 자 연락처</strong>: Google LLC (https://firebase.google.com/support/privacy)</li>
  <li><strong>이전 거부 방법 및 효과</strong>: 크래시 리포팅은 별도 동의 절차 없이 서비스 안정성 확보를 위해 필수적으로 사용되는 기능으로, 현재는 개별 거부 기능을 제공하지 않습니다. 거부를 원하실 경우 11번 연락처로 문의해 주시면 확인 후 안내해 드립니다(거부 시 크래시 진단 기능이 제한될 수 있습니다).</li>
</ul>

<h2>6. 이용자 및 법정대리인의 권리와 행사방법</h2>
<p>이용자는 언제든지 다음의 권리를 행사할 수 있습니다.</p>
<ul>
  <li>단말기 내 저장된 프로필·경로 정보: 앱 삭제 또는 앱 내 초기화 기능을 통해 직접 삭제</li>
  <li>위치정보 이용 동의 철회: 단말기 설정에서 앱의 위치 권한을 거부/취소</li>
  <li>그 외 문의: 아래 11번 연락처를 통해 문의</li>
</ul>
<p>본 서비스는 만 14세 미만 아동을 대상으로 하지 않으며, 만 14세 미만 아동의 개인정보를 고의로 수집하지 않습니다.</p>

<h2>7. 개인정보의 파기절차 및 방법</h2>
<ul>
  <li>단말기 로컬 저장 정보는 이용자의 앱 삭제 시 단말기 저장소에서 함께 삭제됩니다.</li>
  <li>회사는 위치정보 자체(GPS 좌표값)를 별도 데이터베이스에 저장하지 않으므로 이에 대한 파기 대상 데이터가 발생하지 않습니다. 다만 3번에서 밝힌 개인위치정보 수집·이용·제공사실 확인자료는 보유기간(6개월) 경과 후 복구 불가능한 방법으로 지체 없이 파기합니다.</li>
</ul>

<h2>8. 개인정보 자동 수집 장치의 설치·운영 및 거부에 관한 사항</h2>
<p>본 앱은 광고 목적의 쿠키·트래킹 SDK를 사용하지 않습니다. 크래시 리포팅(Firebase Crashlytics)만 사용하며, 이는 단말기 설정 또는 향후 제공될 앱 내 설정을 통해 비활성화할 수 있습니다.</p>

<h2>9. 개인정보의 안전성 확보조치</h2>
<ul>
  <li><strong>기술적 조치</strong>: 단말기-서버 간 통신 구간 암호화(HTTPS), 자체 운영 서버에 대한 접근 권한 제한</li>
  <li><strong>관리적 조치</strong>: 개인정보에 접근할 수 있는 인원을 최소화하여 운영</li>
</ul>

<h2>10. 위치정보 관련 특칙 (「위치정보의 보호 및 이용 등에 관한 법률」)</h2>
<p>본 앱은 실시간 경로 안내를 위해 개인위치정보를 처리하는 위치기반서비스사업자로서, 동법에 따라 다음 사항을 안내합니다.</p>
<ul>
  <li><strong>8세 이하의 아동 등의 보호의무자 권리</strong>: 8세 이하의 아동, 피성년후견인 등 개인위치정보주체를 사실상 보호할 법률상 의무가 있는 자(보호의무자)가 이들의 생명·신체보호를 위해 개인위치정보의 이용 또는 제공에 동의하는 경우, 본인의 동의가 있는 것으로 봅니다.</li>
  <li><strong>손해배상</strong>: 회사의 고의 또는 과실로 개인위치정보와 관련하여 이용자에게 손해가 발생한 경우, 이용자는 관련 법령이 정하는 바에 따라 손해배상을 청구할 수 있습니다.</li>
  <li><strong>위치정보관리책임자</strong>: 아래 11번과 동일</li>
</ul>

<h2>11. 개인정보 보호책임자·위치정보관리책임자 및 문의처</h2>
<ul>
  <li><strong>담당자</strong>: 유루나비 개발자</li>
  <li><strong>이메일</strong>: ceo@westinx.com</li>
</ul>

<h2>12. 고지의 의무</h2>
<p>본 개인정보처리방침의 내용 추가, 삭제 및 수정이 있을 경우 시행일자 최소 7일 전부터 앱 내 공지사항 또는 본 문서를 통해 고지합니다.</p>

<hr>
<footer>
  <p>본 문서는 Google Play 콘솔의 "데이터 보안(Data Safety)" 양식 작성 시 실제 수집 항목과 반드시 일치시켜야 합니다.</p>
</footer>
</body>
</html>"#;

// ── /health ────────────────────────────────────────────────────

#[derive(Serialize)]
struct HealthResp {
    status: &'static str,
}

async fn handle_health() -> Json<HealthResp> {
    Json(HealthResp { status: "ok" })
}

// ── Routing config ─────────────────────────────────────────────

const ROUTING_CONFIG_PATH: &str = "/data/routing-config/routing.json";
const ROUTING_CONFIG_DEFAULT: &str = r#"{"version":1,"profiles":[{"use_highways":0.0,"use_ferry":0.0,"use_living_streets":1.0,"use_tracks":0.15,"top_speed":40,"class_factors":{"0":100,"2":6,"3":2.5,"4":0.5,"5":1.2,"6":1.3,"7":1.5},"curvature_penalty":2.0,"long_bridge_factor":3.0,"long_tunnel_factor":3.0,"span_min_length":300,"uturn_penalty":50},{"use_highways":0.0,"use_ferry":0.0,"use_living_streets":0.5,"use_tracks":0.2,"class_factors":{"0":100,"2":2.0,"3":0.3,"4":1.1,"5":1.8,"6":2.2,"7":3.0},"curvature_penalty":0.5,"long_bridge_factor":2.0,"long_tunnel_factor":2.0,"span_min_length":1000,"uturn_penalty":70},{"use_highways":0.0,"use_ferry":0.0,"use_tolls":0.0,"class_factors":{"0":100},"curvature_penalty":0.0,"long_bridge_factor":1.0,"long_tunnel_factor":1.0,"uturn_penalty":120}]}"#;

async fn handle_routing_config() -> impl axum::response::IntoResponse {
    let body = tokio::fs::read_to_string(ROUTING_CONFIG_PATH)
        .await
        .unwrap_or_else(|_| ROUTING_CONFIG_DEFAULT.to_string());
    (
        [(axum::http::header::CONTENT_TYPE, "application/json")],
        body,
    )
}

// ── Main ───────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    // POI DB / V-World API 키는 여기서 한 번씩 초기화한다(OnceLock). 실패해도 서버는
    // 계속 뜨고 해당 엔드포인트만 503을 반환한다 — 각 함수 내부에서 로그로 알린다.
    poi_db();
    vworld_api_key();

    let app = Router::new()
        .route("/health", get(handle_health))
        .route("/privacy", get(handle_privacy))
        .route("/calc_route", post(handle_calc_route))
        .route("/score_route", post(handle_score_route))
        .route("/calc_winding_score", post(handle_winding))
        .route("/check_route_similarity", post(handle_similarity))
        .route("/check_gps_accuracy", post(handle_gps_accuracy))
        .route("/is_off_route", post(handle_off_route))
        .route("/check_destination_reachable", post(handle_reachability))
        .route("/poi/nearby", get(handle_poi_nearby))
        .route("/geocode/search", get(handle_geocode_search))
        .route("/gasstations/nearby", get(handle_gasstations_nearby))
        .route("/routing-config", get(handle_routing_config));

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

    // ── /geocode/search: parse_vworld_search_items / vworld_error_info ──
    //
    // 실제 V-World Search API를 라이브로 호출해 확인한 응답 3종(OK/4건, NOT_FOUND, ERROR)을
    // 그대로 픽스처로 사용한다(2026-07-18, query=통일로12길 58, category=road 라이브
    // 실측 — 서울 종로구 통일로12길/39길 58 일대 4건이 실제로 이렇게 돌아왔다) — 네트워크
    // 없이 순수 함수만 검증.

    const VWORLD_SEARCH_FIXTURE_OK: &str = r#"{"response" : {"service" : {"name" : "search", "version" : "2.0", "operation" : "search", "time" : "18(ms)"}, "status" : "OK", "record" : {"total" : "4", "current" : "4"}, "page" : {"total" : "1", "current" : "1", "size" : "10"}, "result" : {"crs" : "EPSG:4326", "type" : "address", "items" : [
        {"id" : "1111018100102100118", "address" : {"zipcode" : "03026", "category" : "road", "road" : "서울특별시 종로구 통일로12길 58-2 (행촌동)", "parcel" : "행촌동 210-118", "bldnm" : "", "bldnmdc" : ""}, "point" : {"x" : "126.9619508464101", "y" : "37.57487101858912"}},
        {"id" : "1111018100102100117", "address" : {"zipcode" : "03026", "category" : "road", "road" : "서울특별시 종로구 통일로12길 58-4 (행촌동)", "parcel" : "행촌동 210-117", "bldnm" : "", "bldnmdc" : ""}, "point" : {"x" : "126.96209959387484", "y" : "37.574867567460515"}},
        {"id" : "1111018100102100697", "address" : {"zipcode" : "03026", "category" : "road", "road" : "서울특별시 종로구 통일로12길 58-6 (행촌동)", "parcel" : "행촌동 210-697", "bldnm" : "", "bldnmdc" : ""}, "point" : {"x" : "126.9621817768535", "y" : "37.57491628482984"}},
        {"id" : "1111013300100580012", "address" : {"zipcode" : "03676", "category" : "road", "road" : "서울특별시 종로구 통일로39길 58-12 (홍제동,고은주택)", "parcel" : "홍제동 58-12", "bldnm" : "", "bldnmdc" : ""}, "point" : {"x" : "126.94158783314526", "y" : "37.5875524980416"}}
    ]}}}"#;

    const VWORLD_SEARCH_FIXTURE_NOT_FOUND: &str = r#"{"response" : {"service" : {"name" : "search", "version" : "2.0", "operation" : "search", "time" : "5(ms)"}, "status" : "NOT_FOUND", "record" : {"total" : "0", "current" : "0"}, "page" : {"total" : "0", "current" : "1", "size" : "10"}}}"#;

    // 2026-07-18 라이브 실측(잘못된 키로 Search 엔드포인트 호출) — GetCoord와 동일한
    // status:"ERROR"/error:{code,text} 형태임을 확인했다.
    const VWORLD_SEARCH_FIXTURE_ERROR: &str = r#"{"response" : {"service" : {"name" : "search", "version" : "2.0", "operation" : "search", "time" : "1(ms)"}, "status" : "ERROR", "error" : {"level" : "2", "code" : "INVALID_KEY", "text" : "등록되지 않은 인증키입니다."}}}"#;

    #[test]
    fn parse_vworld_search_items_ok_returns_all_four_items_in_order() {
        let v: serde_json::Value = serde_json::from_str(VWORLD_SEARCH_FIXTURE_OK).unwrap();
        let results = parse_vworld_search_items(&v);
        assert_eq!(results.len(), 4, "4건 모두 담겨야 함: {results:?}");

        assert_eq!(results[0].address, "서울특별시 종로구 통일로12길 58-2 (행촌동)");
        assert!((results[0].lon - 126.9619508464101).abs() < 1e-9, "x=lon 이어야 함");
        assert!((results[0].lat - 37.57487101858912).abs() < 1e-9, "y=lat 이어야 함");

        assert_eq!(results[3].address, "서울특별시 종로구 통일로39길 58-12 (홍제동,고은주택)");
        assert!((results[3].lon - 126.94158783314526).abs() < 1e-9);
        assert!((results[3].lat - 37.5875524980416).abs() < 1e-9);

        assert_eq!(vworld_error_info(&v), None);
    }

    #[test]
    fn parse_vworld_search_items_not_found_returns_empty_and_no_error_info() {
        let v: serde_json::Value = serde_json::from_str(VWORLD_SEARCH_FIXTURE_NOT_FOUND).unwrap();
        assert!(parse_vworld_search_items(&v).is_empty());
        assert_eq!(vworld_error_info(&v), None, "NOT_FOUND는 ERROR가 아니므로 error info가 없어야 함");
    }

    #[test]
    fn parse_vworld_search_items_error_returns_empty_and_extracts_error_info() {
        let v: serde_json::Value = serde_json::from_str(VWORLD_SEARCH_FIXTURE_ERROR).unwrap();
        assert!(parse_vworld_search_items(&v).is_empty());
        let (code, text) = vworld_error_info(&v).expect("ERROR 응답은 error info가 있어야 함");
        assert_eq!(code, "INVALID_KEY");
        assert_eq!(text, "등록되지 않은 인증키입니다.");
    }

    #[test]
    fn parse_vworld_search_items_malformed_json_does_not_panic() {
        // status만 있고 result/items가 없는 경우(스키마 밖 형태) — panic 없이 빈 Vec.
        let v: serde_json::Value = serde_json::json!({"response": {"status": "OK"}});
        assert!(parse_vworld_search_items(&v).is_empty());
    }

    #[test]
    fn parse_vworld_search_items_falls_back_to_parcel_when_road_empty() {
        // address.road가 빈 문자열인 방어적 케이스 — parcel로 폴백해야 한다.
        let v: serde_json::Value = serde_json::json!({"response": {"status": "OK", "result": {"items": [
            {"address": {"road": "", "parcel": "행촌동 210-118"}, "point": {"x": "126.96", "y": "37.57"}}
        ]}}});
        let results = parse_vworld_search_items(&v);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].address, "행촌동 210-118");
    }

    // ── /geocode/search: beon_variant("OO로N길" ↔ "OO로N번길" 폴백 변형) ──

    #[test]
    fn beon_variant_inserts_beon_when_missing() {
        // 실사용자 리포트 사례: "번" 누락. V-World 정식 등록명은 "신창로55번길".
        assert_eq!(
            beon_variant("신창로55길 29"),
            Some("신창로55번길 29".to_string())
        );
    }

    #[test]
    fn beon_variant_removes_beon_when_already_present() {
        // 제거 브랜치: 이 함수는 오직 원본이 이미 NOT_FOUND난 뒤의 폴백으로만 호출되므로,
        // "번길"이 이미 있는 입력이 여기 들어오는 유일한 실사용 경로는 "번을 과다 입력한"
        // 드문 경우뿐이다(정상 표기였다면 원본 시도에서 이미 매치되어 폴백 자체가 안 불림).
        assert_eq!(
            beon_variant("신창로55번길 29"),
            Some("신창로55길 29".to_string())
        );
    }

    #[test]
    fn beon_variant_no_gil_pattern_returns_none() {
        assert_eq!(beon_variant("세종대로 110"), None);
    }

    #[test]
    fn beon_variant_gil_without_preceding_digit_returns_none() {
        // "길"이 있어도 바로 앞이 숫자가 아니면(예: 순우리말 지명) 정규화 대상이 아니다.
        assert_eq!(beon_variant("논길 15"), None);
    }

    #[test]
    fn beon_variant_only_processes_first_match_no_double_insert() {
        // "번길"이 이미 있는 케이스가 최우선 분기이므로, 뒤쪽에 다른 digit+길이 있어도
        // 제거 변형 하나만 반환하고 추가 삽입으로 뒤섞인 결과를 만들지 않는다.
        let variant = beon_variant("신창로55번길 12길 3").expect("번길 포함 — Some이어야 함");
        assert_eq!(variant, "신창로55길 12길 3");
    }

    // ── gis_to_wgs84: Opinet TM 역변환 ──

    #[test]
    fn gis_to_wgs84_converts_known_seoul_stations() {
        // 2026-07-25 pyproj(proj='tmerc',lat_0=38,lon_0=128,k=1,x_0=400000,y_0=600000,ellps='WGS84')
        // 역변환으로 검증한 실제 Opinet API 응답값 3건(서울 종로구·강남구)
        let cases: &[(f64, f64, f64, f64)] = &[
            // (gis_x, gis_y, expect_lat, expect_lon)
            (311970.2, 554223.7, 37.5834, 127.0034), // 혜화주유소(종로구)
            (315530.0, 542774.0, 37.4806, 127.0450), // 유진주유소(강남구)
            (314126.0, 546815.0, 37.5168, 127.0286), // 신사현대주유소(강남구)
        ];
        for &(gx, gy, elat, elon) in cases {
            let (lat, lon) = gis_to_wgs84(gx, gy);
            assert!(
                (lat - elat).abs() < 0.001,
                "lat 오차 초과 gis=({gx},{gy}): got {lat:.5}, want {elat:.5}"
            );
            assert!(
                (lon - elon).abs() < 0.001,
                "lon 오차 초과 gis=({gx},{gy}): got {lon:.5}, want {elon:.5}"
            );
        }
    }
}
