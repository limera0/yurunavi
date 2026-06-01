mod api;
use api::{
    calc_route, calc_winding_score, check_destination_reachable,
    check_gps_accuracy, check_route_similarity, is_off_route,
    GpsPoint, GpsQuality,
};

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
}

async fn handle_calc_route(
    Json(req): Json<CalcRouteReq>,
) -> Result<Json<CalcRouteResp>, StatusCode> {
    let result = calc_route(
        req.origin.into(),
        req.destination.into(),
        req.waypoints.into_iter().map(Into::into).collect(),
        req.route_type,
    );
    Ok(Json(CalcRouteResp {
        points: result.points.into_iter().map(Into::into).collect(),
        total_distance_m: result.total_distance_m,
        winding_score: result.winding_score,
        road_type: result.road_type,
    }))
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
