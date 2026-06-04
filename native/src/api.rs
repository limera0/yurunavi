// flutter_rust_bridge annotations enable codegen:
//   flutter_rust_bridge_codegen generate
// All public structs/functions below are exposed to Dart automatically.

/// GPS 좌표 포인트
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug, Clone)]
pub struct GpsPoint {
    pub lat: f64,
    pub lng: f64,
}

/// 경로 유사도 체크 결과
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug)]
pub struct SimilarityResult {
    /// Jaccard 유사도 (0.0 ~ 1.0)
    pub score: f64,
    /// 70% 이상이면 true
    pub is_duplicate: bool,
}

/// 와인딩 필터 결과
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug)]
pub struct WindingScore {
    /// 와인딩 점수 (0.0 ~ 100.0)
    pub score: f64,
    /// 분류: "country" | "provincial" | "national"
    pub road_type: String,
}

/// 후보 경로 순위 (fun-road v1: 곡률만, 숲/고도는 다음 모듈 몫)
#[derive(Debug, Clone)]
pub struct RouteRank {
    /// routes 입력 배열에서의 원래 인덱스
    pub original_index: usize,
    /// 종합 fun 점수 (0.0~100.0, 높을수록 재미있는 길)
    pub fun_score: f64,
    /// 곡률 τ = 궤적길이 L / 직선거리 C (≥1.0)
    pub curvature_tau: f64,
}

/// 경로 계산 결과 (Flutter ↔ Rust 전달 단위)
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug, Clone)]
pub struct RouteResult {
    /// 보간된 GPS 포인트 목록
    pub points: Vec<GpsPoint>,
    /// 총 거리 (미터)
    pub total_distance_m: f64,
    /// 와인딩 점수 (0~100)
    pub winding_score: f64,
    /// 도로 분류
    pub road_type: String,
}

// ── 경로 유사도 알고리즘 (Jaccard, ~1.1km 격자) ──────────────

const GRID_SIZE: f64 = 0.01; // ~1.1km 격자 셀
const INTERPOLATION_STEP: f64 = 0.005;

fn point_to_cell(lat: f64, lng: f64) -> (i64, i64) {
    ((lat / GRID_SIZE).floor() as i64, (lng / GRID_SIZE).floor() as i64)
}

fn route_to_cells(points: &[GpsPoint]) -> std::collections::HashSet<(i64, i64)> {
    let mut cells = std::collections::HashSet::new();
    for i in 0..points.len().saturating_sub(1) {
        let p1 = &points[i];
        let p2 = &points[i + 1];
        let dist = ((p2.lat - p1.lat).powi(2) + (p2.lng - p1.lng).powi(2)).sqrt();
        let steps = (dist / INTERPOLATION_STEP).ceil().max(1.0) as usize;
        for s in 0..=steps {
            let t = s as f64 / steps as f64;
            let lat = p1.lat + (p2.lat - p1.lat) * t;
            let lng = p1.lng + (p2.lng - p1.lng) * t;
            cells.insert(point_to_cell(lat, lng));
        }
    }
    cells
}

/// 두 경로의 유사도를 계산한다.
/// - `route_a`, `route_b`: GPS 포인트 벡터
/// - 반환: SimilarityResult { score, is_duplicate }
#[flutter_rust_bridge::frb]
pub fn check_route_similarity(
    route_a: Vec<GpsPoint>,
    route_b: Vec<GpsPoint>,
) -> SimilarityResult {
    if route_a.is_empty() || route_b.is_empty() {
        return SimilarityResult { score: 0.0, is_duplicate: false };
    }
    let cells_a = route_to_cells(&route_a);
    let cells_b = route_to_cells(&route_b);

    let intersection = cells_a.intersection(&cells_b).count();
    let union = cells_a.union(&cells_b).count();

    let score = if union == 0 { 0.0 } else { intersection as f64 / union as f64 };
    SimilarityResult {
        score,
        is_duplicate: score >= 0.70,
    }
}

// ── 와인딩 필터 알고리즘 ──────────────────────────────────────

/// 두 점 사이 bearing(방위각) 변화(도)
fn bearing_change(p0: &GpsPoint, p1: &GpsPoint, p2: &GpsPoint) -> f64 {
    let b1 = bearing(p0, p1);
    let b2 = bearing(p1, p2);
    let mut delta = (b2 - b1).abs();
    if delta > 180.0 { delta = 360.0 - delta; }
    delta
}

fn bearing(a: &GpsPoint, b: &GpsPoint) -> f64 {
    let lat1 = a.lat.to_radians();
    let lat2 = b.lat.to_radians();
    let dlon = (b.lng - a.lng).to_radians();
    let x = dlon.sin() * lat2.cos();
    let y = lat1.cos() * lat2.sin() - lat1.sin() * lat2.cos() * dlon.cos();
    x.atan2(y).to_degrees()
}

