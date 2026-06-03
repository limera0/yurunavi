mod api;
use api::{
    calc_tortuosity, calc_winding_score, check_destination_reachable,
    check_gps_accuracy, check_route_similarity, fun_score_v2, is_off_route,
    GpsPoint, GpsQuality, WindingScore,
};

const VALHALLA_URL: &str = "http://localhost:8002/route";

static HTTP_CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
fn http_client() -> &'static reqwest::Client {
    HTTP_CLIENT.get_or_init(reqwest::Client::new)
}

use axum::{
    extract::Json,
    http::StatusCode,
    routing::{get, post},
    Router,
};
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

async fn trace_attributes_fc(client: &reqwest::Client, pts: &[GpsPointDto]) -> f64 {
    if pts.is_empty() { return 3.0; }
    let step = (pts.len() / 80).max(1);
    let shape: Vec<serde_json::Value> = pts.iter().step_by(step)
        .map(|p| serde_json::json!({"lat": p.lat, "lon": p.lng}))
        .collect();
    let payload = serde_json::json!({
        "shape": shape,
        "costing": "motorcycle",
        "shape_match": "map_snap",
        "filters": {
            "attributes": ["edge.road_class", "edge.length"],
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
        Err(_) => return 3.0,
    };
    weighted_avg_fc(&ta_resp)
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
    fun_score_v2: f64,  // NEW: curvature 60% + FC road class 40%
    avg_fc: f64,        // NEW: Valhalla Functional Class average (1.0-5.0)
}

#[derive(Deserialize)]
struct ScoreRouteReq {
    points: Vec<GpsPointDto>,
}

#[derive(Serialize)]
struct ScoreRouteResp {
    fun_score_v2: f64,
    avg_fc: f64,
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

    let avg_fc = trace_attributes_fc(client, &pts).await;
    let f_score_v2 = fun_score_v2(&api_pts, avg_fc);

    Ok(Json(CalcRouteResp {
        points: pts,
        total_distance_m: km * 1000.0,
        winding_score: winding.score,
        road_type: winding.road_type,
        fun_score_v2: f_score_v2,
        avg_fc,
    }))
}

// ── /score_route ───────────────────────────────────────────────

async fn handle_score_route(
    Json(req): Json<ScoreRouteReq>,
) -> Json<ScoreRouteResp> {
    let client = http_client();
    let avg_fc = trace_attributes_fc(client, &req.points).await;
    let api_pts: Vec<GpsPoint> = req.points.iter()
        .map(|p| GpsPoint { lat: p.lat, lng: p.lng })
        .collect();
    let f_score_v2 = if api_pts.len() >= 2 {
        fun_score_v2(&api_pts, avg_fc)
    } else {
        0.0
    };
    let tau = if api_pts.len() >= 2 {
        calc_tortuosity(&api_pts)
    } else {
        1.0
    };
    Json(ScoreRouteResp { fun_score_v2: f_score_v2, avg_fc, curvature_tau: tau })
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
    let app = Router::new()
        .route("/health", get(handle_health))
        .route("/calc_route", post(handle_calc_route))
        .route("/score_route", post(handle_score_route))
        .route("/calc_winding_score", post(handle_winding))
        .route("/check_route_similarity", post(handle_similarity))
        .route("/check_gps_accuracy", post(handle_gps_accuracy))
        .route("/is_off_route", post(handle_off_route))
        .route("/check_destination_reachable", post(handle_reachability));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8003")
        .await
        .expect("포트 8003 바인딩 실패");
    println!("[YuruNavi/Rust] 서버 시작 — http://0.0.0.0:8003");
    axum::serve(listener, app).await.unwrap();
}
