import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show debugPrint;
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

/// 고가도로/터널/지하차도 등 구조물 종류.
enum StructureType { bridge, tunnel, underpass }

/// 구조물 타입 → 한국어 안내 라벨. 카드 라벨(nav_screen)과 TTS(voice_engine)
/// 양쪽에서 공유해 중복 판정 로직을 피한다.
extension StructureTypeLabel on StructureType {
  String get labelKo => switch (this) {
        StructureType.bridge => '고가도로',
        StructureType.tunnel => '터널',
        StructureType.underpass => '지하차도',
      };
}

/// 경로 상의 다리/터널 구간 (전역 shape 인덱스 기준).
class StructureZone {
  final StructureType type;
  final int beginShapeIdx; // 전역 shape 인덱스, ManeuverStep.beginShapeIdx/endShapeIdx와 동일 좌표계
  final int endShapeIdx;   // 전역 shape 인덱스
  const StructureZone({
    required this.type,
    required this.beginShapeIdx,
    required this.endShapeIdx,
  });
}

/// 급커브 방향 (좌/우).
enum CurveDirection { left, right }

/// Valhalla maneuver가 커버하지 않는(교차로가 아닌) 급커브 구간
/// (전역 shape 인덱스 기준, ManeuverStep/StructureZone과 동일 좌표계).
class SharpCurveZone {
  final CurveDirection direction;
  final int beginShapeIdx; // 전역 shape 인덱스
  final int endShapeIdx;   // 전역 shape 인덱스
  const SharpCurveZone({
    required this.direction,
    required this.beginShapeIdx,
    required this.endShapeIdx,
  });
}

