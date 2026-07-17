import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  Map<String, dynamic> edge({
    bool bridge = false,
    bool tunnel = false,
    double? length,
    int? beginShapeIndex,
    int? endShapeIndex,
  }) {
    final m = <String, dynamic>{};
    if (bridge) m['bridge'] = bridge;
    if (tunnel) m['tunnel'] = tunnel;
    if (length != null) m['length'] = length;
    if (beginShapeIndex != null) m['begin_shape_index'] = beginShapeIndex;
    if (endShapeIndex != null) m['end_shape_index'] = endShapeIndex;
    return m;
  }

  group('A — 단일 다리 구간 (임계값 이상)', () {
    test('길이 합 100m 이상인 연속 bridge run → zone 1개', () {
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, length: 0.02),
        edge(bridge: true, beginShapeIndex: 1, endShapeIndex: 2, length: 0.06),
        edge(bridge: true, beginShapeIndex: 2, endShapeIndex: 3, length: 0.05),
        edge(beginShapeIndex: 3, endShapeIndex: 4, length: 0.02),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones.length, 1);
      expect(zones[0].type, StructureType.bridge);
      expect(zones[0].beginShapeIdx, 1);
      expect(zones[0].endShapeIdx, 3);
    });
  });

  group('B — 임계값 미만 구간은 제외', () {
    test('합산 길이 30m 미만인 bridge run → zone 0개', () {
      final edges = <dynamic>[
        edge(bridge: true, beginShapeIndex: 0, endShapeIndex: 1, length: 0.01),
        edge(bridge: true, beginShapeIndex: 1, endShapeIndex: 2, length: 0.015),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones, isEmpty);
    });
  });

  group('B2 — 짧은 도심 구조물(옛 100m 임계값에서는 버려지던 구간)은 포함', () {
    test('합산 길이 30~100m인 tunnel run → zone 1개 (RIDE_RESULTS_0716 "6-잔여" 회귀 방지)',
        () {
      // 실측 근거: "고덕좌교로" 고가(51m) 등 도심 고가/지하차도는 흔히
      // 수십 m 규모 — 옛 minLengthM=100 아래에서는 통째로 버려져 진입
      // 안내(터널/고가 진입 TTS)가 전혀 발화되지 않았다.
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, length: 0.02),
        edge(tunnel: true, beginShapeIndex: 1, endShapeIndex: 2, length: 0.03),
        edge(tunnel: true, beginShapeIndex: 2, endShapeIndex: 3, length: 0.02),
        edge(beginShapeIndex: 3, endShapeIndex: 4, length: 0.02),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones.length, 1);
      expect(zones[0].type, StructureType.tunnel);
      expect(zones[0].beginShapeIdx, 1);
      expect(zones[0].endShapeIdx, 3);
    });
  });

  group('C — 두 개의 분리된 다리 구간', () {
    test('사이에 non-bridge edge가 끼어있으면 병합되지 않고 zone 2개', () {
      // Mirrors real-world case: 7 contiguous bridge edges (1576m) then a
      // separate cluster (1330m), separated by non-bridge edges.
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, length: 0.01),
        for (int i = 1; i <= 7; i++)
          edge(
            bridge: true,
            beginShapeIndex: i,
            endShapeIndex: i + 1,
            length: 1.576 / 7,
          ),
        edge(beginShapeIndex: 8, endShapeIndex: 9, length: 0.5),
        edge(beginShapeIndex: 9, endShapeIndex: 10, length: 0.5),
        for (int i = 10; i <= 11; i++)
          edge(
            bridge: true,
            beginShapeIndex: i,
            endShapeIndex: i + 1,
            length: 1.33 / 2,
          ),
        edge(beginShapeIndex: 12, endShapeIndex: 13, length: 0.01),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones.length, 2);
      expect(zones[0].type, StructureType.bridge);
      expect(zones[0].beginShapeIdx, 1);
      expect(zones[0].endShapeIdx, 8);
      expect(zones[1].type, StructureType.bridge);
      expect(zones[1].beginShapeIdx, 10);
      expect(zones[1].endShapeIdx, 12);
    });
  });

  group('D — 터널 구간', () {
    test('bridge 케이스와 동일한 방식으로 tunnel run → zone 1개', () {
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, length: 0.02),
        edge(tunnel: true, beginShapeIndex: 1, endShapeIndex: 2, length: 0.08),
        edge(tunnel: true, beginShapeIndex: 2, endShapeIndex: 3, length: 0.08),
        edge(beginShapeIndex: 3, endShapeIndex: 4, length: 0.02),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones.length, 1);
      expect(zones[0].type, StructureType.tunnel);
      expect(zones[0].beginShapeIdx, 1);
      expect(zones[0].endShapeIdx, 3);
    });
  });

  group('E — 혼합 경로: 일반/다리/터널 순서', () {
    test('beginShapeIdx 오름차순 정렬, 타입 정확', () {
      final edges = <dynamic>[
        edge(beginShapeIndex: 0, endShapeIndex: 1, length: 0.05),
        edge(bridge: true, beginShapeIndex: 1, endShapeIndex: 2, length: 0.06),
        edge(bridge: true, beginShapeIndex: 2, endShapeIndex: 3, length: 0.05),
        edge(beginShapeIndex: 3, endShapeIndex: 4, length: 0.05),
        edge(tunnel: true, beginShapeIndex: 4, endShapeIndex: 5, length: 0.06),
        edge(tunnel: true, beginShapeIndex: 5, endShapeIndex: 6, length: 0.06),
        edge(beginShapeIndex: 6, endShapeIndex: 7, length: 0.05),
      ];

      final zones = RoutingService.buildStructureZones(edges);

      expect(zones.length, 2);
      expect(zones[0].type, StructureType.bridge);
      expect(zones[0].beginShapeIdx, 1);
      expect(zones[0].endShapeIdx, 3);
      expect(zones[1].type, StructureType.tunnel);
      expect(zones[1].beginShapeIdx, 4);
      expect(zones[1].endShapeIdx, 6);
      // sorted ascending by beginShapeIdx
      expect(zones[0].beginShapeIdx, lessThan(zones[1].beginShapeIdx));
    });
  });

  group('F — 결측/null 필드 방어 처리', () {
    test('bridge/tunnel/length 필드가 없어도 크래시 없이 false/0 취급', () {
      final edges = <dynamic>[
        <String, dynamic>{},
        <String, dynamic>{'begin_shape_index': 0, 'end_shape_index': 1},
        <String, dynamic>{'bridge': null, 'tunnel': null, 'length': null},
      ];

      expect(() => RoutingService.buildStructureZones(edges), returnsNormally);
      final zones = RoutingService.buildStructureZones(edges);
      expect(zones, isEmpty);
    });
  });
}
