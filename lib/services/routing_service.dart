import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Valhalla 라우팅 결과 단위.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin; // round(total_seconds / 60)
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

/// Valhalla 로컬 라우팅 클라이언트.
///
/// 코스 타입별로 Valhalla를 3회 호출하여 서로 다른 경로를 유도한다.
/// 고속도로·자동차전용도로는 모든 코스에서 배제된다.
/// Valhalla 미응답 시 빈 리스트 반환 — 호출자가 처리.
class RoutingService {
  static const _valhallaBase = 'https://valhalla.westinx.com';

  // 코스별 실효속도 (근거: 네이버 실측 71km=118min=36km/h 기준 지방도+국도 혼합)
  // 시골길: 좁고 굽은 길, 지방도: 일반 지방도로, 국도: 간선도로
  static const _speedCountrysideKmh = 30.0; // 시골길
  static const _speedLocalKmh = 36.0;       // 지방도로
  static const _speedNationalKmh = 45.0;    // 국도

  /// 3가지 코스 타입 경로를 반환한다 (idx 0=시골길, 1=지방도로, 2=국도).
  /// 고속도로·자동차전용도로는 모든 코스에서 배제된다.
  static Future<List<RouteResult>> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const [],
  }) async {
    final locations = [
      {'lon': origin.longitude, 'lat': origin.latitude},
      for (final w in waypoints)
        {'lon': w.longitude, 'lat': w.latitude},
      {'lon': destination.longitude, 'lat': destination.latitude},
    ];

    try {
      final body = jsonEncode({
        'locations': locations,
        'costing': 'motorcycle',
        'costing_options': {
          'motorcycle': {
            'use_highways': 0.0,  // 고속도로·자동차전용도로 배제
          },
        },
        'alternates': 2,  // 기본 + 대안 2개 = 총 3개 경로
      });

      final resp = await http
          .post(
            Uri.parse('$_valhallaBase/route'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        dev.log(
          'Valhalla ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}',
          name: 'RoutingService',
          level: 900,
        );
        return const <RouteResult>[];
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // primary + alternates 수집
      final rawTrips = <Map<String, dynamic>>[];
      if (data['trip'] != null) rawTrips.add(data['trip'] as Map<String, dynamic>);
      for (final alt in (data['alternates'] as List? ?? [])) {
        final t = (alt as Map<String, dynamic>)['trip'];
        if (t != null) rawTrips.add(t as Map<String, dynamic>);
      }
      if (rawTrips.isEmpty) return const <RouteResult>[];

      // 각 trip에서 폴리라인, 거리, 시간 추출
      final routes = <({List<LatLng> pts, double km, int mins})>[];
      for (final trip in rawTrips) {
        final legs = (trip['legs'] as List?) ?? [];
        if (legs.isEmpty) continue;
        final pts = _extractPoints(legs);
        final km = legs.fold<double>(
          0,
          (sum, leg) => sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
        );
        final secs = legs.fold<double>(
          0,
          (sum, leg) => sum + ((leg['summary']?['time'] as num?)?.toDouble() ?? 0),
        );
        final mins = (secs / 60).round();
        if (pts.isNotEmpty) routes.add((pts: pts, km: km, mins: mins));
      }
      if (routes.isEmpty) return const <RouteResult>[];

      // 거리 내림차순 정렬 → 시골길(멀리/구불) … 국도(짧고 효율적)
      routes.sort((a, b) => b.km.compareTo(a.km));

      // 3개 미만이면 마지막 경로로 채움
      while (routes.length < 3) { routes.add(routes.last); }

      // 코스별 실효속도로 ETA 재계산 (Valhalla 낙관적 속도 대신)
      const speeds = [
        _speedCountrysideKmh,
        _speedLocalKmh,
        _speedNationalKmh,
      ];
      final courseNames = ['시골길', '지방도로', '국도'];
      final results = <RouteResult>[];
      for (int i = 0; i < 3; i++) {
        final realisticMins = (routes[i].km / speeds[i] * 60).round();
        dev.log(
          'Valhalla [${courseNames[i]}] ${routes[i].pts.length}pts '
          '${routes[i].km.toStringAsFixed(1)}km '
          'valhallaMin=${routes[i].mins} realisticMin=$realisticMins '
          '(${speeds[i].toStringAsFixed(0)}km/h)',
          name: 'RoutingService',
        );
        results.add(RouteResult(
          points: routes[i].pts,
          distanceKm: routes[i].km,
          durationMin: realisticMins,
        ));
      }
      return results;
    } catch (e) {
      dev.log('Valhalla fetchRoutes 실패: $e', name: 'RoutingService', level: 900);
      return const <RouteResult>[];
    }
  }

  static List<LatLng> _extractPoints(List legs) {
    final points = <LatLng>[];
    for (final leg in legs) {
      final shape = leg['shape'] as String? ?? '';
      final decoded = _decodePolyline6(shape);
      if (points.isNotEmpty && decoded.isNotEmpty) {
        points.addAll(decoded.skip(1));
      } else {
        points.addAll(decoded);
      }
    }
    return points;
  }

  /// Valhalla encoded polyline 디코더 (precision 6).
  ///
  /// Valhalla는 Google의 encoded polyline 알고리즘을 precision=6으로 사용.
  /// 표준 precision=5(Google Maps)와 달리 1e6으로 나눔.
  static List<LatLng> _decodePolyline6(String encoded) {
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result2 & 1) != 0 ? ~(result2 >> 1) : (result2 >> 1);
      lat += dLat;

      shift = 0;
      result2 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result2 |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result2 & 1) != 0 ? ~(result2 >> 1) : (result2 >> 1);
      lng += dLng;

      result.add(LatLng(lat / 1e6, lng / 1e6));
    }
    return result;
  }
}
