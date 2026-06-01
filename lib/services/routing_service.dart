import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Valhalla 로컬 라우팅 클라이언트.
///
/// `alternates: 2`로 고속도로·자동차전용도로를 배제한 3개 대안 경로를 한 번에 받아
/// 거리 기준으로 정렬 후 시골길(긴 경로) / 지방도로(중간) / 국도(짧은 경로) 에 매핑한다.
/// Valhalla 미응답 시 빈 리스트 반환 — 호출자가 처리.
class RoutingService {
  static const _valhallaBase = 'http://localhost:8002';

  /// 3가지 코스 타입 경로를 반환한다 (idx 0=시골길, 1=지방도로, 2=국도).
  /// 고속도로·자동차전용도로는 모든 코스에서 배제된다.
  static Future<List<List<LatLng>>> fetchRoutes({
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
        return const [];
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // primary + alternates 수집
      final rawTrips = <Map<String, dynamic>>[];
      if (data['trip'] != null) rawTrips.add(data['trip'] as Map<String, dynamic>);
      for (final alt in (data['alternates'] as List? ?? [])) {
        final t = (alt as Map<String, dynamic>)['trip'];
        if (t != null) rawTrips.add(t as Map<String, dynamic>);
      }
      if (rawTrips.isEmpty) return const [];

      // 각 trip에서 폴리라인과 거리 추출
      final routes = <({List<LatLng> pts, double km})>[];
      for (final trip in rawTrips) {
        final legs = (trip['legs'] as List?) ?? [];
        if (legs.isEmpty) continue;
        final pts = _extractPoints(legs);
        final km = legs.fold<double>(
          0,
          (sum, leg) => sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
        );
        if (pts.isNotEmpty) routes.add((pts: pts, km: km));
      }
      if (routes.isEmpty) return const [];

      // 거리 내림차순 정렬 → 시골길(멀리/구불) … 국도(짧고 효율적)
      routes.sort((a, b) => b.km.compareTo(a.km));

      // 3개 미만이면 마지막 경로로 채움
      while (routes.length < 3) { routes.add(routes.last); }

      final courseNames = ['시골길', '지방도로', '국도'];
      for (int i = 0; i < 3; i++) {
        dev.log(
          'Valhalla [${courseNames[i]}] ${routes[i].pts.length}pts ${routes[i].km.toStringAsFixed(1)}km',
          name: 'RoutingService',
        );
      }

      return [routes[0].pts, routes[1].pts, routes[2].pts];
    } catch (e) {
      dev.log('Valhalla fetchRoutes 실패: $e', name: 'RoutingService', level: 900);
      return const [];
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