/// 경로의 와인딩 점수를 계산한다.
///
/// 알고리즘:
/// 1. 연속 세 포인트 간 방위각 변화의 누적 합계를 경로 거리로 정규화
/// 2. 점수 0~100: 높을수록 꼬불꼬불한 도로 (시골길)
/// 3. road_type 분류: score < 20 → national, 20~50 → provincial, >50 → country
#[flutter_rust_bridge::frb]
pub fn calc_winding_score(route: Vec<GpsPoint>) -> WindingScore {
    if route.len() < 3 {
        return WindingScore { score: 0.0, road_type: "national".to_string() };
    }

    let mut total_angle = 0.0_f64;
    let mut total_dist_m = 0.0_f64;

    for i in 1..route.len() - 1 {
        let angle = bearing_change(&route[i - 1], &route[i], &route[i + 1]);
        total_angle += angle;
        total_dist_m += haversine_m(&route[i - 1], &route[i]);
    }
    if total_dist_m < 1.0 {
        return WindingScore { score: 0.0, road_type: "national".to_string() };
    }

    // 각도/km 기준으로 정규화, 100도/km = 100점 기준 상한
    let score_raw = (total_angle / (total_dist_m / 1000.0)).min(200.0);
    let score = (score_raw / 200.0 * 100.0).clamp(0.0, 100.0);

    let road_type = if score < 20.0 {
        "national"
    } else if score < 50.0 {
        "provincial"
    } else {
        "country"
    };

    WindingScore { score, road_type: road_type.to_string() }
}

fn haversine_m(a: &GpsPoint, b: &GpsPoint) -> f64 {
    const R: f64 = 6_371_000.0;
    let d_lat = (b.lat - a.lat).to_radians();
    let d_lon = (b.lng - a.lng).to_radians();
    let sin_half_lat = (d_lat / 2.0).sin();
    let sin_half_lon = (d_lon / 2.0).sin();
    let h = sin_half_lat * sin_half_lat
        + a.lat.to_radians().cos()
        * b.lat.to_radians().cos()
        * sin_half_lon * sin_half_lon;
    2.0 * R * h.sqrt().asin()
}

/// 경로 곡률 τ = 궤적 전체 길이(L) / 출발~도착 직선 거리(C).
///
/// - τ = 1.0 : 완전한 직선 도로
/// - τ > 1.0 : 꼬불꼬불할수록 증가
/// - 포인트 수 < 2 또는 직선거리 < 1m 이면 1.0 반환 (나눗셈 방지)
pub fn calc_tortuosity(route: &[GpsPoint]) -> f64 {
    if route.len() < 2 {
        return 1.0;
    }
    let straight = haversine_m(&route[0], &route[route.len() - 1]);
    if straight < 1.0 {
        return 1.0;
    }
    let path_len: f64 = route.windows(2).map(|w| haversine_m(&w[0], &w[1])).sum();
    (path_len / straight).max(1.0)
}

/// Fun-road 점수 v1 — 곡률(τ) 항만 반영.
///
/// 향후 숲 근접도, 교통량, 도로 등급 항이 추가될 예정.
/// τ 기준: 1.0→0점, 2.0→50점, 3.0+→100점(상한).
pub fn fun_score_v1(route: &[GpsPoint]) -> f64 {
    let tau = calc_tortuosity(route);
    ((tau - 1.0) * 50.0).clamp(0.0, 100.0)
}

