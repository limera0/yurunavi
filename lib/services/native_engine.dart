import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// GPS 포인트
class GpsPoint {
  final double lat;
  final double lng;
  const GpsPoint(this.lat, this.lng);
}

/// 유사도 결과
class SimilarityResult {
  final double score;
  final bool isDuplicate;
  const SimilarityResult({required this.score, required this.isDuplicate});
}

/// 와인딩 점수 결과
class WindingScore {
  final double score;
  final String roadType; // "country" | "provincial" | "national"
  const WindingScore({required this.score, required this.roadType});
}

/// GPS 측위 품질 — mirrors Rust GpsQuality enum.
enum GpsQuality { good, degraded, poor }

/// 경로 이탈 상태 — mirrors Rust OffRouteStatus.
class OffRouteStatus {
  final bool isOffRoute;
  final double closestPointDistanceM;
  final double thresholdM;
  const OffRouteStatus({
    required this.isOffRoute,
    required this.closestPointDistanceM,
    required this.thresholdM,
  });
}

/// 목적지 도달 가능성 — mirrors Rust ReachabilityResult.
class ReachabilityResult {
  final bool isReachable;
  final String reason;
  const ReachabilityResult({required this.isReachable, required this.reason});
}

/// Rust native engine의 Dart fallback 구현.
///
/// flutter_rust_bridge codegen 완료 후 native 바인딩으로 교체 가능.
/// API 시그니처는 native/src/api.rs 와 1:1 대응.
class NativeEngine {
  static const double _gridSize = 0.01;
  static const double _interpStep = 0.005;

  // ── 경로 유사도 (Jaccard) ─────────────────────────────────

  static SimilarityResult checkRouteSimilarity(
    List<GpsPoint> routeA,
    List<GpsPoint> routeB,
  ) {
    if (routeA.isEmpty || routeB.isEmpty) {
      return const SimilarityResult(score: 0.0, isDuplicate: false);
    }
    final cellsA = _routeToCells(routeA);
    final cellsB = _routeToCells(routeB);

    final intersection = cellsA.intersection(cellsB).length;
    final union = cellsA.union(cellsB).length;
    final score = union == 0 ? 0.0 : intersection / union;

    return SimilarityResult(score: score, isDuplicate: score >= 0.70);
  }

