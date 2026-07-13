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
}
