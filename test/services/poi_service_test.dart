import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/models/poi.dart';
import 'package:yurunavi/services/poi_service.dart';

Poi _poi(String id, PoiType type, double lat, double lon) {
  return Poi(id: id, name: id, type: type, location: LatLng(lat, lon));
}

void main() {
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
  });
}
