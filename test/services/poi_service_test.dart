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

  group('PoiService.looksMisclassified', () {
    test('(a) 카페 소분류에 섞인 식당류 업소명은 오분류로 판정한다', () {
      expect(PoiService.looksMisclassified('할매국물닭발', PoiType.cafe), isTrue);
      expect(PoiService.looksMisclassified('영동곱창', PoiType.cafe), isTrue);
      expect(PoiService.looksMisclassified('원조순대국밥', PoiType.cafe), isTrue);
    });

    test('(b) 정상적인 카페 업소명은 오분류로 판정하지 않는다', () {
      expect(PoiService.looksMisclassified('스타벅스 강남점', PoiType.cafe), isFalse);
      expect(PoiService.looksMisclassified('동네카페', PoiType.cafe), isFalse);
    });

    test('(c) 식당류 키워드는 restaurant 타입 자체에는 적용하지 않는다', () {
      // restaurant 카테고리는 애초에 식당이 맞으므로 같은 키워드로 걸러내면 안 됨.
      expect(PoiService.looksMisclassified('할매국물닭발', PoiType.restaurant),
          isFalse);
    });

    test('(d) 행정/사업체성 명칭은 카테고리 무관하게 오분류로 판정한다', () {
      expect(
          PoiService.looksMisclassified('OO협동조합', PoiType.gasStation), isTrue);
      expect(
          PoiService.looksMisclassified('OO컨설팅', PoiType.gasStation), isTrue);
      expect(PoiService.looksMisclassified('OO협회', PoiType.cafe), isTrue);
    });

    test('(e) 정상적인 주유소/편의점 업소명은 오분류로 판정하지 않는다', () {
      expect(PoiService.looksMisclassified('GS칼텍스 오산주유소', PoiType.gasStation),
          isFalse);
      expect(PoiService.looksMisclassified('CU 오산점', PoiType.convenienceStore),
          isFalse);
    });

    test(
        '(f) 회귀 가드: "OO연구소"류 카페 브랜딩은 오분류로 판정하지 않는다 '
        '(2026-07-14 감사에서 발견된 오탐 케이스 — "조합"은 실제 상호에 정식 '
        '법인명을 그대로 쓰는 식당이 없다는 사용자 확인에 따라 의도적으로 유지)',
        () {
      expect(PoiService.looksMisclassified('OO커피연구소', PoiType.cafe), isFalse);
      // '조합'은 의도적으로 필터에 남겨둠 — 아래는 실제로 걸러지는 게 맞는
      // 케이스임을 명시하는 회귀 가드(반대 방향 오탐 방지 아님).
      expect(
          PoiService.looksMisclassified('산머루영농조합법인', PoiType.restaurant),
          isTrue);
    });
  });
}
