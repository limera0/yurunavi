import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Routing error categories surfaced to the UI.
enum RoutingError {
  /// Network unreachable, DNS failure, connection refused, or timeout.
  serverDown,
  /// Server responded but could not find a valid route for this request.
  noRoute,
  /// Server responded with a non-200 HTTP status.
  serverError,
}

/// Thrown by [RoutingService.fetchRoutes] on failure (replaces empty-list return).
class RoutingException implements Exception {
  final RoutingError type;
  final String? detail;
  const RoutingException(this.type, {this.detail});

  @override
  String toString() =>
      'RoutingException(${type.name}${detail != null ? ': $detail' : ''})';
}

/// Valhalla maneuver 한 단계 (턴바이턴).
class ManeuverStep {
  /// Valhalla maneuver type integer (e.g. 10=우회전, 15=좌회전, 4=도착).
  final int type;
  /// Valhalla가 반환한 영문 instruction.
  final String instruction;
  /// 이 구간 거리 (km).
  final double distanceKm;
  const ManeuverStep({
    required this.type,
    required this.instruction,
    required this.distanceKm,
  });
}

/// Valhalla 라우팅 결과 단위.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin; // round(distance / realistic_speed_kmh * 60)
  final double windingScore; // 0~100 from NativeEngine.calcWindingScore
  final List<ManeuverStep> maneuvers; // Valhalla 턴바이턴 단계
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    this.windingScore = 0.0,
    this.maneuvers = const [],
  });
}

/// Valhalla 로컬 라우팅 클라이언트.
///
/// 코스 타입별로 Valhalla를 3회 병렬 호출하여 서로 다른 geometry를 유도한다.
/// 고속도로·자동차전용도로는 모든 코스에서 배제된다.
/// 실패 시 [RoutingException] throw — 호출자가 처리.
class RoutingService {
  static const _valhallaBase = 'https://valhalla.westinx.com';

  // 코스별 실효속도 (근거: 네이버 실측 71km=118min=36km/h, 지방도+국도 혼합)
  // Valhalla 응답 time은 ~57-88km/h 낙관치이므로 거리 기반으로 재계산
  static const _speedCountrysideKmh = 30.0; // 시골길: 좁고 굽은 길
  static const _speedLocalKmh = 36.0;       // 지방도로: 지방 국도 혼합
  static const _speedNationalKmh = 45.0;    // 국도: 간선도로 위주

  // 코스별 Valhalla costing_options (인덱스: 0=시골길, 1=지방도로, 2=국도)
  // use_highways: 0.0 전 코스 공통 (앱 존재 이유: 고속도로 배제)
  static const _courseNames = ['시골길', '지방도로', '국도'];
  static const _courseSpeeds = [
    _speedCountrysideKmh,
    _speedLocalKmh,
    _speedNationalKmh,
  ];

  // ── Route cache (TTL 5 min, max 20 entries) ──────────────────────────────
  static const _cacheTtl = Duration(minutes: 5);
  static const _cacheMaxSize = 20;
  static final Map<String, ({List<RouteResult> routes, DateTime at})> _cache = {};

  /// 원점이 크게 이동했거나 강제 새로고침이 필요할 때 캐시를 비운다.
  static void invalidateCache() => _cache.clear();

  static String _cacheKey(
      LatLng origin, LatLng destination, List<LatLng> waypoints) {
    String fmt(LatLng p) =>
        '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    final wStr = waypoints.map(fmt).join(';');
    return '${fmt(origin)}→${fmt(destination)}|$wStr';
  }

  /// 3가지 코스 타입 경로를 반환한다 (idx 0=시골길, 1=지방도로, 2=국도).
  /// 고속도로·자동차전용도로는 모든 코스에서 배제된다.
  /// 실패 시 [RoutingException] throw: serverDown(1회 자동 재시도), noRoute, serverError.
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

