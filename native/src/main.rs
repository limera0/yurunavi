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

#[derive(Deserialize)]
struct PoiNearbyQuery {
    lat: f64,
    lon: f64,
    radius_m: f64,
    #[serde(default)]
    types: Option<String>,
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
    let placeholders: Vec<String> = (0..types.len()).map(|i| format!("?{}", i + 5)).collect();
    let sql = format!(
        "SELECT p.bizes_id, p.name, p.category, p.lat, p.lon, p.address \
         FROM poi_rtree r JOIN poi p ON p.id = r.id \
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

    Ok(with_dist.into_iter().map(|(_, dto)| dto).collect())
}

async fn handle_poi_nearby(
    Query(q): Query<PoiNearbyQuery>,
) -> Result<Json<Vec<PoiDto>>, StatusCode> {
    let mutex = match poi_db() {
        Some(m) => m,
        None => return Err(StatusCode::SERVICE_UNAVAILABLE),
    };
    let conn = mutex.lock().map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let radius_m = q.radius_m.clamp(0.0, MAX_POI_RADIUS_M);
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

    let results = query_poi_nearby(&conn, q.lat, q.lon, radius_m, &types).map_err(|e| {
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
}