/// 후보 경로 목록을 fun_score 기준으로 내림차순 정렬해 반환한다.
///
/// 입력: Valhalla 또는 Rust가 생성한 경로 목록 (각 경로 = Vec<GpsPoint>).
/// 반환: fun_score 높은 순. original_index 로 원본 배열 참조 가능.
pub fn rank_candidates(routes: Vec<Vec<GpsPoint>>) -> Vec<RouteRank> {
    let mut ranks: Vec<RouteRank> = routes
        .iter()
        .enumerate()
        .map(|(i, route)| RouteRank {
            original_index: i,
            fun_score: fun_score_v1(route),
            curvature_tau: calc_tortuosity(route),
        })
        .collect();
    ranks.sort_by(|a, b| {
        b.fun_score
            .partial_cmp(&a.fun_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    ranks
}

/// FC1~FC5 도로 등급을 0~100 재미 점수로 변환.
///
/// - FC1 (motorway/고속) → 0점 (재미없음)
/// - FC5 (tertiary/residential/소로) → 100점 (최고 재미)
/// - avg_fc 범위: 1.0~5.0 (Valhalla Functional Class 평균)
pub fn road_class_score(avg_fc: f64) -> f64 {
    (avg_fc.clamp(1.0, 5.0) - 1.0) / 4.0 * 100.0
}

/// Fun-road 점수 v2 — 곡률(τ) 60% + 도로등급(FC) 40% 합산.
///
/// avg_fc: Valhalla FC 평균 (1.0=FC1 국도·고속, 5.0=FC5 소로·농도).
/// 반환: 0.0~100.0.
pub fn fun_score_v2(route: &[GpsPoint], avg_fc: f64) -> f64 {
    let tau_score = fun_score_v1(route);
    let fc_score  = road_class_score(avg_fc);
    (0.6 * tau_score + 0.4 * fc_score).clamp(0.0, 100.0)
}

/// v2 후보 순위: (경로 포인트, Valhalla FC 평균) 쌍을 받아
/// fun_score_v2 기준 내림차순 정렬.
pub fn rank_candidates_v2(routes: Vec<(Vec<GpsPoint>, f64)>) -> Vec<RouteRank> {
    let mut ranks: Vec<RouteRank> = routes
        .iter()
        .enumerate()
        .map(|(i, (route, avg_fc))| RouteRank {
            original_index: i,
            fun_score: fun_score_v2(route, *avg_fc),
            curvature_tau: calc_tortuosity(route),
        })
        .collect();
    ranks.sort_by(|a, b| {
        b.fun_score
            .partial_cmp(&a.fun_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    ranks
}

/// 교통량 대리지표: 도로 제한속도 기반 재미 점수 (0~100).
///
/// 낮은 속도 = 좁고 조용한 도로 = 높은 재미.
/// 20km/h → 100pts, 50km/h → 50pts, ≥80km/h → 0pts.
pub fn traffic_score(avg_speed_kmh: f64) -> f64 {
    let clamped = avg_speed_kmh.clamp(20.0, 80.0);
    (80.0 - clamped) / 60.0 * 100.0
}

/// Fun-road 점수 v3 — 곡률(τ) 50% + 도로등급(FC) 30% + 교통량(speed) 20%.
///
/// avg_speed_kmh: trace_attributes 에서 취득한 엣지 속도 가중평균 (km/h).
pub fn fun_score_v3(route: &[GpsPoint], avg_fc: f64, avg_speed_kmh: f64) -> f64 {
    let tau_score     = fun_score_v1(route);
    let fc_score      = road_class_score(avg_fc);
    let t_score       = traffic_score(avg_speed_kmh);
    (0.5 * tau_score + 0.3 * fc_score + 0.2 * t_score).clamp(0.0, 100.0)
}

/// FC 등급 가중치 v2 (비선형): motorway→0, trunk→30, primary→60, secondary→85, unclassified→100.
///
/// 현재 road_class_score 는 선형(0~100). v2는 상위 도로(고속·간선) 감점을 강화.
/// avg_fc: Valhalla FC 평균 (1.0=FC1 motorway, 5.0=FC5 소로).
pub fn road_class_score_v2(avg_fc: f64) -> f64 {
    let fc = avg_fc.clamp(1.0, 5.0);
    // FC→점수 구간별 선형 보간
    // FC1→0, FC2→30, FC3→60, FC4→85, FC5→100
    let score = if fc <= 2.0 {
        (fc - 1.0) * 30.0
    } else if fc <= 3.0 {
        30.0 + (fc - 2.0) * 30.0
    } else if fc <= 4.0 {
        60.0 + (fc - 3.0) * 25.0
    } else {
        85.0 + (fc - 4.0) * 15.0
    };
    score.clamp(0.0, 100.0)
}

/// 숲 근접도 점수 (0~100).
/// forest_proximity: 0.0 = 숲 없음, 1.0 = 경로 전체가 숲 속.
/// OSM landuse=forest / natural=wood 폴리곤으로부터 전처리 필요.
pub fn forest_score(forest_proximity: f64) -> f64 {
    forest_proximity.clamp(0.0, 1.0) * 100.0
}

/// Fun-road 점수 v4 — 4개 항 합산.
/// 가중치: τ×40% + FC×25% + speed×15% + forest×20%.
/// forest_proximity: 0.0~1.0 (OSM 전처리 인덱스에서 취득).
pub fn fun_score_v4(
    route: &[GpsPoint],
    avg_fc: f64,
    avg_speed_kmh: f64,
    forest_proximity: f64,
) -> f64 {
    let tau_score = fun_score_v1(route);
    let fc_s      = road_class_score(avg_fc);
    let t_s       = traffic_score(avg_speed_kmh);
    let f_s       = forest_score(forest_proximity);
    (0.40 * tau_score + 0.25 * fc_s + 0.15 * t_s + 0.20 * f_s).clamp(0.0, 100.0)
}

// ── 경로 계산 (Flutter → Rust 진입점) ────────────────────────────

/// Flutter에서 호출하는 실제 경로 계산 함수.
///
/// `#[flutter_rust_bridge::frb(sync)]` 대신 비동기로 선언해
/// Dart isolate를 블록하지 않는다.
///
/// 디버그 출력(`eprintln!`)은 `flutter run` 콘솔에서 확인 가능.
/// 배포 빌드에서는 `--release` 플래그로 제거됨.
#[flutter_rust_bridge::frb]
pub fn calc_route(
    origin: GpsPoint,
    destination: GpsPoint,
    waypoints: Vec<GpsPoint>,
    route_type: i32,
) -> RouteResult {
    eprintln!(
        "[YuruNavi/Rust] calc_route called: origin=({:.6},{:.6}) dest=({:.6},{:.6}) waypoints={} route_type={}",
        origin.lat, origin.lng,
        destination.lat, destination.lng,
        waypoints.len(),
        route_type,
    );

    for (i, wp) in waypoints.iter().enumerate() {
        eprintln!("[YuruNavi/Rust]   waypoint[{}]=({:.6},{:.6})", i, wp.lat, wp.lng);
    }

    // ── 좌표 유효성 검증 ───────────────────────────────────────
    // lat 범위: -90~90, lng 범위: -180~180
    // 범위 초과 시 origin 근방의 빈 경로를 반환해 앱 크래시를 방지한다.
    let coords_valid = |p: &GpsPoint| {
        p.lat >= -90.0 && p.lat <= 90.0 && p.lng >= -180.0 && p.lng <= 180.0
    };
    if !coords_valid(&origin) || !coords_valid(&destination) {
        eprintln!("[YuruNavi/Rust] ERROR: invalid coordinates detected — aborting route calc");
        return RouteResult {
            points: vec![origin.clone()],
            total_distance_m: 0.0,
            winding_score: 0.0,
            road_type: "national".to_string(),
        };
    }

    // ── 보간 파라미터 (route_type 별) ──────────────────────────
    let (amplitude, steps): (f64, usize) = match route_type {
        0 => (0.018, 28), // 시골길
        1 => (0.010, 22), // 지방도로
        _ => (0.004, 16), // 국도 (기본)
    };

    let all_stops: Vec<&GpsPoint> = std::iter::once(&origin)
        .chain(waypoints.iter())
        .chain(std::iter::once(&destination))
        .collect();

    let mut points: Vec<GpsPoint> = Vec::new();
    let mut total_dist = 0.0_f64;
    let mut phase: f64 = 0.0;
    let wave_count = match route_type { 0 => 3.0, 1 => 2.0, _ => 1.0 };

    for seg in 0..all_stops.len() - 1 {
        let from = all_stops[seg];
        let to = all_stops[seg + 1];

        let d_lat = to.lat - from.lat;
        let d_lng = to.lng - from.lng;
        let len = (d_lat * d_lat + d_lng * d_lng).sqrt();
        let (nx, ny) = if len > 0.0 { (-d_lng / len, d_lat / len) } else { (0.0, 0.0) };

        // pseudo-random phase per segment (deterministic, no std::Random needed)
        phase = (phase + 1.3) % (2.0 * std::f64::consts::PI);

        for i in 0..=steps {
            if i == 0 && seg > 0 { continue; } // avoid duplicate junction point
            let t = i as f64 / steps as f64;
            let wave = ((t * std::f64::consts::PI * wave_count + phase) as f64).sin();
            let lat = from.lat + d_lat * t + ny * wave * amplitude;
            let lng = from.lng + d_lng * t + nx * wave * amplitude;

            if let Some(prev) = points.last() {
                total_dist += haversine_m(prev, &GpsPoint { lat, lng });
            }
            points.push(GpsPoint { lat, lng });
        }
    }

    let winding = if points.len() >= 3 {
        calc_winding_score(points.clone())
    } else {
        WindingScore { score: 0.0, road_type: "national".to_string() }
    };

    eprintln!(
        "[YuruNavi/Rust] calc_route done: {} points, {:.0}m, winding={:.1} ({})",
        points.len(), total_dist, winding.score, winding.road_type
    );

    RouteResult {
        points,
        total_distance_m: total_dist,
        winding_score: winding.score,
        road_type: winding.road_type,
    }
}

// ── 엣지 케이스 가드 ─────────────────────────────────────────────

/// GPS 측위 품질 분류
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug, Clone, PartialEq)]
pub enum GpsQuality {
    /// 정상 측위 (정확도 ≤ 20m, 타임스탬프 신선)
    Good,
    /// 측위 저하 (정확도 20–50m 또는 3–8초 경과)
    Degraded,
    /// 측위 불량 (정확도 > 50m 또는 8초 이상 경과)
    Poor,
}

/// GPS 정확도 및 타임스탬프 신선도를 검사한다.
///
/// - `accuracy_m`: 디바이스에서 보고한 수평 정확도 (미터).
/// - `age_ms`: 마지막 GPS 업데이트로부터 경과한 시간 (밀리초).
///
/// 반환: [GpsQuality] — Flutter에서 UI 경고 표시 여부 결정에 사용.
#[flutter_rust_bridge::frb]
pub fn check_gps_accuracy(accuracy_m: f64, age_ms: u64) -> GpsQuality {
    if accuracy_m < 0.0 {
        eprintln!("[YuruNavi/Rust] check_gps_accuracy: negative accuracy ({accuracy_m}) treated as Poor");
        return GpsQuality::Poor;
    }
    let age_s = age_ms / 1000;
    let quality = if accuracy_m <= 20.0 && age_s < 3 {
        GpsQuality::Good
    } else if accuracy_m <= 50.0 && age_s < 8 {
        GpsQuality::Degraded
    } else {
        GpsQuality::Poor
    };
    if quality != GpsQuality::Good {
        eprintln!(
            "[YuruNavi/Rust] check_gps_accuracy: accuracy={accuracy_m:.1}m age={age_s}s → {:?}",
            quality
        );
    }
    quality
}

/// 이탈 감지 결과
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug, Clone)]
pub struct OffRouteStatus {
    /// 경로 이탈 여부
    pub is_off_route: bool,
    /// 가장 가까운 경로 포인트까지의 거리 (미터)
    pub closest_point_distance_m: f64,
    /// 이탈 임계값 (미터) — 이 값보다 멀면 재경로 계산 트리거
    pub threshold_m: f64,
}

/// 현재 위치가 경로 corridor 안에 있는지 검사한다.
///
/// 경로 상 모든 포인트 사이 선분과의 최소 수직 거리를 계산한다.
/// `threshold_m`을 초과하면 재경로 계산이 필요하다는 신호를 반환한다.
///
/// - `current`: 라이더의 현재 위치.
/// - `route`: 계획된 경로 포인트 배열.
/// - `threshold_m`: 이탈 판정 임계값 (기본 권장: 150m).
#[flutter_rust_bridge::frb]
pub fn is_off_route(
    current: GpsPoint,
    route: Vec<GpsPoint>,
    threshold_m: f64,
) -> OffRouteStatus {
    // Guard: threshold must be positive and route must have at least 2 points.
    let threshold_m = if threshold_m <= 0.0 { 150.0 } else { threshold_m };

    if route.len() < 2 {
        eprintln!("[YuruNavi/Rust] is_off_route: route has < 2 points — returning off-route");
        return OffRouteStatus {
            is_off_route: true,
            closest_point_distance_m: f64::MAX,
            threshold_m,
        };
    }

    // Coordinate validity guard.
    let coords_valid = |p: &GpsPoint| {
        p.lat >= -90.0 && p.lat <= 90.0 && p.lng >= -180.0 && p.lng <= 180.0
    };
    if !coords_valid(&current) {
        eprintln!("[YuruNavi/Rust] is_off_route: invalid current position — skipping");
        return OffRouteStatus {
            is_off_route: false,
            closest_point_distance_m: 0.0,
            threshold_m,
        };
    }

    // Find the minimum distance from `current` to any segment of the route.
    let mut min_dist = f64::MAX;

    for i in 0..route.len() - 1 {
        let a = &route[i];
        let b = &route[i + 1];
        let d = point_to_segment_distance_m(&current, a, b);
        if d < min_dist {
            min_dist = d;
        }
    }

    let off = min_dist > threshold_m;
    if off {
        eprintln!(
            "[YuruNavi/Rust] is_off_route: TRIGGERED — {:.0}m from route (threshold {:.0}m)",
            min_dist, threshold_m
        );
    }

    OffRouteStatus {
        is_off_route: off,
        closest_point_distance_m: min_dist,
        threshold_m,
    }
}

/// 목적지 도달 가능성 결과
#[flutter_rust_bridge::frb(dart_metadata = ("freezed"))]
#[derive(Debug, Clone)]
pub struct ReachabilityResult {
    pub is_reachable: bool,
    /// 사람이 읽을 수 있는 도달 불가 이유 (도달 가능 시 빈 문자열)
    pub reason: String,
}

/// 목적지가 정상적인 경로 계산 대상인지 검사한다.
///
/// 실패 케이스:
/// 1. origin == destination (동일 좌표, 오차 10m 이내)
/// 2. 직선 거리 > 1500km (현실적인 바이크 투어 범위 초과)
/// 3. 좌표 범위 초과
#[flutter_rust_bridge::frb]
pub fn check_destination_reachable(
    origin: GpsPoint,
    destination: GpsPoint,
) -> ReachabilityResult {
    let coords_valid = |p: &GpsPoint| {
        p.lat >= -90.0 && p.lat <= 90.0 && p.lng >= -180.0 && p.lng <= 180.0
    };

    if !coords_valid(&origin) || !coords_valid(&destination) {
        return ReachabilityResult {
            is_reachable: false,
            reason: "invalid_coordinates".to_string(),
        };
    }

    let dist_m = haversine_m(&origin, &destination);

    // Same-point guard: within 10 m is treated as "already there".
    if dist_m < 10.0 {
        eprintln!("[YuruNavi/Rust] check_destination_reachable: origin ≈ destination ({dist_m:.1}m)");
        return ReachabilityResult {
            is_reachable: false,
            reason: "same_location".to_string(),
        };
    }

    // Unreachable-by-motorcycle guard: > 1500 km straight line.
    const MAX_DIST_M: f64 = 1_500_000.0;
    if dist_m > MAX_DIST_M {
        eprintln!(
            "[YuruNavi/Rust] check_destination_reachable: distance {:.0}km exceeds 1500km limit",
            dist_m / 1000.0
        );
        return ReachabilityResult {
            is_reachable: false,
            reason: "too_far".to_string(),
        };
    }

    ReachabilityResult {
        is_reachable: true,
        reason: String::new(),
    }
}

// ── 내부 헬퍼: 점 → 선분 수직 거리 ─────────────────────────────

/// 점 P에서 선분 AB까지의 최단 거리 (미터, haversine 근사).
fn point_to_segment_distance_m(p: &GpsPoint, a: &GpsPoint, b: &GpsPoint) -> f64 {
    let ab_dist = haversine_m(a, b);
    if ab_dist < 1.0 {
        // Degenerate segment: A ≈ B, just return distance to A.
        return haversine_m(p, a);
    }

    // Project P onto the infinite line through A–B using dot product in
    // lat/lng space (valid for short distances where distortion is small).
    let ax = b.lat - a.lat;
    let ay = b.lng - a.lng;
    let bx = p.lat - a.lat;
    let by = p.lng - a.lng;
    let t = ((bx * ax + by * ay) / (ax * ax + ay * ay)).clamp(0.0, 1.0);

    let closest = GpsPoint {
        lat: a.lat + t * ax,
        lng: a.lng + t * ay,
    };
    haversine_m(p, &closest)
}

// ── 단위 테스트 ───────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_routes_are_100_pct_similar() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0 + i as f64 * 0.01, lng: 127.0 })
            .collect();
        let result = check_route_similarity(route.clone(), route);
        assert!(result.score > 0.99);
        assert!(result.is_duplicate);
    }

    #[test]
    fn winding_score_straight_road_is_low() {
        let route: Vec<GpsPoint> = (0..20)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let ws = calc_winding_score(route);
        assert!(ws.score < 20.0, "직선 도로 점수가 너무 높음: {}", ws.score);
    }

    // ── 엣지 케이스 테스트 ──────────────────────────────────────

    #[test]
    fn gps_quality_good_accuracy() {
        assert_eq!(check_gps_accuracy(10.0, 1000), GpsQuality::Good);
    }

    #[test]
    fn gps_quality_degraded_accuracy() {
        assert_eq!(check_gps_accuracy(35.0, 5000), GpsQuality::Degraded);
    }

    #[test]
    fn gps_quality_poor_old_fix() {
        // Age > 8 seconds should be Poor regardless of accuracy.
        assert_eq!(check_gps_accuracy(5.0, 10_000), GpsQuality::Poor);
    }

    #[test]
    fn gps_quality_negative_accuracy_is_poor() {
        assert_eq!(check_gps_accuracy(-1.0, 500), GpsQuality::Poor);
    }

    #[test]
    fn off_route_detects_large_deviation() {
        // Straight route along latitude 37.0.
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        // Position 1 degree north — vastly off route (~111 km).
        let far_pos = GpsPoint { lat: 38.0, lng: 127.05 };
        let result = is_off_route(far_pos, route, 150.0);
        assert!(result.is_off_route, "rider is 111km away — should be off-route");
        assert!(result.closest_point_distance_m > 150.0);
    }

    #[test]
    fn on_route_not_flagged() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        // Position exactly on the route.
        let on_pos = GpsPoint { lat: 37.0, lng: 127.05 };
        let result = is_off_route(on_pos, route, 150.0);
        assert!(!result.is_off_route, "position on route should not trigger re-route");
    }

    #[test]
    fn off_route_empty_route_is_off() {
        let result = is_off_route(
            GpsPoint { lat: 37.0, lng: 127.0 },
            vec![],
            150.0,
        );
        assert!(result.is_off_route, "empty route = off route");
    }

    #[test]
    fn destination_same_as_origin_unreachable() {
        let origin = GpsPoint { lat: 37.5665, lng: 126.9780 };
        let dest = GpsPoint { lat: 37.5665, lng: 126.9780 };
        let r = check_destination_reachable(origin, dest);
        assert!(!r.is_reachable);
        assert_eq!(r.reason, "same_location");
    }

    #[test]
    fn destination_too_far_unreachable() {
        // Seoul → Buenos Aires (~18,000 km).
        let origin = GpsPoint { lat: 37.5665, lng: 126.9780 };
        let dest = GpsPoint { lat: -34.6037, lng: -58.3816 };
        let r = check_destination_reachable(origin, dest);
        assert!(!r.is_reachable);
        assert_eq!(r.reason, "too_far");
    }

    #[test]
    fn normal_destination_is_reachable() {
        // Seoul → Busan (~325 km).
        let origin = GpsPoint { lat: 37.5665, lng: 126.9780 };
        let dest = GpsPoint { lat: 35.1796, lng: 129.0756 };
        let r = check_destination_reachable(origin, dest);
        assert!(r.is_reachable, "Seoul→Busan should be reachable");
    }

    #[test]
    fn invalid_coords_unreachable() {
        let invalid = GpsPoint { lat: 999.0, lng: 0.0 };
        let origin = GpsPoint { lat: 37.0, lng: 127.0 };
        let r = check_destination_reachable(origin, invalid);
        assert!(!r.is_reachable);
        assert_eq!(r.reason, "invalid_coordinates");
    }

    #[test]
    fn calc_route_invalid_coords_returns_safe_fallback() {
        // Should not panic; returns a single-point route.
        let origin = GpsPoint { lat: 999.0, lng: 0.0 };
        let dest = GpsPoint { lat: 37.5665, lng: 126.9780 };
        let result = calc_route(origin.clone(), dest, vec![], 2);
        assert_eq!(result.points.len(), 1);
        assert_eq!(result.total_distance_m, 0.0);
    }

    #[test]
    fn zero_threshold_defaults_to_150m() {
        let route: Vec<GpsPoint> = vec![
            GpsPoint { lat: 37.0, lng: 127.0 },
            GpsPoint { lat: 37.1, lng: 127.0 },
        ];
        let result = is_off_route(GpsPoint { lat: 37.05, lng: 127.0 }, route, 0.0);
        assert_eq!(result.threshold_m, 150.0, "zero threshold should default to 150m");
    }

    #[test]
    fn fallback_ratio_triggers_at_1_3() {
        let t_rural = 1300.0_f64;
        let t_prov = 1000.0_f64;
        assert!(t_rural / t_prov >= 1.3, "1300/1000 must trigger fallback");
    }

    #[test]
    fn fallback_ratio_no_trigger_below_1_3() {
        let t_rural = 1290.0_f64;
        let t_prov = 1000.0_f64;
        assert!(t_rural / t_prov < 1.3, "1290/1000 must NOT trigger fallback");
    }

    #[test]
    fn tortuosity_straight_road_is_one() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let tau = calc_tortuosity(&route);
        assert!((tau - 1.0).abs() < 0.02, "직선도로 τ≈1.0 예상, 실제 {tau}");
    }

    #[test]
    fn tortuosity_winding_road_above_one() {
        // 사인파 경로: 실제 궤적이 직선보다 길어야 함
        let route: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let tau = calc_tortuosity(&route);
        assert!(tau > 1.05, "굽이길 τ > 1.05 예상, 실제 {tau}");
    }

    #[test]
    fn fun_score_straight_road_near_zero() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let score = fun_score_v1(&route);
        assert!(score < 5.0, "직선도로 fun_score < 5.0 예상, 실제 {score}");
    }

    #[test]
    fn rank_candidates_winding_first() {
        let straight: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let winding: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let ranks = rank_candidates(vec![straight, winding]);
        assert_eq!(ranks[0].original_index, 1, "굽이길(인덱스 1)이 1위 예상");
        assert!(ranks[0].fun_score > ranks[1].fun_score);
    }

    #[test]
    fn road_class_score_fc1_is_zero() {
        let s = road_class_score(1.0);
        assert!(s.abs() < 0.01, "FC1 should be 0 pts, got {s}");
    }

    #[test]
    fn road_class_score_fc5_is_hundred() {
        let s = road_class_score(5.0);
        assert!((s - 100.0).abs() < 0.01, "FC5 should be 100 pts, got {s}");
    }

    #[test]
    fn fun_score_v2_rural_beats_national() {
        let winding: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let straight: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let rural   = fun_score_v2(&winding, 5.0);
        let national = fun_score_v2(&straight, 2.0);
        assert!(rural > national,
            "시골길 v2={rural:.1} should beat 국도 v2={national:.1}");
    }

    #[test]
    fn rank_candidates_v2_rural_first() {
        let straight: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let winding: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let ranks = rank_candidates_v2(vec![(straight, 2.0), (winding, 5.0)]);
        assert_eq!(ranks[0].original_index, 1,
            "굽이진 시골길(인덱스 1)이 1위여야 함");
        assert!(ranks[0].fun_score > ranks[1].fun_score);
    }

    #[test]
    fn traffic_score_slow_road_is_high() {
        let s = traffic_score(20.0);
        assert!((s - 100.0).abs() < 0.01, "20km/h should be 100pts, got {s}");
    }

    #[test]
    fn traffic_score_fast_road_is_zero() {
        let s = traffic_score(80.0);
        assert!(s.abs() < 0.01, "80km/h should be 0pts, got {s}");
    }

    #[test]
    fn fun_score_v3_rural_quiet_beats_national_fast() {
        let winding: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let straight: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let rural    = fun_score_v3(&winding, 5.0, 25.0); // FC5, 25km/h
        let national = fun_score_v3(&straight, 2.0, 70.0); // FC2, 70km/h
        assert!(rural > national,
            "시골길(v3)={rural:.1} should beat 국도(v3)={national:.1}");
    }

    #[test]
    fn fun_score_v3_speed_bonus_differentiates_same_route() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        // 같은 경로라도 낮은 속도 도로가 높은 점수여야 함
        let slow = fun_score_v3(&route, 3.0, 20.0);
        let fast = fun_score_v3(&route, 3.0, 70.0);
        assert!(slow > fast,
            "같은 경로: slow(20km/h)={slow:.1} > fast(70km/h)={fast:.1} 기대");
    }

    #[test]
    fn forest_score_no_forest_is_zero() {
        assert!(forest_score(0.0).abs() < 0.01, "forest=0 should be 0pts");
    }

    #[test]
    fn forest_score_full_forest_is_hundred() {
        assert!((forest_score(1.0) - 100.0).abs() < 0.01, "forest=1 should be 100pts");
    }

    #[test]
    fn fun_score_v4_forest_route_beats_open() {
        let route: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let forested = fun_score_v4(&route, 4.0, 30.0, 1.0);
        let open     = fun_score_v4(&route, 4.0, 30.0, 0.0);
        assert!(forested > open,
            "숲속 경로={forested:.1} > 개활지={open:.1} 기대");
    }

    #[test]
    fn fun_score_v4_all_terms_contribute() {
        // 시골길: 굽이+FC5+저속+숲 → 높은 점수
        let winding: Vec<GpsPoint> = (0..40)
            .map(|i| {
                let t = i as f64 / 40.0;
                GpsPoint {
                    lat: 37.0 + t * 0.1 + (t * std::f64::consts::PI * 6.0).sin() * 0.02,
                    lng: 127.0 + t * 0.1,
                }
            })
            .collect();
        let rural = fun_score_v4(&winding, 5.0, 25.0, 0.8);
        // 국도: 직선+FC2+고속+숲없음 → 낮은 점수
        let straight: Vec<GpsPoint> = (0..10)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let national = fun_score_v4(&straight, 2.0, 70.0, 0.0);
        assert!(rural > national,
            "시골숲길 v4={rural:.1} > 국도 v4={national:.1} 기대");
        assert!(rural > 50.0, "시골숲길 점수가 50점 이상이어야 함, 실제: {rural:.1}");
    }

    // ── 항목 3: 도로 등급 가중치 v2 ─────────────────────────────────────────

    #[test]
    fn road_class_score_v2_fc1_is_zero() {
        assert!(road_class_score_v2(1.0).abs() < 0.01, "FC1(motorway)→0");
    }

    #[test]
    fn road_class_score_v2_fc2_is_thirty() {
        assert!((road_class_score_v2(2.0) - 30.0).abs() < 0.01, "FC2(trunk)→30");
    }

    #[test]
    fn road_class_score_v2_fc5_is_hundred() {
        assert!((road_class_score_v2(5.0) - 100.0).abs() < 0.01, "FC5(소로)→100");
    }

    #[test]
    fn road_class_score_v2_gives_more_credit_to_secondary_roads() {
        // v2는 지방도(FC4)에 v1보다 높은 점수 부여 → 시골길 선호 강화
        let fc4_v1 = road_class_score(4.0);     // 선형: 75
        let fc4_v2 = road_class_score_v2(4.0);  // v2: 85
        assert!(fc4_v2 > fc4_v1,
            "FC4(지방도) v2({fc4_v2:.1}) > v1({fc4_v1:.1}): v2가 지방도를 더 선호해야 함");
    }

    // ── 항목 2: 고속도로 배제 검증 ──────────────────────────────────────────

    #[test]
    fn motorway_fc1_contributes_zero_to_fun_score() {
        // FC1(motorway) avg_fc=1.0 → road_class_score=0
        // 동일 형상에서 고속도로 경로가 시골길보다 현저히 낮아야 함
        let pts: Vec<GpsPoint> = (0..20)
            .map(|i| GpsPoint { lat: 37.0, lng: 127.0 + i as f64 * 0.01 })
            .collect();
        let motorway_score = fun_score_v2(&pts, 1.0); // FC1 = motorway
        let rural_score    = fun_score_v2(&pts, 5.0); // FC5 = 소로
        assert!(motorway_score < rural_score,
            "고속도로(FC1) 점수({motorway_score:.1}) < 소로(FC5)({rural_score:.1}) 필요");
        assert!(motorway_score < 30.0,
            "고속도로 fun_score < 30 필요, 실제: {motorway_score:.1}");
    }

    #[test]
    fn motorway_link_near_fc1_scores_low() {
        // motorway_link는 FC1~FC2 사이 (avg≈1.3)
        let s = road_class_score(1.3);
        assert!(s < 10.0, "motorway_link(FC1.3) road_class_score < 10 필요, 실제: {s:.1}");
    }
}