    final cacheKey = _cacheKey(origin, destination, waypoints);
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      dev.log(
        'RoutingService cache HIT (${_cache.length} entries)',
        name: 'RoutingService',
      );
      return cached.routes;
    }

    // 코스별 costing_options — 서로 다른 geometry를 유도
    final costingOptions = <Map<String, dynamic>>[
      // 시골길: 생활도로·비포장 선호, top_speed 제한 → 간선도로 자연 회피
      // use_ferry:0.0 — 한국 도선/나룻배는 오토바이 탑승 불가 경우 많음
      {
        'use_highways': 0.0,
        'use_ferry': 0.0,
        'use_living_streets': 1.0,
        'use_tracks': 0.8,
        'top_speed': 40,
        'class_factors': {
          '1': 100.0, // FC1: 고속국도 강한 회피
          '2': 5.0,   // FC2: 일반국도 회피
          '3': 2.5,   // FC3: 지방도 중간
          '4': 1.0,   // FC4: 군도 기준
          '5': 0.2,   // FC5: 생활도로 강한 선호
        },
        'urban_penalty': 50.0, // 도심 관통 방지
      },
      // 지방도로: 중간 설정, 주요 국도 의존 낮춤
      {
        'use_highways': 0.0,
        'use_ferry': 0.0,
        'use_living_streets': 0.5,
        'use_tracks': 0.2,
        'class_factors': {
          '1': 100.0, // FC1: 고속국도 강한 회피
          '2': 2.0,   // FC2: 일반국도 약한 회피
          '3': 0.5,   // FC3: 지방도 선호
          '4': 0.7,   // FC4: 군도 약한 선호
          '5': 1.5,   // FC5: 생활도로 약한 회피
        },
      },
      // 국도: 최단·주요도로 선호, 생활도로·트랙 회피
      {
        'use_highways': 0.0,
        'use_ferry': 0.0,
        'use_living_streets': 0.0,
        'use_tracks': 0.0,
        'shortest': true,
        'class_factors': {
          '1': 100.0, // FC1: 고속국도 강한 회피
          '2': 0.4,   // FC2: 일반국도 강한 선호
          '3': 1.0,   // FC3: 지방도 기준
          '4': 2.0,   // FC4: 군도 회피
          '5': 10.0,  // FC5: 생활도로 강한 회피
        },
      },
    ];

    // serverDown은 1회 자동 재시도 (noRoute·serverError는 재시도 없음)
    RoutingException? lastError;
    for (int attempt = 0; attempt <= 1; attempt++) {
      if (attempt > 0) {
        dev.log(
          'RoutingService retry (attempt $attempt)',
          name: 'RoutingService',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      try {
        final result = await _doFetch(locations, costingOptions);
        // cache store — evict oldest if full
        if (_cache.length >= _cacheMaxSize) {
          final oldest = _cache.entries
              .reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b);
          _cache.remove(oldest.key);
        }
        _cache[cacheKey] = (routes: result, at: DateTime.now());
        dev.log(
          'RoutingService cache STORE (${_cache.length}/$_cacheMaxSize entries)',
          name: 'RoutingService',
        );
        return result;
      } on RoutingException catch (e) {
        dev.log(
          'RoutingService error on attempt $attempt: $e',
          name: 'RoutingService',
          level: 900,
        );
        lastError = e;
        if (e.type != RoutingError.serverDown) break;
      }
    }
    throw lastError!;
  }

  /// 3개 코스 병렬 요청 실행. 실패 시 [RoutingException] throw.
  static Future<List<RouteResult>> _doFetch(
    List<Map<String, dynamic>> locations,
    List<Map<String, dynamic>> costingOptions,
  ) async {
    final futures = costingOptions.map(
      (opts) => http
          .post(
            Uri.parse('$_valhallaBase/route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'locations': locations,
              'costing': 'motorcycle',
              'costing_options': {'motorcycle': opts},
            }),
          )
          .timeout(const Duration(seconds: 20)),
    );

    final List<http.Response> responses;
    try {
      responses = await Future.wait(futures);
    } on TimeoutException catch (e) {
      dev.log('Valhalla timeout: $e', name: 'RoutingService', level: 900);
      throw const RoutingException(RoutingError.serverDown);
    } on SocketException catch (e) {
      dev.log('Valhalla socket error: $e', name: 'RoutingService', level: 900);
      throw const RoutingException(RoutingError.serverDown);
    } catch (e) {
      dev.log('Valhalla fetchRoutes 실패: $e', name: 'RoutingService', level: 900);
      throw RoutingException(RoutingError.serverDown, detail: e.toString());
    }

    final results = <RouteResult>[];
    for (int i = 0; i < 3; i++) {
      final resp = responses[i];
      if (resp.statusCode != 200) {
        dev.log(
          'Valhalla [${_courseNames[i]}] ${resp.statusCode}: '
          '${resp.body.substring(0, resp.body.length.clamp(0, 200))}',
          name: 'RoutingService',
          level: 900,
        );
        throw RoutingException(RoutingError.serverError,
            detail: 'HTTP ${resp.statusCode}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final trip = data['trip'] as Map<String, dynamic>?;
      if (trip == null) throw const RoutingException(RoutingError.noRoute);

      final legs = (trip['legs'] as List?) ?? [];
      if (legs.isEmpty) throw const RoutingException(RoutingError.noRoute);

      final pts = _extractPoints(legs);
      if (pts.isEmpty) throw const RoutingException(RoutingError.noRoute);

      final km = legs.fold<double>(
        0,
        (sum, leg) =>
            sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
      );
      final realisticMins = (km / _courseSpeeds[i] * 60).round();

      // maneuvers 수집 — 전 leg 이어붙임
      final maneuvers = <ManeuverStep>[];
      for (final leg in legs) {
        for (final m in (leg['maneuvers'] as List? ?? [])) {
          maneuvers.add(ManeuverStep(
            type: (m['type'] as num?)?.toInt() ?? 0,
            instruction: (m['instruction'] as String?) ?? '',
            distanceKm: (m['length'] as num?)?.toDouble() ?? 0.0,
          ));
        }
      }

      dev.log(
        'Valhalla [${_courseNames[i]}] ${pts.length}pts '
        '${km.toStringAsFixed(1)}km '
        'realisticMin=$realisticMins (${_courseSpeeds[i].toStringAsFixed(0)}km/h) '
        'maneuvers=${maneuvers.length}',
        name: 'RoutingService',
      );

      results.add(RouteResult(
        points: pts,
        distanceKm: km,
        durationMin: realisticMins,
        maneuvers: maneuvers,
      ));
    }
    return results;
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