  static Set<String> _routeToCells(List<GpsPoint> points) {
    final cells = <String>{};
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final dist = math.sqrt(
          math.pow(p2.lat - p1.lat, 2) + math.pow(p2.lng - p1.lng, 2));
      final steps = (dist / _interpStep).ceil().clamp(1, 9999);
      for (int s = 0; s <= steps; s++) {
        final t = s / steps;
        final lat = p1.lat + (p2.lat - p1.lat) * t;
        final lng = p1.lng + (p2.lng - p1.lng) * t;
        final key =
            '${(lat / _gridSize).floor()}_${(lng / _gridSize).floor()}';
        cells.add(key);
      }
    }
    return cells;
  }

  // ── 와인딩 필터 ───────────────────────────────────────────

  static WindingScore calcWindingScore(List<GpsPoint> route) {
    if (route.length < 3) {
      return const WindingScore(score: 0.0, roadType: 'national');
    }

    double totalAngle = 0;
    double totalDistM = 0;

    for (int i = 1; i < route.length - 1; i++) {
      totalAngle += _bearingChange(route[i - 1], route[i], route[i + 1]);
      totalDistM += _haversineM(route[i - 1], route[i]);
    }

    if (totalDistM < 1.0) {
      return const WindingScore(score: 0.0, roadType: 'national');
    }

    final scoreRaw = (totalAngle / (totalDistM / 1000.0)).clamp(0.0, 200.0);
    final score = (scoreRaw / 200.0 * 100.0).clamp(0.0, 100.0);

    final roadType =
        score < 20 ? 'national' : score < 50 ? 'provincial' : 'country';

    return WindingScore(score: score, roadType: roadType);
  }

  static double _bearingChange(GpsPoint p0, GpsPoint p1, GpsPoint p2) {
    final b1 = _bearing(p0, p1);
    final b2 = _bearing(p1, p2);
    double delta = (b2 - b1).abs();
    if (delta > 180) delta = 360 - delta;
    return delta;
  }

  static double _bearing(GpsPoint a, GpsPoint b) {
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dlon = (b.lng - a.lng) * math.pi / 180;
    final x = math.sin(dlon) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dlon);
    return math.atan2(x, y) * 180 / math.pi;
  }

  static double _haversineM(GpsPoint a, GpsPoint b) {
    const R = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lng - a.lng) * math.pi / 180;
    final sinHalfLat = math.sin(dLat / 2);
    final sinHalfLon = math.sin(dLon / 2);
    final h = sinHalfLat * sinHalfLat +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            sinHalfLon *
            sinHalfLon;
    return 2 * R * math.asin(math.sqrt(h));
  }

  // ── Rust HTTP 엔진 연결 (port 8003) ──────────────────────────────
  static const _rustBase = 'http://localhost:8003';

  /// 경로 계산 — Rust HTTP 서버 우선, 실패 시 Dart fallback.
  ///
  /// routeType: 0=country(시골길), 1=provincial(지방도로), 2=national(국도)
  static Future<List<LatLng>> calcRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
    int routeType = 2,
  }) async {
    try {
      final body = jsonEncode({
        'origin': {'lat': origin.latitude, 'lng': origin.longitude},
        'destination': {
          'lat': destination.latitude,
          'lng': destination.longitude
        },
        'waypoints': waypoints
            .map((w) => {'lat': w.latitude, 'lng': w.longitude})
            .toList(),
        'route_type': routeType,
      });
      final resp = await http
          .post(
            Uri.parse('$_rustBase/calc_route'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final pts = (data['points'] as List).cast<Map<String, dynamic>>();
        dev.log(
          '[YuruNavi/Dart] calcRoute: Rust 응답 ${pts.length}pts '
          'dist=${(data['total_distance_m'] as num).toStringAsFixed(0)}m '
          'winding=${(data['winding_score'] as num).toStringAsFixed(1)} '
          'type=${data['road_type']}',
          name: 'NativeEngine',
        );
        return pts
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();
      }
    } catch (e) {
      dev.log(
        '[YuruNavi/Dart] calcRoute: Rust 서버 실패 ($e) → Dart fallback',
        name: 'NativeEngine',
        level: 900,
      );
    }
    return calcDummyRoute(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
      routeType: routeType,
    );
  }

  // ── 경로 생성 ─────────────────────────────────────────────────
  //
  // ROOT CAUSE (2026-05-25): The Rust engine is NOT wired up yet.
  //   - native/src/api.rs now has #[flutter_rust_bridge::frb] annotations.
  //   - Run `flutter_rust_bridge_codegen generate` from the project root to
  //     generate lib/src/rust/frb_generated.dart bindings.
  //   - Replace the body of this function with:
  //       final pts = await api.calcRoute(
  //         origin: GpsPoint(lat: origin.latitude, lng: origin.longitude),
  //         destination: GpsPoint(lat: destination.latitude, lng: destination.longitude),
  //         waypoints: waypoints.map((w) => GpsPoint(lat: w.latitude, lng: w.longitude)).toList(),
  //         routeType: routeType,
  //       );
  //       return pts.points.map((p) => LatLng(p.lat, p.lng)).toList();
  //
  // Until codegen runs this function uses a pure-Dart fallback that mirrors
  // the Rust algorithm so UI development can continue.
  //
  // routeType: 0=country(시골길), 1=provincial(지방도로), 2=national(국도)
  static Future<List<LatLng>> calcDummyRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
    int routeType = 2,
  }) async {
    // ── Dart-side coordinate transfer log ────────────────────────
    // These logs mirror what will be sent over FFI when the Rust bridge
    // is live. Compare against [YuruNavi/Rust] eprintln! output.
    dev.log(
      '[YuruNavi/Dart] calcDummyRoute: '
      'origin=(${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)}) '
      'dest=(${destination.latitude.toStringAsFixed(6)},${destination.longitude.toStringAsFixed(6)}) '
      'waypoints=${waypoints.length} '
      'routeType=$routeType',
      name: 'NativeEngine',
    );
    for (int i = 0; i < waypoints.length; i++) {
      dev.log(
        '[YuruNavi/Dart]   waypoint[$i]=(${waypoints[i].latitude.toStringAsFixed(6)},${waypoints[i].longitude.toStringAsFixed(6)})',
        name: 'NativeEngine',
      );
    }

    // ── Coordinate sanity check ───────────────────────────────────
    // Mirrors the Rust-side validation in calc_route().
    bool validCoord(LatLng p) =>
        p.latitude >= -90 && p.latitude <= 90 &&
        p.longitude >= -180 && p.longitude <= 180;
    if (!validCoord(origin) || !validCoord(destination)) {
      dev.log(
        '[YuruNavi/Dart] ERROR: invalid coordinates — returning empty route',
        name: 'NativeEngine',
        level: 900, // warning level
      );
      return [origin];
    }
    // 경로 타입별 파라미터 (amplitude=곡률, steps=포인트 수)
    const params = [
      (amplitude: 0.018, steps: 28), // 시골길
      (amplitude: 0.010, steps: 22), // 지방도로
      (amplitude: 0.004, steps: 16), // 국도
    ];
    final p = params[routeType.clamp(0, 2)];

    // 경유지 포함 전체 구간을 분할해서 각 구간별로 곡선 생성
    final allPoints = [origin, ...waypoints, destination];
    final result = <LatLng>[];
    final rng = math.Random(42);

    for (int seg = 0; seg < allPoints.length - 1; seg++) {
      final from = allPoints[seg];
      final to = allPoints[seg + 1];

      final dLat = to.latitude - from.latitude;
      final dLng = to.longitude - from.longitude;

      // 법선 방향 (경로 수직)
      final len = math.sqrt(dLat * dLat + dLng * dLng);
      final nx = len > 0 ? -dLng / len : 0.0;
      final ny = len > 0 ? dLat / len : 0.0;

      // 랜덤 위상 오프셋으로 자연스러운 형태 부여
      final phaseOffset = rng.nextDouble() * math.pi;
      final waveCount = routeType == 0 ? 3.0 : routeType == 1 ? 2.0 : 1.0;

      for (int i = 0; i <= p.steps; i++) {
        final t = i / p.steps;
        final wave = math.sin(t * math.pi * waveCount + phaseOffset);
        final lat = from.latitude + dLat * t + ny * wave * p.amplitude;
        final lng = from.longitude + dLng * t + nx * wave * p.amplitude;
        if (i > 0 || seg == 0) result.add(LatLng(lat, lng));
      }
    }

    dev.log(
      '[YuruNavi/Dart] calcDummyRoute done: ${result.length} points generated',
      name: 'NativeEngine',
    );

    // Simulates the async latency of a real FFI call (remove after bridge live)
    await Future.delayed(const Duration(milliseconds: 300));
    return result;
  }

  // ── 엣지 케이스 가드 (Dart fallback) ────────────────────────────────────
  // Each method mirrors the corresponding Rust function in native/src/api.rs.
  // Replace with api.xxx() FFI calls after running flutter_rust_bridge_codegen.

  /// GPS 측위 품질 검사.
  /// [accuracyM]: 수평 정확도 (미터). [ageMs]: 마지막 GPS 업데이트 경과 시간 (ms).
  static GpsQuality checkGpsAccuracy({
    required double accuracyM,
    required int ageMs,
  }) {
    if (accuracyM < 0) {
      dev.log('[YuruNavi/Dart] checkGpsAccuracy: negative accuracy → Poor',
          name: 'NativeEngine', level: 900);
      return GpsQuality.poor;
    }
    final ageS = ageMs ~/ 1000;
    if (accuracyM <= 20 && ageS < 3) return GpsQuality.good;
    if (accuracyM <= 50 && ageS < 8) return GpsQuality.degraded;
    dev.log(
      '[YuruNavi/Dart] checkGpsAccuracy: ${accuracyM.toStringAsFixed(1)}m ${ageS}s → poor',
      name: 'NativeEngine',
    );
    return GpsQuality.poor;
  }

  /// 현재 위치가 경로로부터 [thresholdM] 미터 이상 이탈했는지 검사.
  static OffRouteStatus isOffRoute({
    required LatLng current,
    required List<LatLng> route,
    double thresholdM = 150.0,
  }) {
    final threshold = thresholdM <= 0 ? 150.0 : thresholdM;

    if (route.length < 2) {
      dev.log('[YuruNavi/Dart] isOffRoute: route < 2 points',
          name: 'NativeEngine', level: 900);
      return OffRouteStatus(
        isOffRoute: true,
        closestPointDistanceM: double.maxFinite,
        thresholdM: threshold,
      );
    }

    if (!_validCoord(current)) {
      return OffRouteStatus(
        isOffRoute: false,
        closestPointDistanceM: 0,
        thresholdM: threshold,
      );
    }

    double minDist = double.maxFinite;
    for (int i = 0; i < route.length - 1; i++) {
      final d = _pointToSegmentM(current, route[i], route[i + 1]);
      if (d < minDist) minDist = d;
    }

    final off = minDist > threshold;
    if (off) {
      dev.log(
        '[YuruNavi/Dart] isOffRoute: TRIGGERED — ${minDist.toStringAsFixed(0)}m from route',
        name: 'NativeEngine',
        level: 900,
      );
    }
    return OffRouteStatus(
      isOffRoute: off,
      closestPointDistanceM: minDist,
      thresholdM: threshold,
    );
  }

  /// 목적지 도달 가능성 검사.
  static ReachabilityResult checkDestinationReachable({
    required LatLng origin,
    required LatLng destination,
  }) {
    if (!_validCoord(origin) || !_validCoord(destination)) {
      return const ReachabilityResult(
          isReachable: false, reason: 'invalid_coordinates');
    }
    final distM = _haversineM(
      GpsPoint(origin.latitude, origin.longitude),
      GpsPoint(destination.latitude, destination.longitude),
    );
    if (distM < 10) {
      dev.log('[YuruNavi/Dart] checkDestinationReachable: same_location',
          name: 'NativeEngine', level: 900);
      return const ReachabilityResult(
          isReachable: false, reason: 'same_location');
    }
    if (distM > 1500000) {
      dev.log(
        '[YuruNavi/Dart] checkDestinationReachable: too_far (${(distM / 1000).toStringAsFixed(0)}km)',
        name: 'NativeEngine',
        level: 900,
      );
      return const ReachabilityResult(isReachable: false, reason: 'too_far');
    }
    return const ReachabilityResult(isReachable: true, reason: '');
  }

  // ── Internal coordinate helpers ──────────────────────────────

  static bool _validCoord(LatLng p) =>
      p.latitude >= -90 &&
      p.latitude <= 90 &&
      p.longitude >= -180 &&
      p.longitude <= 180;

  /// Minimum distance from point [p] to segment [a]–[b] in metres.
  static double _pointToSegmentM(LatLng p, LatLng a, LatLng b) {
    final ax = b.latitude - a.latitude;
    final ay = b.longitude - a.longitude;
    final bx = p.latitude - a.latitude;
    final by = p.longitude - a.longitude;
    final lenSq = ax * ax + ay * ay;
    final t = lenSq < 1e-12
        ? 0.0
        : ((bx * ax + by * ay) / lenSq).clamp(0.0, 1.0);
    final closest = LatLng(a.latitude + t * ax, a.longitude + t * ay);
    return _haversineM(
      GpsPoint(p.latitude, p.longitude),
      GpsPoint(closest.latitude, closest.longitude),
    );
  }
}