/// Valhalla 라우팅 결과 단위.
class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin; // round(distance / realistic_speed_kmh * 60)
  final double windingScore; // 0~100 from NativeEngine.calcWindingScore
  final List<ManeuverStep> maneuvers; // Valhalla 턴바이턴 단계
  /// 다리/터널 구간 (fetchRoutes()/_doFetch()는 채우지 않음 — 별도 호출자가 채운다).
  final List<StructureZone> structures;
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    this.windingScore = 0.0,
    this.maneuvers = const [],
    this.structures = const [],
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

  // 지방도 우회 과다 시 완화용 costing (시골길의 _ruralBalancedOpts와 동일한 패턴)
  static const Map<String, dynamic> _provincialBalancedOpts = {
    'use_highways': 0.0,
    'use_ferry': 0.0,
    'class_factors': {
      '0': 100,   // motorway: 고속도로 회피
      '1': 100,   // trunk: 자동차전용 회피
      '2': 1.0,   // primary: 국도 일부 허용 (지방도 2.0→폴백 1.0)
      '3': 0.6,   // secondary: 지방도 선호 유지(다소 완화)
      '4': 1.3,   // tertiary: 시군도 다소 회피
      '5': 1.8,   // unclassified
      '6': 2.2,   // residential
      '7': 3.0,   // service
    },
    'curvature_penalty': 0.3,
    'long_bridge_factor': 2.0,
    'long_tunnel_factor': 2.0,
  };

  static const double _provincialDetourThreshold = 1.3;

  // ── 제자리 루프(신갈JC형) 회피 ────────────────────────────────────────
  // RECON_songtan_paldang_uturn.md 참조: costing 튜닝으로는 없앨 수 없는 유형의
  // "제자리 루프"가 실측으로 확인됨(신갈JC 인근 인터체인지 연결로) — 경로가
  // [_loopMinPathM] 이상 진행한 뒤 [_loopProximityM] 이내로 되돌아오면, 루프
  // 중심 주변에 경유점을 뿌려 origin→경유점→destination으로 재요청한다. 대안이
  // 루프 중심을 [_loopClearanceM] 이상 벗어나고(=실제로 그 지점을 피함) 원본
  // 대비 [_loopAcceptRatio] 배 이내 거리면 교체하고, 그렇지 않으면(=진짜 산길
  // 스위치백 등 지형상 불가피) 원본을 그대로 둔다. "우회해도 더/비슷하게
  // 짧아지는가"만으로 판정하므로 헤어핀 각도 등 임의의 임계값이 필요 없다 —
  // 판교-무릉(강원도 산길 스위치백) 실측으로 오탐 없음을 확인함(§7 참조).
  static const double _loopProximityM = 1500;
  static const double _loopMinPathM = 5000;
  static const double _loopSearchWindowM = 30000;
  static const double _loopCoarseStepM = 200;
  // 2026-07-19 실측 튜닝: 3000m는 신갈JC 실제 사례(loopCenter 기준 clearance
  // 2464m)를 걸러내 버려 2000m로 낮춤 — loop/RECON_songtan_paldang_uturn.md §8
  // 검증표 참조.
  static const double _loopClearanceM = 2000;
  static const double _loopAcceptRatio = 1.02;
  static const List<double> _loopSweepRadiiKm = [6, 15];
  static const List<int> _loopSweepAnglesDeg = [
    0, 45, 90, 135, 180, 225, 270, 315,
  ];
  // 긴 경로(400km+)는 신갈형 병목이 두 곳 이상 연속될 수 있음(청파동-춘천
  // 실측: 1차 회피 후에도 다른 지점에 2번째 루프가 남아있었음) — 매 라운드
  // 루프가 없어질 때까지 반복하되 무한루프 방지로 상한을 둔다.
  static const int _loopEscapeMaxRounds = 3;

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
        'use_tracks': 0.15,
        'top_speed': 40,
        'class_factors': {
          '0': 100,   // motorway: 고속도로 회피
          '1': 100,   // trunk: 자동차전용 회피
          '2': 10,    // primary: 일반국도 회피
          '3': 4,     // secondary: 지방도 회피
          '4': 0.5,   // tertiary: 시군도 선호
          '5': 1.3,   // unclassified: 소로 약한 회피
          '6': 1.4,   // residential: 마을길 약한 회피
          '7': 1.6,   // service: 농로 약한 회피
        },
        'curvature_penalty': 3.0,
        'long_bridge_factor': 6.0,
        'long_tunnel_factor': 6.0,
        'span_min_length': 300,
        'uturn_penalty': 50,
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
          '3': 0.3,   // secondary: 지방도 선호
          '4': 1.1,   // tertiary: 시군도 약한 회피
          '5': 1.8,   // unclassified: 소로 약한 회피
          '6': 2.2,   // residential: 마을길 회피
          '7': 3.0,   // service: 농로 회피
        },
        'curvature_penalty': 0.5,
        'long_bridge_factor': 5.0,
        'long_tunnel_factor': 5.0,
        'span_min_length': 1000,
        'uturn_penalty': 70,
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
          '2': 0.3,   // primary: 일반국도 강한 선호
          '3': 1.2,   // secondary: 지방도 기준
          '4': 2.0,   // tertiary: 시군도 회피
          '5': 4.0,   // unclassified: 소로 강한 회피
          '6': 5.0,   // residential: 마을길 강한 회피
          '7': 8.0,   // service: 농로 강한 회피
        },
        'curvature_penalty': 0.0,
        'long_bridge_factor': 1.0,
        'long_tunnel_factor': 1.0,
        'uturn_penalty': 120,
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
    // 시골(0) 거리가 지방(1) 거리의 1.3배 이상이면 과다 우회로 보고
    // balanced costing 으로 시골 경로만 재요청해 교체한다.
    // 아래에서 실제로 results[0]/[1]을 교체했는지 추적 — 뒤이은 루프 회피
    // 단계가 재요청 시 어느 costing을 써야 하는지 판단하는 데 쓰인다.
    bool ruralReplacedByBalanced = false;
    bool provincialReplacedByBalanced = false;
    if (results.length == 3) {
      final ruralKm = results[0].distanceKm;
      final provKm = results[1].distanceKm;
      if (provKm > 0 && ruralKm / provKm >= _ruralDetourThreshold) {
        dev.log(
          '시골길 과다우회 감지 (rural=${ruralKm.toStringAsFixed(1)}km / '
          'prov=${provKm.toStringAsFixed(1)}km '
          '= ${(ruralKm / provKm).toStringAsFixed(2)}x ≥ $_ruralDetourThreshold) '
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
              ruralReplacedByBalanced = true;
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

      // ── 지방도로 1.3배 폴백 (시골길 폴백과 동일 패턴) ──────────────
      // 지방도(1) 거리가 국도(2) 거리의 1.3배 이상이면 과다 우회로 보고
      // balanced costing 으로 지방도 경로만 재요청해 교체한다.
      // results[1]은 위 시골길 폴백에서 건드리지 않으므로 순서 무관하게 안전.
      final provKm2 = results[1].distanceKm;
      final natlKm = results[2].distanceKm;
      if (natlKm > 0 && provKm2 / natlKm >= _provincialDetourThreshold) {
        dev.log(
          '지방도로 과다우회 감지 (prov=${provKm2.toStringAsFixed(1)}km / '
          'natl=${natlKm.toStringAsFixed(1)}km '
          '= ${(provKm2 / natlKm).toStringAsFixed(2)}x ≥ $_provincialDetourThreshold) '
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
                  'costing_options': {'motorcycle': _provincialBalancedOpts},
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
              // ETA 는 기존과 동일하게 _courseSpeeds[1] 로 재계산 (회귀 방지 핵심)
              final realisticMins = (km / _courseSpeeds[1] * 60).round();
              final maneuvers = _collectManeuvers(legs);
              if (maneuvers.isNotEmpty) {
                dev.log(
                  'shape_index check (balanced): lastEnd=${maneuvers.last.endShapeIdx} pts=${pts.length}',
                  name: 'RoutingService',
                );
              }
              results[1] = RouteResult(
                points: pts,
                distanceKm: km,
                durationMin: realisticMins,
                maneuvers: maneuvers,
              );
              provincialReplacedByBalanced = true;
              dev.log(
                'balanced 교체 완료: ${km.toStringAsFixed(1)}km '
                '${realisticMins}m',
                name: 'RoutingService',
              );
            }
          }
          // balanced 실패 시: 기존 지방도 경로 유지 (조용히 폴백, throw 금지)
        } catch (e) {
          dev.log('balanced 폴백 실패 → 기존 지방도 경로 유지: $e',
              name: 'RoutingService', level: 900);
        }
      }
    }

    // ── 제자리 루프 회피 (전 코스 공통, 위 폴백들 이후 최종 결과에 적용) ──
    // effectiveCostingOptions: 위 시골길/지방도로 balanced 폴백이 실제로
    // results[i]를 교체했다면 그 costing으로, 아니면 원래 costingOptions[i]로
    // 재요청해야 한다 — 그렇지 않으면 balanced로 이미 완화된 경로를 원래(더
    // 극단적인) costing으로 다시 요청해 완화 효과가 무효화된다.
    final effectiveCostingOptions = List<Map<String, dynamic>>.from(costingOptions);
    if (results.length == 3) {
      if (ruralReplacedByBalanced) {
        effectiveCostingOptions[0] = _ruralBalancedOpts;
      }
      if (provincialReplacedByBalanced) {
        effectiveCostingOptions[1] = _provincialBalancedOpts;
      }
    }

    final escaped = await Future.wait([
      for (int i = 0; i < results.length; i++)
        _escapeLoopIfPossible(
          results[i],
          effectiveCostingOptions[i],
          _courseSpeeds[i],
        ).catchError((Object e) {
          dev.log('루프 회피 로직 실패(무시, 원본 유지): $e',
              name: 'RoutingService', level: 900);
          return results[i];
        }),
    ]);

    return escaped;
  }

  /// [result]의 경로에서 "제자리 루프"(일정 거리 이상 진행한 뒤 근처로
  /// 되돌아오는 구간)를 감지해, 가능하면 그 지점을 피해가는 대안으로
  /// 교체한다. 400km+ 장거리 경로는 이런 병목이 두 곳 이상 있을 수 있어
  /// [_loopEscapeMaxRounds]까지 반복한다. 루프가 없거나, 있어도 대안이
  /// 원본보다 짧거나 비슷하지 않으면(=지형상 불가피) 그 시점 결과를 그대로
  /// 반환한다. 상세 설계·검증 데이터는 loop/RECON_songtan_paldang_uturn.md
  /// §6-8 참조.
  static Future<RouteResult> _escapeLoopIfPossible(
    RouteResult result,
    Map<String, dynamic> costingOpts,
    double courseSpeedKmh,
  ) async {
    var current = result;
    for (int round = 0; round < _loopEscapeMaxRounds; round++) {
      if (current.points.length < 2) return current;
      final loopCenter = findLoopCenter(current.points);
      if (loopCenter == null) return current;

      final origin = current.points.first;
      final destination = current.points.last;
      dev.log(
        '제자리 루프 감지(round $round): center='
        '${loopCenter.latitude.toStringAsFixed(4)},'
        '${loopCenter.longitude.toStringAsFixed(4)} → 경유점 탐색 시작',
        name: 'RoutingService',
      );

      RouteResult? best;
      double bestKm = double.infinity;

      for (final radiusKm in _loopSweepRadiiKm) {
        final candidates = await Future.wait([
          for (final angleDeg in _loopSweepAnglesDeg)
            _tryViaRoute(
              origin,
              destination,
              _bearingDistance.offset(loopCenter, radiusKm * 1000, angleDeg),
              costingOpts,
            ),
        ]);

        for (final candidate in candidates) {
          if (candidate == null) continue;
          final clearanceM = candidate.points
              .map((p) => _bearingDistance(p, loopCenter))
              .reduce((a, b) => a < b ? a : b);
          if (clearanceM < _loopClearanceM) continue; // 루프 지점을 여전히 지남
          if (candidate.distanceKm > current.distanceKm * _loopAcceptRatio) {
            continue; // 원본보다 유의미하게 더 돎
          }
          if (candidate.distanceKm < bestKm) {
            best = candidate;
            bestKm = candidate.distanceKm;
          }
        }
        if (best != null) break; // 더 작은 반경에서 찾았으면 더 큰 우회는 안 봄
      }

      if (best == null) {
        dev.log(
          '루프 회피 대안 없음(round $round) → 이 시점 결과 유지(지형상 불가피로 판단)',
          name: 'RoutingService',
        );
        return current;
      }

      final km = best.distanceKm;
      final realisticMins = (km / courseSpeedKmh * 60).round();
      dev.log(
        '루프 회피 성공(round $round): ${current.distanceKm.toStringAsFixed(1)}km → '
        '${km.toStringAsFixed(1)}km (경유점 재요청으로 교체)',
        name: 'RoutingService',
      );
      current = RouteResult(
        points: best.points,
        distanceKm: km,
        durationMin: realisticMins,
        maneuvers: best.maneuvers,
      );
    }
    return current;
  }

  /// origin→via→destination 2-leg 경로를 시도한다. 실패(네트워크 오류·논라우트)
  /// 시 null — 호출자가 조용히 다음 후보로 넘어간다. durationMin은 호출자가
  /// 코스별 실효속도로 재계산하므로 0으로 둔다.
  static Future<RouteResult?> _tryViaRoute(
    LatLng origin,
    LatLng destination,
    LatLng via,
    Map<String, dynamic> costingOpts,
  ) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_valhallaBase/route'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'locations': [
                {'lon': origin.longitude, 'lat': origin.latitude},
                {'lon': via.longitude, 'lat': via.latitude},
                {'lon': destination.longitude, 'lat': destination.latitude},
              ],
              'costing': 'motorcycle',
              'costing_options': {'motorcycle': costingOpts},
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final trip = data['trip'] as Map<String, dynamic>?;
      final legs = (trip?['legs'] as List?) ?? [];
      if (legs.isEmpty) return null;

      final pts = _extractPoints(legs);
      if (pts.isEmpty) return null;

      final km = legs.fold<double>(
        0,
        (sum, leg) =>
            sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble(),
      );
      final maneuvers = _collectManeuvers(legs);
      return RouteResult(
        points: pts,
        distanceKm: km,
        durationMin: 0,
        maneuvers: maneuvers,
      );
    } catch (e) {
      return null;
    }
  }

  /// 경로가 [_loopMinPathM] 이상의 도로를 지나온 뒤 [_loopProximityM] 이내로
  /// 되돌아오는 "제자리 루프" 구간이 있으면 그 지점을 반환한다(없으면 null).
  /// 순수 동기 geometry 계산 — 네트워크 호출 없음. 수백 km 경로에서도 빠르게
  /// 돌기 위해 원본 폴리라인을 [_loopCoarseStepM] 간격으로 성기게 리샘플링한
  /// 뒤 그 위에서만 스캔한다(정밀 보간 불필요 — 루프 유무 판정용 근사).
  static LatLng? findLoopCenter(List<LatLng> points) {
    final coarse = _resampleByDistance(points, _loopCoarseStepM);
    if (coarse.length < 2) return null;

    final n = coarse.length;
    final cumM = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      cumM[i] = cumM[i - 1] + _bearingDistance(coarse[i - 1], coarse[i]);
    }

    for (int i = 0; i < n; i++) {
      int j = i;
      while (j < n && cumM[j] - cumM[i] < _loopMinPathM) {
        j++;
      }
      while (j < n && cumM[j] - cumM[i] <= _loopSearchWindowM) {
        if (_bearingDistance(coarse[i], coarse[j]) <= _loopProximityM) {
          return coarse[i];
        }
        j++;
      }
    }
    return null;
  }

  /// [points]를 누적 거리 기준 [stepM] 간격으로 성기게 리샘플링한다(보간 없이
  /// 가장 가까운 원본 점만 선택 — [findLoopCenter]의 근사 스캔용).
  static List<LatLng> _resampleByDistance(List<LatLng> points, double stepM) {
    if (points.isEmpty) return const [];
    final out = <LatLng>[points.first];
    double acc = 0.0;
    double nextAt = stepM;
    for (int i = 0; i < points.length - 1; i++) {
      acc += _bearingDistance(points[i], points[i + 1]);
      if (acc >= nextAt) {
        out.add(points[i + 1]);
        nextAt += stepM;
      }
    }
    if (out.last != points.last) out.add(points.last);
    return out;
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
              .join(' '),
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

  /// trace_attributes 응답의 edges 배열에서 다리/터널 구간을 추출한다.
  ///
  /// bridge/tunnel을 각각 독립적으로 추적해 배열 순서상 연속된(run-adjacent)
  /// edge들을 하나의 구간으로 묶는다. 합산 길이가 [minLengthM] 미만인 구간은
  /// 버린다. 반환값은 beginShapeIdx 오름차순 정렬(타입 무관하게 shape 순서).
  ///
  /// [minLengthM] 기본값 근거(2026-07-17, RIDE_RESULTS_0716 "6-잔여" 수정):
  /// 원래 100m였으나, 실제 서비스 지역(고덕/송탄, `yurunavi-valhalla`)에서
  /// Valhalla `/locate`로 격자 샘플링한 실측 bridge/tunnel edge 49개 중
  /// 36개(73%)가 100m 미만이었고, 그중 "고덕좌교로"(51m)·"고덕국제2로"(71m)·
  /// "고덕갈평4로"(37m)처럼 **이름이 붙은, 실제로 라이더가 인지해야 할 도심
  /// 고가/지하차도**도 다수 포함돼 있었다(도심 고가/지하차도는 교차로 하나
  /// 분량인 경우가 흔하다는 RIDE_RESULTS_0716의 가설과 일치). 반면 30m 미만
  /// 구간(9~29m, 표본 21개)은 전부 이름 없는 edge — 배수로 박스컬버트·진입로
  /// 수준의 트리비얼한 구조물로 추정되어 여전히 걸러낸다. 안내 누락(안전
  /// 문제)과 트리비얼 구조물 오탐(UX 소음)의 절충점으로 30m을 택함 — 자세한
  /// 원본 표본은 세션 기록 참조(파일로 남기지 않음).
  static List<StructureZone> buildStructureZones(
    List<dynamic> edges, {
    double minLengthM = 30,
  }) {
    final zones = <StructureZone>[];

    void collect(StructureType type, bool Function(Map edge) isType) {
      int? runBegin;
      int runEnd = 0;
      double runLengthM = 0;

      void flush() {
        if (runBegin != null && runLengthM >= minLengthM) {
          zones.add(StructureZone(
            type: type,
            beginShapeIdx: runBegin!,
            endShapeIdx: runEnd,
          ));
        }
        runBegin = null;
        runLengthM = 0;
      }

      for (final e in edges) {
        final edge = e as Map;
        if (isType(edge)) {
          final b = (edge['begin_shape_index'] as num?)?.toInt() ?? 0;
          final end = (edge['end_shape_index'] as num?)?.toInt() ?? 0;
          final lenM = ((edge['length'] as num?)?.toDouble() ?? 0.0) * 1000;
          runBegin ??= b;
          runEnd = end;
          runLengthM += lenM;
        } else {
          flush();
        }
      }
      flush();
    }

    collect(StructureType.bridge, (e) => (e['bridge'] as bool?) ?? false);
    collect(StructureType.tunnel, (e) => (e['tunnel'] as bool?) ?? false);

    zones.sort((a, b) => a.beginShapeIdx.compareTo(b.beginShapeIdx));
    return zones;
  }

  /// exit(type 20/21) maneuver가 구조물 zone과 겹치거나, zone 종료 지점으로부터
  /// [bufferM] 이내에서 시작하면 그 구조물 타입을 반환한다. overlap이 항상 가장
  /// 강한 신호이므로 발견 즉시 반환하고, 그렇지 않으면 exit maneuver 시작
  /// 이전에 끝난 zone 중 가장 가까운 것을 buffer 이내에서 찾는다.
  ///
  /// 실측(2026-07-16 가상 GPS 테스트, 터널 코너)으로 검증된 값 — 실제 사례에서
  /// exit maneuver 자신의 shape 범위 안에 tunnel 태그 엣지가 포함돼 있었고,
  /// 다른 사례는 zone 종료 shape 인덱스가 exit maneuver 시작 3칸 전이었다.
  /// 300m면 이 두 경우를 다 잡으면서 이후의 무관한 회전까지 잘못 잡을 만큼
  /// 넓지는 않다.
  static StructureType? structureNearExit(
    ManeuverStep exitManeuver,
    List<StructureZone> zones,
    List<double> cumFromStartM, {
    double bufferM = 300,
  }) {
    if (cumFromStartM.isEmpty) return null;
    StructureType? best;
    double bestGapM = double.infinity;
    final exitBeginM = cumFromStartM[
        exitManeuver.beginShapeIdx.clamp(0, cumFromStartM.length - 1)];
    for (final z in zones) {
      final overlaps = z.beginShapeIdx <= exitManeuver.endShapeIdx &&
          exitManeuver.beginShapeIdx <= z.endShapeIdx;
      if (overlaps) return z.type; // overlap은 즉시 확정
      final zEndM =
          cumFromStartM[z.endShapeIdx.clamp(0, cumFromStartM.length - 1)];
      final gap = exitBeginM - zEndM;
      if (gap >= 0 && gap <= bufferM && gap < bestGapM) {
        bestGapM = gap;
        best = z.type;
      }
    }
    return best;
  }

  static const _bearingDistance = Distance();

  /// 경로 폴리라인 geometry만으로 급커브 구간을 감지한다.
  ///
  /// Valhalla maneuver 목록은 교차로에서만 turn을 발행하므로, 교차로가 아닌
  /// 곳에서 도로가 그대로 이어지며 크게 휘는 구간은 maneuver가 비어 있다.
  /// 순수 동기 geometry 계산이며 네트워크 호출이 없다 — [fetchStructureZones]와
  /// 달리 generation 가드 없이 호출자가 즉시 사용할 수 있다.
  ///
  /// 각 인덱스 i에서 앞으로 [windowM] 이내의 최원점 j를 찾아, 세그먼트
  /// (i, i+1)의 방위각과 세그먼트 (j-1, j)의 방위각 차이가 [thresholdDeg]
  /// 이상이면 그 인덱스를 커브 안으로 표시한다(감소하는 방위각 = 좌회전).
  /// 연속된 같은 방향 플래그를 buildStructureZones와 동일한 run-length
  /// 병합 방식으로 하나의 zone으로 합치고, Valhalla가 이미 회전(turn-family
  /// maneuver type)을 안내하는 구간과 shape 인덱스 범위가 겹치면 제외한다.
  /// "직진 유지" 등 필러 maneuver(경로 전체를 빈틈없이 분할함)는 억제 기준에서
  /// 제외한다 — 아래 turnManeuverTypes 참조.
  static List<SharpCurveZone> detectSharpCurves(
    List<LatLng> points,
    List<ManeuverStep> maneuvers, {
    double windowM = 100,
    double thresholdDeg = 45,
  }) {
    if (points.length < 3) return [];

    final n = points.length;
    final cumM = List<double>.filled(n, 0.0);
    final bearingDeg = List<double>.filled(n - 1, 0.0); // seg i: points[i]→points[i+1]
    double acc = 0.0;
    for (int i = 0; i < n - 1; i++) {
      acc += _bearingDistance(points[i], points[i + 1]);
      cumM[i + 1] = acc;
      bearingDeg[i] = (_bearingDistance.bearing(points[i], points[i + 1]) + 360) % 360;
    }

    // 인덱스 i가 커브 구간 안이면 방향, 아니면 null. 두 포인터로 O(n) 스캔
    // (cumM이 단조증가하므로 j는 i가 증가해도 뒤로 가지 않는다).
    final flagged = List<CurveDirection?>.filled(n - 1, null);
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (j < i + 1) j = i + 1;
      while (j < n - 1 && cumM[j + 1] - cumM[i] <= windowM) {
        j++;
      }
      final segStart = bearingDeg[i];
      final segEnd = bearingDeg[j - 1];
      double delta = segEnd - segStart;
      if (delta > 180) delta -= 360;
      if (delta <= -180) delta += 360;
      if (delta.abs() >= thresholdDeg) {
        flagged[i] = delta < 0 ? CurveDirection.left : CurveDirection.right;
      }
    }

    // buildStructureZones의 collect/flush run-length 병합과 동일한 방식.
    final zones = <SharpCurveZone>[];
    CurveDirection? runDir;
    int? runBegin;
    int runEnd = 0;

    void flush() {
      if (runBegin != null && runDir != null) {
        zones.add(SharpCurveZone(
          direction: runDir!,
          beginShapeIdx: runBegin!,
          endShapeIdx: runEnd,
        ));
      }
      runBegin = null;
      runDir = null;
    }

    for (int i = 0; i < n - 1; i++) {
      final dir = flagged[i];
      if (dir != null && dir == runDir) {
        runEnd = i;
      } else {
        flush();
        if (dir != null) {
          runDir = dir;
          runBegin = i;
          runEnd = i;
        }
      }
    }
    flush();

    // Valhalla maneuver 목록은 "직진 유지"류 필러(type 1=출발, 2류 "Drive
    // east..." 등)를 포함해 경로 전체를 빈틈없이 분할한다 — 실제 회전을
    // 안내하는 turn-family 타입만 억제 기준으로 써야 한다. 그렇지 않으면
    // 어떤 급커브든 그 구간을 덮는 필러 maneuver와 겹쳐 항상 억제되어버린다.
    // voice_engine.dart의 eventForType()에서 turn_left/turn_right/
    // sharp_turn_left/sharp_turn_right/uturn을 만드는 타입과 동일 — 그쪽이
    // 바뀌면 여기도 맞춰야 한다.
    const turnManeuverTypes = {9, 10, 11, 12, 13, 14, 15, 16};
    final turnManeuvers =
        maneuvers.where((m) => turnManeuverTypes.contains(m.type));

    // Valhalla가 이미 회전을 안내하는 구간과 겹치는 후보는 제외.
    final filtered = zones.where((z) {
      for (final m in turnManeuvers) {
        if (z.beginShapeIdx <= m.endShapeIdx && m.beginShapeIdx <= z.endShapeIdx) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) => a.beginShapeIdx.compareTo(b.beginShapeIdx));
    return filtered;
  }

  /// 경로 좌표 목록으로 Valhalla trace_attributes를 호출해 다리/터널 구간을
  /// 조회한다. 부가 기능이므로 어떤 실패에서도 예외를 던지지 않고 빈 리스트를
  /// 반환한다.
  static Future<List<StructureZone>> fetchStructureZones(
    List<LatLng> points,
  ) async {
    if (points.length < 2) return [];

    try {
      final encoded = _encodePolyline6(points);
      final resp = await http
          .post(
            Uri.parse('$_valhallaBase/trace_attributes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'encoded_polyline': encoded,
              // edge_walk는 shape가 그래프 엣지와 정확히 일치하지 않으면(교차로
              // 밀집 구간, 부동소수점 오차 등) 400으로 실패한다(2026-07-15 밤
              // 라이딩 로그에서 실측: "edge_walk algorithm failed to find exact
              // route match" — Valhalla가 직접 walk_or_snap 폴백을 권장함).
              // walk_or_snap은 가능하면 edge_walk를 쓰고 실패 시 map-matching으로
              // 자동 폴백해 항상 결과를 반환한다(CPU 비용은 더 들지만 이 호출은
              // 이미 20초 타임아웃 + 실패 시 빈 리스트로 안전하게 무시됨).
              'shape_match': 'walk_or_snap',
              'costing': 'motorcycle',
              'filters': {
                'attributes': [
                  'edge.begin_shape_index',
                  'edge.end_shape_index',
                  'edge.length',
                  'edge.bridge',
                  'edge.tunnel',
                ],
                'action': 'include',
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        dev.log(
          'trace_attributes ${resp.statusCode}: '
          '${resp.body.substring(0, resp.body.length.clamp(0, 200))}',
          name: 'RoutingService',
          level: 900,
        );
        debugPrint('YNAV_STRUCT_ERR status=${resp.statusCode}');
        return [];
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final edges = data['edges'] as List? ?? [];
      return buildStructureZones(edges);
    } catch (e) {
      dev.log('fetchStructureZones 실패: $e', name: 'RoutingService', level: 900);
      debugPrint('YNAV_STRUCT_ERR exception=$e');
      return [];
    }
  }

  /// 폴리라인 [points]의 [fromIdx] 지점부터, 인덱스가 증가하는 방향(=경로
  /// 진행 방향, 라이더가 실제로 이동할 방향)으로만 [stepM] 간격 좌표를
  /// [maxForwardM]까지 샘플링한다. fromIdx 자신(0m 지점)을 항상 포함.
  ///
  /// [fetchOffRouteStructureNear]를 "내 위치 중심 원형" 대신 "주행 경로를
  /// 따라 전방으로만" 조회하기 위한 헬퍼(2026-07-17 사용자 피드백 — 반경을
  /// 그냥 키우면 옆길/뒤쪽의 무관한 구조물까지 잘못 잡을 위험이 있다는 지적).
  /// 각 샘플 지점을 [fetchOffRouteStructureNear]의 기본 반경(150m)으로 조회하면
  /// 인접 샘플 간 원이 겹쳐 경로를 따라 빈틈없이 커버되면서도, 뒤쪽이나 경로에서
  /// 먼 옆쪽은 애초에 샘플 대상에 들지 않는다.
  static List<LatLng> forwardSamplePoints(
    List<LatLng> points,
    int fromIdx, {
    double maxForwardM = 500,
    double stepM = 150,
  }) {
    if (points.isEmpty || fromIdx < 0 || fromIdx >= points.length) {
      return const [];
    }
    final samples = <LatLng>[points[fromIdx]];
    double traveled = 0.0;
    double nextSampleAt = stepM;
    for (int i = fromIdx; i < points.length - 1 && traveled < maxForwardM; i++) {
      final a = points[i];
      final b = points[i + 1];
      final segLen = _bearingDistance(a, b);
      final segEndTraveled = traveled + segLen;
      while (nextSampleAt <= segEndTraveled && nextSampleAt <= maxForwardM) {
        final t = segLen > 0 ? (nextSampleAt - traveled) / segLen : 0.0;
        samples.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
        nextSampleAt += stepM;
      }
      traveled = segEndTraveled;
    }
    return samples;
  }

  /// 경로에는 없지만(우회 중인) 근처의 다리/터널을 감지한다. [fetchStructureZones]가
  /// trace_attributes로 "실제로 밟는 도로"만 보는 것과 달리, Valhalla /locate로
  /// [point] 반경 [radiusM] 내 모든 엣지를 조회해 "옆길로 우회 중인 구조물"을
  /// 잡는다 — 언더패스/고가도로 옆길 분기에서 차선변경 타이밍을 놓치지 않게
  /// 하는 안전 기능(§0 HANDOFF_0716 참조)이라 radiusM 기본값은 실측(99.3m)보다
  /// 여유 있게 150m로 잡는다. 호출자는 보통 [forwardSamplePoints]로 얻은 여러
  /// 지점에 대해 이 함수를 병렬 호출해 경로 전방을 커버한다. 부가 기능이므로
  /// 실패 시 예외 없이 null.
  static Future<StructureType?> fetchOffRouteStructureNear(
    LatLng point, {
    double radiusM = 150,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_valhallaBase/locate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'locations': [
                {
                  'lat': point.latitude,
                  'lon': point.longitude,
                  'radius': radiusM.round(),
                }
              ],
              'costing': 'motorcycle',
              'verbose': true,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        dev.log(
          'locate ${resp.statusCode}: '
          '${resp.body.substring(0, resp.body.length.clamp(0, 200))}',
          name: 'RoutingService',
          level: 900,
        );
        debugPrint('YNAV_OFFROUTE_ERR status=${resp.statusCode}');
        return null;
      }

      final data = jsonDecode(resp.body) as List;
      if (data.isEmpty) return null;
      final edges = (data.first as Map)['edges'] as List? ?? [];
      return classifyOffRouteEdges(edges);
    } catch (e) {
      dev.log('fetchOffRouteStructureNear 실패: $e',
          name: 'RoutingService', level: 900);
      debugPrint('YNAV_OFFROUTE_ERR exception=$e');
      return null;
    }
  }

  /// /locate 응답의 edges 배열(한 location 분)에서 가장 가까운 다리/터널
  /// 엣지를 골라 타입을 판정한다. bridge는 이름과 무관하게 항상 고가도로로
  /// 확정(모호함 없음). tunnel은 way 이름에 "지하차도"/"터널"이 있으면 그
  /// 라벨을 그대로 쓰고, 이름 정보가 없으면 터널로 통칭(폴백 — 실제 지하차도/
  /// 터널 사례를 더 모아 길이 기반 임계값을 정할 때까지는 이 단순 폴백을
  /// 유지한다, HANDOFF_0716 §3-4 참조).
  static StructureType? classifyOffRouteEdges(List<dynamic> edges) {
    StructureType? best;
    double bestDistM = double.infinity;
    for (final e in edges) {
      final edge = e as Map;
      final inner = edge['edge'] as Map? ?? const {};
      final isBridge = (inner['bridge'] as bool?) ?? false;
      final isTunnel = (inner['tunnel'] as bool?) ?? false;
      if (!isBridge && !isTunnel) continue;

      // distance 필드가 없는 경우는 실제 Valhalla 응답에선 안 나오는 방어적
      // 케이스라, 후보에서 밀리지 않도록 "가장 가깝다"(0.0)로 취급한다.
      final distM = (edge['distance'] as num?)?.toDouble() ?? 0.0;
      if (distM >= bestDistM) continue;

      StructureType type;
      if (isBridge) {
        type = StructureType.bridge;
      } else {
        final names = ((edge['edge_info'] as Map?)?['names'] as List? ?? [])
            .whereType<String>();
        if (names.any((n) => n.contains('지하차도'))) {
          type = StructureType.underpass;
        } else {
          type = StructureType.tunnel; // 이름 무관("터널" 포함이든 없든) 통칭 폴백
        }
      }
      bestDistM = distM;
      best = type;
    }
    return best;
  }

  /// 같은 exit maneuver에 대해 여러 지점(예: begin/endShapeIdx)에서 조회한
  /// [fetchOffRouteStructureNear] 결과를 하나로 합친다. 실측(2026-07-17 가상
  /// GPS)으로 확인된 이유: 구조물 way 이름("고덕지하차도")이 실제로는 exit
  /// maneuver의 시작점이 아니라 끝점(목적지 방향) 근처 엣지에 붙어있는
  /// 경우가 있어, 시작점만 조회하면 이름 없는 tunnel 플래그만 잡혀 "터널"로
  /// 과도하게 통칭된다. underpass(이름 매칭 성공)가 하나라도 있으면 그게
  /// 가장 구체적인 정보이므로 즉시 채택하고, 그 다음은 bridge(이름 무관
  /// 확정), tunnel(이름 없는 폴백)은 최후순위로 다른 결과가 있으면 대체된다.
  static StructureType? mergeOffRouteStructures(
      Iterable<StructureType?> results) {
    StructureType? best;
    for (final t in results) {
      if (t == null) continue;
      if (t == StructureType.underpass) return t;
      if (best == null || best == StructureType.tunnel) best = t;
    }
    return best;
  }

  /// Valhalla encoded polyline 인코더 (precision 6) — [_decodePolyline6]의 역연산.
  static String _encodePolyline6(List<LatLng> points) {
    final buffer = StringBuffer();
    int prevLat = 0;
    int prevLng = 0;

    void encodeValue(int value) {
      int v = value < 0 ? ~(value << 1) : (value << 1);
      while (v >= 0x20) {
        buffer.writeCharCode((0x20 | (v & 0x1f)) + 63);
        v >>= 5;
      }
      buffer.writeCharCode(v + 63);
    }

    for (final p in points) {
      final lat = (p.latitude * 1e6).round();
      final lng = (p.longitude * 1e6).round();
      encodeValue(lat - prevLat);
      encodeValue(lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
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
