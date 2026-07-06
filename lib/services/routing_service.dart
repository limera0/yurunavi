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
  final int beginShapeIdx;   // 전역 인덱스 (leg 오프셋 적용 후)
  final int endShapeIdx;     // 전역 인덱스
  /// Valhalla가 로터리 진입(type 26) maneuver에서 반환하는 출구 번호 (nth exit).
  /// 로터리 진입이 아닌 maneuver에서는 null.
  final int? roundaboutExitCount;
  /// Valhalla sign.exit_name_elements를 이어붙인 출구명 (예: "천호대교 북단").
  /// 없으면 null.
  final String? exitName;
  const ManeuverStep({
    required this.type,
    required this.instruction,
    required this.distanceKm,
    this.beginShapeIdx = 0,
    this.endShapeIdx = 0,
    this.roundaboutExitCount,
    this.exitName,
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

  // 시골길 우회 과다 시 완화용 costing (main.rs handle_calc_route 와 동일)
  static const Map<String, dynamic> _ruralBalancedOpts = {
    'use_highways': 0.0,
    'use_ferry': 0.0,
    'class_factors': {
      '0': 100,   // motorway: 고속도로 회피
      '1': 100,   // trunk: 자동차전용 회피
      '2': 3.0,   // primary: 국도 일부 허용 (시골길 6→폴백 3)
      '3': 1.0,   // secondary: 지방도 중립
      '4': 0.7,   // tertiary: 시군도 선호
      '5': 1.0,   // unclassified: 소로 중립
      '6': 1.2,   // residential: 마을길 약한 회피
      '7': 2.0,   // service: 농로 회피
    },
    'curvature_penalty': 1.2,
    'long_bridge_factor': 1.5,
  };

  static const double _ruralDetourThreshold = 1.5;

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
          '0': 100,   // motorway: 고속도로 회피
          '1': 100,   // trunk: 자동차전용 회피
          '2': 6,     // primary: 일반국도 회피
          '3': 2,     // secondary: 지방도 중간
          '4': 0.6,   // tertiary: 시군도 선호
          '5': 0.8,   // unclassified: 소로 선호
          '6': 0.9,   // residential: 마을길 선호
          '7': 1.0,   // service: 농로 기준
        },
        'curvature_penalty': 2.5,
        'long_bridge_factor': 3.0,
        'long_tunnel_factor': 3.0,
        'span_min_length': 500,
      },
      // 지방도로: 중간 설정, 주요 국도 의존 낮춤
      {
        'use_highways': 0.0,
        'use_ferry': 0.0,
        'use_living_streets': 0.5,
        'use_tracks': 0.2,
        'class_factors': {
          '0': 100,   // motorway: 고속도로 회피
          '1': 100,   // trunk: 자동차전용 회피
          '2': 2.0,   // primary: 일반국도 약한 회피
          '3': 0.5,   // secondary: 지방도 선호
          '4': 0.9,   // tertiary: 시군도 약한 선호
          '5': 1.5,   // unclassified: 소로 약한 회피
          '6': 2.0,   // residential: 마을길 회피
          '7': 3.0,   // service: 농로 회피
        },
        'curvature_penalty': 1.0,
        'long_bridge_factor': 1.5,
        'long_tunnel_factor': 1.5,
        'span_min_length': 500,
      },
      // 국도: 주요도로 선호, 생활도로·트랙·고속도로·유료도로 회피
      // 'shortest' 제거: motorcyclecost.cc EdgeCost()가 shortest_일 때
      // class_factors/use_highways/use_tolls/curvature/bridge/tunnel factor를
      // 전부 건너뛰고 순수 거리비용만 반환 — 이 코스가 자동차전용도로(trunk)를
      // 36% 섞어 쓰던 원인이었음 (loop/RECON_costing_national.md 참조).
      {
        'use_highways': 0.0,
        'use_ferry': 0.0,
        'use_living_streets': 0.0,
        'use_tracks': 0.0,
        'use_tolls': 0.0,
        'class_factors': {
          '0': 100,   // motorway: 고속도로 회피
          '1': 100,   // trunk: 자동차전용 회피
          '2': 0.5,   // primary: 일반국도 강한 선호
          '3': 1.2,   // secondary: 지방도 기준
          '4': 2.0,   // tertiary: 시군도 회피
          '5': 4.0,   // unclassified: 소로 강한 회피
          '6': 5.0,   // residential: 마을길 강한 회피
          '7': 8.0,   // service: 농로 강한 회피
        },
        'curvature_penalty': 0.0,
        'long_bridge_factor': 1.0,
        'long_tunnel_factor': 1.0,
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

      final maneuvers = _collectManeuvers(legs);
      if (maneuvers.isNotEmpty) {
        dev.log(
          'shape_index check: lastEnd=${maneuvers.last.endShapeIdx} pts=${pts.length}',
          name: 'RoutingService',
        );
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

    // ── 시골길 1.3배 폴백 (main.rs 와 동작 일치) ──────────────────
    // 시골(0) 시간이 지방(1) 시간의 1.3배 이상이면 과다 우회로 보고
    // balanced costing 으로 시골 경로만 재요청해 교체한다.
    if (results.length == 3) {
      final ruralMins = results[0].durationMin;
      final provMins = results[1].durationMin;
      if (provMins > 0 && ruralMins / provMins >= _ruralDetourThreshold) {
        dev.log(
          '시골길 과다우회 감지 (rural=${ruralMins}m / prov=${provMins}m '
          '= ${(ruralMins / provMins).toStringAsFixed(2)}x ≥ $_ruralDetourThreshold) '
          '→ balanced 재요청',
          name: 'RoutingService',
        );
        try {
          final resp = await http
              .post(
                Uri.parse('$_valhallaBase/route'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'locations': locations,
                  'costing': 'motorcycle',
                  'costing_options': {'motorcycle': _ruralBalancedOpts},
                }),
              )
              .timeout(const Duration(seconds: 20));

          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final trip = data['trip'] as Map<String, dynamic>?;
            final legs = (trip?['legs'] as List?) ?? [];
            final pts = _extractPoints(legs);
            if (pts.isNotEmpty) {
              final km = legs.fold<double>(
                0,
                (sum, leg) =>
                    sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
              );
              // ETA 는 기존과 동일하게 _courseSpeeds[0] 로 재계산 (회귀 방지 핵심)
              final realisticMins = (km / _courseSpeeds[0] * 60).round();
              final maneuvers = _collectManeuvers(legs);
              if (maneuvers.isNotEmpty) {
                dev.log(
                  'shape_index check (balanced): lastEnd=${maneuvers.last.endShapeIdx} pts=${pts.length}',
                  name: 'RoutingService',
                );
              }
              results[0] = RouteResult(
                points: pts,
                distanceKm: km,
                durationMin: realisticMins,
                maneuvers: maneuvers,
              );
              dev.log(
                'balanced 교체 완료: ${km.toStringAsFixed(1)}km '
                '${realisticMins}m',
                name: 'RoutingService',
              );
            }
          }
          // balanced 실패 시: 기존 시골 경로 유지 (조용히 폴백, throw 금지)
        } catch (e) {
          dev.log('balanced 폴백 실패 → 기존 시골 경로 유지: $e',
              name: 'RoutingService', level: 900);
        }
      }
    }

    return results;
  }

  /// leg별 maneuvers를 전역 shape 인덱스로 변환해 수집.
  /// Valhalla begin/end_shape_index는 leg 내부 기준 → leg 누적 오프셋을 더한다.
  /// 오프셋 누적은 _extractPoints의 skip(1) 병합과 정확히 대응(leg당 points-1).
  static List<ManeuverStep> _collectManeuvers(List legs) {
    final out = <ManeuverStep>[];
    int shapeOffset = 0;
    for (final leg in legs) {
      for (final m in (leg['maneuvers'] as List? ?? [])) {
        final b = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
        final e = (m['end_shape_index'] as num?)?.toInt() ?? 0;
        out.add(ManeuverStep(
          type: (m['type'] as num?)?.toInt() ?? 0,
          instruction: (m['instruction'] as String?) ?? '',
          distanceKm: (m['length'] as num?)?.toDouble() ?? 0.0,
          beginShapeIdx: shapeOffset + b,
          endShapeIdx: shapeOffset + e,
          roundaboutExitCount: (m['roundabout_exit_count'] as num?)?.toInt(),
          exitName: (m['sign']?['exit_name_elements'] as List?)
              ?.map((e) => (e as Map)['text'] as String? ?? '')
              .join(''),
        ));
      }
      final legPts = _decodePolyline6(leg['shape'] as String? ?? '');
      shapeOffset += legPts.isEmpty ? 0 : legPts.length - 1;
    }
    return out;
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
