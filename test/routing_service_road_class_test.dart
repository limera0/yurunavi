import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  ManeuverStep step({int type = 0, int beginShapeIdx = 0}) => ManeuverStep(
        type: type,
        instruction: '',
        distanceKm: 0,
        beginShapeIdx: beginShapeIdx,
      );

  Map<String, dynamic> edge({
    int? beginShapeIndex,
    int? endShapeIndex,
    String? roadClass,
  }) {
    final m = <String, dynamic>{};
    if (beginShapeIndex != null) m['begin_shape_index'] = beginShapeIndex;
    if (endShapeIndex != null) m['end_shape_index'] = endShapeIndex;
    if (roadClass != null) m['road_class'] = roadClass;
    return m;
  }

  group('A — isGradeDowngrade: 랭크 조합', () {
    test('상위 등급 유지(primary→primary) → false(억제 대상)', () {
      expect(RoutingService.isGradeDowngrade('primary', 'primary'), isFalse);
    });

    test('등급 상승(secondary→primary, 랭크 숫자 감소) → false(억제 대상)', () {
      expect(RoutingService.isGradeDowngrade('secondary', 'primary'), isFalse);
    });

    test('등급 하락(primary→secondary, 랭크 숫자 증가) → true(정상 안내)', () {
      expect(RoutingService.isGradeDowngrade('primary', 'secondary'), isTrue);
    });

    test('등급 하락(trunk→residential) → true', () {
      expect(RoutingService.isGradeDowngrade('trunk', 'residential'), isTrue);
    });

    test('모든 랭크 조합: xr > er일 때만 true', () {
      const ranks = [
        'motorway', 'trunk', 'primary', 'secondary',
        'tertiary', 'unclassified', 'residential', 'service_other',
      ];
      for (int ei = 0; ei < ranks.length; ei++) {
        for (int xi = 0; xi < ranks.length; xi++) {
          final expected = xi > ei;
          expect(
            RoutingService.isGradeDowngrade(ranks[ei], ranks[xi]),
            expected,
            reason: '${ranks[ei]}(rank $ei) → ${ranks[xi]}(rank $xi)',
          );
        }
      }
    });
  });

  group('B — isGradeDowngrade: null/미인식 값 → 판단 불가 → true(fail-open, 정상 안내)', () {
    test('양쪽 다 null', () {
      expect(RoutingService.isGradeDowngrade(null, null), isTrue);
    });

    test('entry만 null', () {
      expect(RoutingService.isGradeDowngrade(null, 'primary'), isTrue);
    });

    test('exit만 null', () {
      expect(RoutingService.isGradeDowngrade('primary', null), isTrue);
    });

    test('인식 불가한 문자열(오타/신규 enum 값)', () {
      expect(RoutingService.isGradeDowngrade('primary', 'nonexistent_class'), isTrue);
      expect(RoutingService.isGradeDowngrade('nonexistent_class', 'primary'), isTrue);
    });
  });

  group('C — buildRoadClassByManeuverIdx: entry/exit 매칭', () {
    test('entry는 beginShapeIdx에서 끝나는 edge, exit는 시작하는 edge', () {
      final maneuvers = [step(beginShapeIdx: 5)];
      final edges = <dynamic>[
        edge(beginShapeIndex: 3, endShapeIndex: 5, roadClass: 'primary'),
        edge(beginShapeIndex: 5, endShapeIndex: 8, roadClass: 'secondary'),
      ];

      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);

      expect(map[0]?.entry, 'primary');
      expect(map[0]?.exit, 'secondary');
    });

    test('여러 maneuver 각각 독립적으로 매칭된다', () {
      final maneuvers = [
        step(beginShapeIdx: 2),
        step(beginShapeIdx: 6),
      ];
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 2, roadClass: 'trunk'),
        edge(beginShapeIndex: 2, endShapeIndex: 6, roadClass: 'trunk'),
        edge(beginShapeIndex: 6, endShapeIndex: 9, roadClass: 'tertiary'),
      ];

      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);

      expect(map[0]?.entry, 'trunk');
      expect(map[0]?.exit, 'trunk');
      expect(map[1]?.entry, 'trunk');
      expect(map[1]?.exit, 'tertiary');
    });

    test('매칭되는 edge가 전혀 없는 maneuver는 맵에서 빠진다', () {
      final maneuvers = [step(beginShapeIdx: 99)];
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, roadClass: 'primary'),
      ];

      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);

      expect(map.containsKey(0), isFalse);
    });

    test('entry edge만 매칭되고 exit edge가 없으면 exit는 null (맵엔 포함)', () {
      final maneuvers = [step(beginShapeIdx: 5)];
      final edges = <dynamic>[
        edge(beginShapeIndex: 3, endShapeIndex: 5, roadClass: 'primary'),
      ];

      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);

      expect(map[0]?.entry, 'primary');
      expect(map[0]?.exit, isNull);
    });

    test('exit edge만 매칭되고 entry edge가 없으면 entry는 null (맵엔 포함)', () {
      final maneuvers = [step(beginShapeIdx: 5)];
      final edges = <dynamic>[
        edge(beginShapeIndex: 5, endShapeIndex: 8, roadClass: 'secondary'),
      ];

      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);

      expect(map[0]?.entry, isNull);
      expect(map[0]?.exit, 'secondary');
    });

    test('road_class 필드 자체가 없는 edge는 null 값으로 취급되고 크래시 없음', () {
      final maneuvers = [step(beginShapeIdx: 5)];
      final edges = <dynamic>[
        <String, dynamic>{'begin_shape_index': 3, 'end_shape_index': 5},
        <String, dynamic>{'begin_shape_index': 5, 'end_shape_index': 8},
      ];

      expect(() => RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers),
          returnsNormally);
      final map = RoutingService.buildRoadClassByManeuverIdx(edges, maneuvers);
      // entry/exit 둘 다 null이지만 begin_shape_index==5인 edge가 매칭되므로
      // 맵 엔트리 자체는 없다(entry != null || exit != null 조건 미충족).
      expect(map.containsKey(0), isFalse);
    });

    test('빈 edges/maneuvers → 빈 맵', () {
      expect(RoutingService.buildRoadClassByManeuverIdx(const [], const []), isEmpty);
    });
  });
}
