import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/core/config/app_config.dart';
import 'package:yurunavi/models/poi.dart';
import 'package:yurunavi/services/poi_service.dart';

Poi _poi(String id, PoiType type, double lat, double lon) {
  return Poi(id: id, name: id, type: type, location: LatLng(lat, lon));
}

Map<String, dynamic> _poiJson(String id, PoiType category, double lat, double lon) {
  const catStr = {
    PoiType.cafe: 'cafe',
    PoiType.convenienceStore: 'convenience_store',
    PoiType.gasStation: 'gas_station',
    PoiType.supermarket: 'supermarket',
    PoiType.restaurant: 'restaurant',
  };
  return {
    'id': id,
    'name': id,
    'category': catStr[category],
    'lat': lat,
    'lon': lon,
  };
}

void main() {
  // PoiService._poiBaseUrl은 AppConfig.instance를 읽으므로, 이 테스트 파일이
  // 독립된 isolate로 실행되더라도 late 필드가 초기화돼 있어야 한다.
  setUpAll(() {
    AppConfig.init(const ProdConfig());
  });

  group('PoiService.selectForAmbientDisplay', () {
    test('(a) 빈 후보 목록이면 빈 리스트를 반환한다', () {
      final result = PoiService.selectForAmbientDisplay(
        candidates: const [],
        south: 0,
        north: 1,
        west: 0,
        east: 1,
        center: const LatLng(0.5, 0.5),
      );
      expect(result, isEmpty);
    });

    test('(b) 결과는 maxCount를 절대 초과하지 않는다', () {
      final candidates = <Poi>[];
      final types = PoiType.values;
      for (var i = 0; i < 50; i++) {
        final lat = (i % 10) * 0.1;
        final lon = (i ~/ 10) * 0.1;
        candidates.add(_poi('p$i', types[i % types.length], lat, lon));
      }
      final result = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 0,
        north: 1,
        west: 0,
        east: 1,
        center: const LatLng(0.5, 0.5),
        maxCount: 20,
      );
      expect(result.length, lessThanOrEqualTo(20));
    });

    test('(c) 후보가 전부 한 grid cell에 몰려도 cell 내 우선순위가 지켜진다', () {
      // south=0,north=1,west=0,east=1, gridSize=4 → (0.1,0.1)은 전부 cell(0,0)에 들어간다.
      final candidates = [
        _poi('restaurant', PoiType.restaurant, 0.1, 0.1),
        _poi('supermarket', PoiType.supermarket, 0.1, 0.1),
        _poi('cafe', PoiType.cafe, 0.1, 0.1),
        _poi('convenienceStore', PoiType.convenienceStore, 0.1, 0.1),
        _poi('gasStation', PoiType.gasStation, 0.1, 0.1),
      ];
      final result = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 0,
        north: 1,
        west: 0,
        east: 1,
        center: const LatLng(0.1, 0.1),
        maxCount: 3,
      );
      expect(result.length, 3);
      expect(result.map((p) => p.type).toList(), [
        PoiType.gasStation,
        PoiType.convenienceStore,
        PoiType.cafe,
      ]);
    });

    test('(d) 서로 다른 cell에 퍼진 후보는 한 cell이 2개를 받기 전에 모든 cell이 1개씩 받는다 '
        '(라운드로빈 분산 검증)', () {
      // south=0,north=4,west=0,east=4, gridSize=4 → cell 한 칸=1도.
      // (0.1,0.1)->cell(0,0), (1.1,1.1)->cell(1,1), (2.1,2.1)->cell(2,2), 서로 다른 cell.
      final candidates = [
        _poi('a1', PoiType.restaurant, 0.1, 0.1),
        _poi('a2', PoiType.restaurant, 0.1, 0.1),
        _poi('b1', PoiType.restaurant, 1.1, 1.1),
        _poi('b2', PoiType.restaurant, 1.1, 1.1),
        _poi('c1', PoiType.restaurant, 2.1, 2.1),
        _poi('c2', PoiType.restaurant, 2.1, 2.1),
      ];
      final result = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 0,
        north: 4,
        west: 0,
        east: 4,
        center: const LatLng(0, 0),
        maxCount: 3,
      );
      expect(result.length, 3);
      // 각기 다른 cell(위/경도 그룹)에서 하나씩 뽑혔는지 확인 — 특정 cell에서 2개가
      // 뽑히고 다른 cell이 0개인 경우가 없어야 한다(라운드로빈 분산).
      final latGroups = result.map((p) => p.location.latitude.floor()).toSet();
      expect(latGroups.length, 3);
    });

    test('(e) 퇴화된 bounds(south==north)는 크래시 없이 우선순위+거리 정렬로 폴백한다', () {
      final center = const LatLng(0, 0);
      final candidates = [
        // 거리상 가장 가깝지만 우선순위는 낮음(카페) — 우선순위가 거리보다 우선해야 한다.
        _poi('cafe-near', PoiType.cafe, 0.001, 0.001),
        _poi('conv-mid', PoiType.convenienceStore, 0.01, 0.01),
        _poi('gas-far', PoiType.gasStation, 0.05, 0.05),
      ];
      final result = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 5.0,
        north: 5.0, // south == north → latSpan == 0 → degenerate
        west: 0,
        east: 1,
        center: center,
      );
      expect(result.length, 3);
      expect(result.map((p) => p.type).toList(), [
        PoiType.gasStation,
        PoiType.convenienceStore,
        PoiType.cafe,
      ]);
    });

    test(
        '(f) 동일 후보 집합이면 뷰포트가 살짝 이동(팬)해도 선택 결과가 바뀌지 않는다 '
        '(2026-07-15 밤 라이딩 회귀 가드 — "편의점이 사라지고 식당이 뜬다")', () {
      final candidates = <Poi>[];
      final types = PoiType.values;
      for (var i = 0; i < 40; i++) {
        final lat = 37.0 + (i % 8) * 0.01;
        final lon = 127.0 + (i ~/ 8) * 0.01;
        candidates.add(_poi('p$i', types[i % types.length], lat, lon));
      }
      final before = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 36.98,
        north: 37.10,
        west: 126.98,
        east: 127.10,
        center: const LatLng(37.04, 127.04),
        maxCount: 20,
      );
      // 뷰포트를 아주 조금 팬(같은 span, 원점만 이동) — 그리드가 뷰포트에
      // 상대적이면 셀 경계가 같이 밀려 선택된 POI 집합이 바뀐다.
      final after = PoiService.selectForAmbientDisplay(
        candidates: candidates,
        south: 36.981,
        north: 37.101,
        west: 126.983,
        east: 127.103,
        center: const LatLng(37.041, 127.043),
        maxCount: 20,
      );
      expect(
        before.map((p) => p.id).toSet(),
        after.map((p) => p.id).toSet(),
      );
    });
  });

  group('PoiRegionCache', () {
    test('정확히 같은 영역+타입으로 저장 후 조회하면 적중한다', () {
      final cache = PoiRegionCache();
      final pois = [
        _poi('a', PoiType.cafe, 0.5, 0.5),
        _poi('b', PoiType.gasStation, 0.6, 0.6),
      ];
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe, PoiType.gasStation},
        pois: pois,
      );

      final result = cache.tryGet(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe, PoiType.gasStation},
      );

      expect(result, isNotNull);
      expect(result!.map((p) => p.id).toSet(), {'a', 'b'});
    });

    test('저장된 더 넓은 영역이 더 좁은 요청 영역을 포함하면 적중하고, 결과는 요청 영역으로 '
        '필터링된다', () {
      final cache = PoiRegionCache();
      final pois = [
        _poi('inside', PoiType.cafe, 0.5, 0.5),
        _poi('outside', PoiType.cafe, 5.0, 5.0), // 요청 영역 밖
      ];
      cache.put(
        south: 0,
        west: 0,
        north: 10,
        east: 10,
        types: {PoiType.cafe},
        pois: pois,
      );

      final result = cache.tryGet(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
      );

      expect(result, isNotNull);
      expect(result!.map((p) => p.id).toList(), ['inside']);
    });

    test('저장된 타입 집합이 요청 타입의 상위집합이면 적중하고, 결과는 요청 타입으로 '
        '필터링된다', () {
      final cache = PoiRegionCache();
      final pois = [
        _poi('cafe1', PoiType.cafe, 0.5, 0.5),
        _poi('gas1', PoiType.gasStation, 0.5, 0.5),
      ];
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe, PoiType.gasStation, PoiType.restaurant},
        pois: pois,
      );

      final result = cache.tryGet(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
      );

      expect(result, isNotNull);
      expect(result!.map((p) => p.id).toList(), ['cafe1']);
    });

    test('저장된 영역이 요청 영역을 완전히 포함하지 못하면(더 작거나 겹치지 않으면) '
        '미스한다', () {
      final cache = PoiRegionCache();
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
        pois: [_poi('a', PoiType.cafe, 0.5, 0.5)],
      );

      // 요청 영역이 저장된 영역보다 넓다(포함 관계 역전) → 미스.
      final result = cache.tryGet(
        south: -1,
        west: -1,
        north: 2,
        east: 2,
        types: {PoiType.cafe},
      );

      expect(result, isNull);
    });

    test('TTL이 지난 항목은 미스로 취급한다', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final cache = PoiRegionCache(now: () => now);
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
        pois: [_poi('a', PoiType.cafe, 0.5, 0.5)],
      );

      // TTL(5분) 이내 — 적중.
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(
        cache.tryGet(south: 0, west: 0, north: 1, east: 1, types: {PoiType.cafe}),
        isNotNull,
      );

      // TTL 경과 — 미스.
      now = now.add(const Duration(seconds: 2));
      expect(
        cache.tryGet(south: 0, west: 0, north: 1, east: 1, types: {PoiType.cafe}),
        isNull,
      );
    });

    test(
        '서버 응답이 500건 이상(잘렸을 가능성)이면 캐싱하지 않는다 — '
        '완전하지 않은 결과를 "이 영역의 전체"로 오인해 재사용하면 가장자리 POI가 '
        '조용히 누락될 수 있기 때문(2026-07-15 감사에서 발견)', () {
      final cache = PoiRegionCache();
      final manyPois = List.generate(
        500,
        (i) => _poi('p$i', PoiType.cafe, 0.5, 0.5),
      );
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
        pois: manyPois,
      );

      // 저장 자체가 스킵됐어야 하므로, 완전히 같은 영역을 다시 조회해도 미스.
      final result = cache.tryGet(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
      );
      expect(result, isNull);
    });

    test('500건 미만 응답은 정상적으로 캐싱된다(회귀 가드)', () {
      final cache = PoiRegionCache();
      final fewPois = List.generate(
        499,
        (i) => _poi('p$i', PoiType.cafe, 0.5, 0.5),
      );
      cache.put(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
        pois: fewPois,
      );

      final result = cache.tryGet(
        south: 0,
        west: 0,
        north: 1,
        east: 1,
        types: {PoiType.cafe},
      );
      expect(result, isNotNull);
      expect(result!.length, 499);
    });
  });

  // S2(2026-08-05) — 429 서킷브레이커/백오프/예외 전달 회귀 가드.
  // 서킷브레이커 테스트는 네트워크 경로를 직접 검증하므로, 로컬 bulk 조회를
  // 건너뛰도록 localPoisLoader: () async => null 을 공통으로 주입한다.
  // (bulk 조회는 path_provider 바인딩이 필요해 순수 unit test에서 쓸 수 없음.)
  PoiService makeService({
    required http.Client Function() clientFactory,
    DateTime Function()? now,
  }) =>
      PoiService(
        clientFactory: clientFactory,
        now: now,
        localPoisLoader: () async => null,
      );

  group('PoiService — 서킷브레이커·예외 전달', () {
    test('1) 200 정상 응답 → POI가 파싱되고 서킷은 닫힌 채(정상) 유지된다', () async {
      var callCount = 0;
      final service = makeService(
        clientFactory: () => MockClient((request) async {
          callCount++;
          return http.Response(
            jsonEncode([_poiJson('a', PoiType.gasStation, 37.5, 127.0)]),
            200,
          );
        }),
      );

      final pois = await service.fetchPois(
        center: const LatLng(37.5, 127.0),
        radiusMeters: 500,
        types: [PoiType.gasStation],
      );
      expect(pois.length, 1);
      expect(pois.first.id, 'a');
      expect(callCount, 1);

      // 서킷이 닫혀 있으므로 바로 다음 호출도 정상적으로 네트워크에 닿는다.
      await service.fetchPois(
        center: const LatLng(37.5, 127.0),
        radiusMeters: 500,
        types: [PoiType.gasStation],
      );
      expect(callCount, 2);
    });

    test('2) 429 응답 → PoiFetchException(statusCode: 429)을 던진다(빈 리스트 아님)', () async {
      final service = makeService(
        clientFactory: () => MockClient((request) async => http.Response('', 429)),
      );

      await expectLater(
        () => service.fetchPois(
          center: const LatLng(0, 0),
          radiusMeters: 500,
          types: [PoiType.cafe],
        ),
        throwsA(isA<PoiFetchException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.circuitOpen, 'circuitOpen', false)),
      );
    });

    test(
        '3) 429 직후 재호출은 서킷이 열려 있어 MockClient에 닿지 않고(호출 카운터 불변) '
        'circuitOpen: true로 즉시 던진다', () async {
      var callCount = 0;
      final service = makeService(
        clientFactory: () => MockClient((request) async {
          callCount++;
          return http.Response('', 429);
        }),
      );

      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>()),
      );
      expect(callCount, 1);

      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>().having((e) => e.circuitOpen, 'circuitOpen', true)),
      );
      // 서킷이 막았으므로 두 번째 호출은 네트워크(MockClient handler)에 닿지 않는다.
      expect(callCount, 1);
    });

    test(
        '4) 백오프 경과 후 재호출은 요청이 나가고, 연속 실패마다 대기시간이 '
        '1→2→4→8→16→32→60(상한)초로 늘어난다', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      var callCount = 0;
      final service = makeService(
        now: () => now,
        clientFactory: () => MockClient((request) async {
          callCount++;
          return http.Response('', 429);
        }),
      );

      Future<void> attemptAndExpectFailure() => expectLater(
            () => service.fetchPois(
                center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
            throwsA(isA<PoiFetchException>()),
          );

      const expectedBackoffsSeconds = [1, 2, 4, 8, 16, 32, 60, 60];
      var expectedCallCount = 0;
      for (final backoff in expectedBackoffsSeconds) {
        // 경과 시간이 부족하면 서킷이 여전히 열려 있어(circuitOpen) 호출 카운터가
        // 늘지 않아야 한다.
        if (expectedCallCount > 0) {
          await expectLater(
            () => service.fetchPois(
                center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
            throwsA(isA<PoiFetchException>().having((e) => e.circuitOpen, 'circuitOpen', true)),
          );
          expect(callCount, expectedCallCount);
        }
        now = now.add(Duration(seconds: backoff));
        await attemptAndExpectFailure();
        expectedCallCount++;
        expect(callCount, expectedCallCount);
      }
    });

    test('5) 성공 응답은 서킷과 실패 카운터를 즉시 리셋한다', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      var callCount = 0;
      var respondWithFailure = true;
      final service = makeService(
        now: () => now,
        clientFactory: () => MockClient((request) async {
          callCount++;
          if (respondWithFailure) return http.Response('', 429);
          return http.Response(jsonEncode(const []), 200);
        }),
      );

      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>()),
      );
      expect(callCount, 1);

      now = now.add(const Duration(seconds: 1)); // 1초 백오프 경과 → half-open
      respondWithFailure = false;
      final pois = await service.fetchPois(
          center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]);
      expect(pois, isEmpty);
      expect(callCount, 2);

      // 리셋됐다면 대기 없이 바로 다음 호출도 네트워크에 닿아야 한다(circuitOpen이
      // 아니라 진짜 429가 다시 온 것이어야 한다) — 리셋 안 됐다면 오래된 백오프가
      // 아직 안 지나 circuitOpen:true로 막혔을 것이다.
      respondWithFailure = true;
      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>().having((e) => e.circuitOpen, 'circuitOpen', false)),
      );
      expect(callCount, 3);
    });

    test('6) Retry-After 헤더 값을 지수 백오프보다 우선해서 존중한다', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      var callCount = 0;
      final service = makeService(
        now: () => now,
        clientFactory: () => MockClient((request) async {
          callCount++;
          return http.Response('', 429, headers: {'retry-after': '30'});
        }),
      );

      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>()),
      );
      expect(callCount, 1);

      // 29초 후에도 여전히 막혀 있어야 한다 — 지수 백오프(1초)였다면 이미 열렸을 것.
      now = now.add(const Duration(seconds: 29));
      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>().having((e) => e.circuitOpen, 'circuitOpen', true)),
      );
      expect(callCount, 1);

      // 30초(Retry-After) 경과 후엔 다시 네트워크에 닿는다.
      now = now.add(const Duration(seconds: 1));
      await expectLater(
        () => service.fetchPois(
            center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]),
        throwsA(isA<PoiFetchException>()),
      );
      expect(callCount, 2);
    });

    test('9) 실패 시 PoiRegionCache.put이 호출되지 않는다(캐시 미오염)', () async {
      final cache = PoiRegionCache();
      final service = makeService(
        clientFactory: () => MockClient((request) async => http.Response('', 500)),
      );

      // 화면 코드(main_map_screen/nav_screen)와 동일한 패턴 — fetch 성공 시에만
      // put()을 호출하고, 실패(PoiFetchException)면 캐시를 건드리지 않는다.
      try {
        final fetched = await service.fetchPoisInBounds(
          south: 0,
          west: 0,
          north: 1,
          east: 1,
          types: [PoiType.cafe],
        );
        cache.put(
          south: 0,
          west: 0,
          north: 1,
          east: 1,
          types: {PoiType.cafe},
          pois: fetched,
        );
      } on PoiFetchException {
        // 조용히 무시 — 캐시는 건드리지 않는다.
      }

      final result = cache.tryGet(south: 0, west: 0, north: 1, east: 1, types: {PoiType.cafe});
      expect(result, isNull);
    });

    test(
        '10) 연속 실패 구간에서 실패 상세 로그는 1회만 나가고, 성공 후 다음 장애에서 다시 1회 나간다',
        () async {
      // S1에서 초당 2~3회의 로그 append가 발열·배터리의 직접 원인이었다.
      // 서킷 전이 로그뿐 아니라 실패 상세 로그도 연속 구간당 1회로 억제돼야 한다.
      var now = DateTime(2026, 8, 5, 12);
      var fail = true;
      final service = makeService(
        now: () => now,
        clientFactory: () => MockClient((request) async =>
            fail ? http.Response('', 429) : http.Response('[]', 200)),
      );

      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = original);

      Future<void> call() async {
        try {
          await service.fetchPois(
              center: const LatLng(0, 0), radiusMeters: 1, types: [PoiType.cafe]);
        } on PoiFetchException {
          // 기대된 실패.
        }
      }

      // 서킷 백오프를 매번 넘겨 실제 HTTP 시도가 반복되게 한다.
      for (var i = 0; i < 5; i++) {
        await call();
        now = now.add(const Duration(seconds: 120));
      }
      expect(lines.where((l) => l.startsWith('YNAV_POI fetch failed')).length, 1);

      // 성공하면 억제가 풀린다.
      fail = false;
      await call();
      fail = true;
      now = now.add(const Duration(seconds: 120));
      await call();
      expect(lines.where((l) => l.startsWith('YNAV_POI fetch failed')).length, 2);
    });
  });

  group('PoiService.snapBoundsOutward', () {
    test('7a) 인접한 두 중심점이 만드는 bbox가 동일한 스냅 bbox로 떨어진다', () {
      ({double south, double west, double north, double east}) bboxFor(LatLng c) {
        const delta = 0.02; // nav_screen 자동추종 모드 근사 정사각형과 동일 패턴.
        return (
          south: c.latitude - delta,
          west: c.longitude - delta,
          north: c.latitude + delta,
          east: c.longitude + delta,
        );
      }

      // "nice" 격자선에 정확히 걸치지 않는 중심점을 쓴다 — 격자선 바로 위/
      // 아래로 걸치는 두 점을 고르면 진짜로 서로 다른 셀에 속해(둘 다 outward
      // 스냅 계약을 올바르게 지킨 것) 셀이 달라지는 게 정상이므로, 그런
      // 경계 케이스는 "안정성" 검증에 적합하지 않다.
      final b1 = bboxFor(const LatLng(37.5050, 127.0050));
      // 약 11m 이동 — 스냅 전이었다면 PoiRegionCache가 매번 미스했을 정도의 미세한 이동.
      final b2 = bboxFor(const LatLng(37.5051, 127.0051));

      final snap1 = PoiService.snapBoundsOutward(
          south: b1.south, west: b1.west, north: b1.north, east: b1.east);
      final snap2 = PoiService.snapBoundsOutward(
          south: b2.south, west: b2.west, north: b2.north, east: b2.east);

      expect(snap1, snap2);
    });

    test('7b) 스냅 결과는 항상 원본 bbox를 포함한다', () {
      const cases = [
        (south: 37.501, west: 127.002, north: 37.541, east: 127.042),
        (south: -1.0, west: -1.0, north: 2.0, east: 2.0),
        (south: 0.1, west: 0.1, north: 0.1, east: 0.1), // 퇴화(점) 케이스
      ];
      for (final c in cases) {
        final snap = PoiService.snapBoundsOutward(
            south: c.south, west: c.west, north: c.north, east: c.east);
        expect(snap.south, lessThanOrEqualTo(c.south));
        expect(snap.west, lessThanOrEqualTo(c.west));
        expect(snap.north, greaterThanOrEqualTo(c.north));
        expect(snap.east, greaterThanOrEqualTo(c.east));
      }
    });
  });

  group('PoiFetchThrottle', () {
    test('8a) 15초 시간 경계 양옆에서 정확히 갈린다', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final throttle = PoiFetchThrottle(
        minInterval: const Duration(seconds: 15),
        minMoveMeters: 200,
        now: () => now,
      );
      const center = LatLng(37.5, 127.0);

      expect(throttle.shouldFetch(center: center), isTrue); // 최초 호출은 항상 허용
      throttle.markStarted(center: center);

      now = now.add(const Duration(seconds: 14, milliseconds: 999));
      expect(throttle.shouldFetch(center: center), isFalse); // 경계 직전 — 여전히 차단

      now = now.add(const Duration(milliseconds: 1));
      expect(throttle.shouldFetch(center: center), isTrue); // 정확히 15초 경과 — 허용
    });

    test('8b) 200m 이동 경계 양옆에서 정확히 갈린다', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final throttle = PoiFetchThrottle(
        minInterval: const Duration(seconds: 15),
        minMoveMeters: 200,
        now: () => now,
      );
      const center = LatLng(37.5, 127.0);
      throttle.markStarted(center: center);

      // 시간은 전혀 안 지났으므로(0초) 순수하게 거리만으로 판단된다.
      final near = LatLng(37.5 + 0.0005, 127.0); // 약 55m
      expect(throttle.shouldFetch(center: near), isFalse);

      final far = LatLng(37.5 + 0.002, 127.0); // 약 222m
      expect(throttle.shouldFetch(center: far), isTrue);
    });

    test('8c) markStarted 직후 같은 자리로의 즉시 재호출은 차단된다', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final throttle = PoiFetchThrottle(
        minInterval: const Duration(seconds: 15),
        minMoveMeters: 200,
        now: () => now,
      );
      const center = LatLng(37.5, 127.0);

      expect(throttle.shouldFetch(center: center), isTrue);
      throttle.markStarted(center: center);
      expect(throttle.shouldFetch(center: center), isFalse);
    });

    test(
        '8d) 타입 집합이 바뀌면 시간/거리 조건을 우회하되 typeChangeMinInterval 하한은 '
        '유지한다(§2-3 — 완전 무제한 우회 금지)', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final throttle = PoiFetchThrottle(
        minInterval: const Duration(seconds: 15),
        minMoveMeters: 200,
        typeChangeMinInterval: const Duration(seconds: 3),
        now: () => now,
      );
      const center = LatLng(37.5, 127.0);
      throttle.markStarted(center: center, types: {PoiType.gasStation});

      // 같은 자리·같은 타입 → 15초/200m 게이트에 걸려 차단.
      expect(throttle.shouldFetch(center: center, types: {PoiType.gasStation}), isFalse);

      // 타입이 바뀌었지만 3초가 안 지났으면 여전히 차단(무제한 우회 금지).
      expect(throttle.shouldFetch(center: center, types: {PoiType.cafe}), isFalse);

      now = now.add(const Duration(seconds: 3));
      // 3초(typeChangeMinInterval) 경과 후엔 타입 변경이 허용된다 — 15초
      // 전체를 기다리지 않아도 된다.
      expect(throttle.shouldFetch(center: center, types: {PoiType.cafe}), isTrue);
    });
  });

  group('PoiService.signedBearingDiff', () {
    // HANDOFF_0807_S6 — 검단 회전교차로 로컬 prod Valhalla 프로브 5건 실측값.
    // "판정" 열은 routing_service.dart RoutingService.classifyRoundaboutDirection의
    // ±45° 임계값 기대 버킷(별도 routing_service 테스트에서 재사용/검증).
    const probes = [
      (from: 56.2, to: 64.6, expected: 8.4, label: 'S→E'),
      (from: 56.2, to: 265.3, expected: -150.9, label: 'S→W'),
      (from: 171.7, to: 154.2, expected: -17.5, label: 'N→S'),
      (from: 254.4, to: 265.3, expected: 10.9, label: 'E→W'),
      (from: 56.2, to: 315.1, expected: -101.1, label: 'W→N'),
    ];

    for (final p in probes) {
      test('${p.label}: signedBearingDiff(${p.from}, ${p.to}) ≈ ${p.expected}', () {
        final diff = PoiService.signedBearingDiff(p.from, p.to);
        expect(diff, closeTo(p.expected, 0.05));
      });
    }

    test('0° 차이는 0을 반환한다', () {
      expect(PoiService.signedBearingDiff(90, 90), closeTo(0, 1e-9));
    });

    test('경계값 180°는 -180으로 떨어진다(공식의 wrap 경계 — -180~180 반개구간 상한)', () {
      // from=0, to=180 — 정확히 180 차이. 공식 ((to-from+540)%360)-180은
      // 정확히 ±180 지점에서 -180 쪽으로 떨어진다
      // (((180-0+540)%360)-180 = (720%360)-180 = 0-180 = -180).
      expect(PoiService.signedBearingDiff(0, 180), closeTo(-180, 1e-9));
    });

    test('wrap-around: from=350, to=10 (동쪽으로 20도, 0도선을 넘어감) → +20', () {
      expect(PoiService.signedBearingDiff(350, 10), closeTo(20, 1e-9));
    });

    test('wrap-around: from=10, to=350 (서쪽으로 20도, 0도선을 넘어감) → -20', () {
      expect(PoiService.signedBearingDiff(10, 350), closeTo(-20, 1e-9));
    });
  });
}
