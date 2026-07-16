import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  Map<String, dynamic> locateEdge({
    double distance = 0.0,
    bool bridge = false,
    bool tunnel = false,
    List<String>? names,
  }) {
    return {
      'distance': distance,
      'edge': {'bridge': bridge, 'tunnel': tunnel},
      'edge_info': {'names': names ?? const <String>[]},
    };
  }

  group('A — bridge는 이름 무관 항상 고가도로', () {
    test('bridge=true, 이름 없음 → StructureType.bridge', () {
      final edges = <dynamic>[
        locateEdge(distance: 78.3, bridge: true),
      ];
      expect(RoutingService.classifyOffRouteEdges(edges), StructureType.bridge);
    });

    test('bridge=true + 이름이 있어도 여전히 고가도로', () {
      final edges = <dynamic>[
        locateEdge(distance: 50.0, bridge: true, names: ['어떤대교']),
      ];
      expect(RoutingService.classifyOffRouteEdges(edges), StructureType.bridge);
    });
  });

  group('B — tunnel 이름 판정 (지하차도/터널/폴백)', () {
    test('tunnel=true + 이름에 "지하차도" 포함 → underpass', () {
      final edges = <dynamic>[
        locateEdge(distance: 76.1, tunnel: true, names: ['고덕지하차도']),
      ];
      expect(
          RoutingService.classifyOffRouteEdges(edges), StructureType.underpass);
    });

    test('tunnel=true + 이름에 "터널" 포함 → tunnel', () {
      final edges = <dynamic>[
        locateEdge(distance: 90.0, tunnel: true, names: ['남산1호터널']),
      ];
      expect(RoutingService.classifyOffRouteEdges(edges), StructureType.tunnel);
    });

    test('tunnel=true + 이름 정보 없음 → tunnel로 폴백', () {
      final edges = <dynamic>[
        locateEdge(distance: 127.0, tunnel: true),
      ];
      expect(RoutingService.classifyOffRouteEdges(edges), StructureType.tunnel);
    });
  });

  group('C — 가장 가까운 엣지 우선', () {
    test('여러 구조물 엣지 중 distance가 가장 작은 것의 타입을 반환', () {
      final edges = <dynamic>[
        locateEdge(distance: 140.3, tunnel: true),
        locateEdge(distance: 76.1, tunnel: true, names: ['고덕지하차도']),
        locateEdge(distance: 99.3, bridge: true),
      ];
      expect(
          RoutingService.classifyOffRouteEdges(edges), StructureType.underpass);
    });
  });

  group('D — 구조물 아닌 엣지는 무시', () {
    test('bridge/tunnel 모두 false인 엣지만 있으면 null', () {
      final edges = <dynamic>[
        locateEdge(distance: 12.5, names: ['고덕국제대로']),
        locateEdge(distance: 100.9, names: ['고덕중앙로']),
      ];
      expect(RoutingService.classifyOffRouteEdges(edges), isNull);
    });

    test('빈 리스트 → null', () {
      expect(RoutingService.classifyOffRouteEdges(const []), isNull);
    });
  });

  group('F — mergeOffRouteStructures (begin/end 두 지점 병합)', () {
    test('underpass가 하나라도 있으면 즉시 채택(가장 구체적)', () {
      expect(
        RoutingService.mergeOffRouteStructures(
            [StructureType.tunnel, StructureType.underpass]),
        StructureType.underpass,
      );
    });

    test('tunnel(폴백)만 있다가 나중에 bridge가 나오면 bridge로 대체', () {
      expect(
        RoutingService.mergeOffRouteStructures(
            [StructureType.tunnel, StructureType.bridge]),
        StructureType.bridge,
      );
    });

    test('bridge 먼저, tunnel 나중이어도 bridge 유지(tunnel이 더 구체적이지 않음)', () {
      expect(
        RoutingService.mergeOffRouteStructures(
            [StructureType.bridge, StructureType.tunnel]),
        StructureType.bridge,
      );
    });

    test('전부 null이면 null', () {
      expect(RoutingService.mergeOffRouteStructures([null, null]), isNull);
    });

    test('tunnel 하나뿐이면 tunnel', () {
      expect(
        RoutingService.mergeOffRouteStructures([null, StructureType.tunnel]),
        StructureType.tunnel,
      );
    });
  });

  group('E — 결측/null 필드 방어 처리', () {
    test('edge/edge_info/distance 필드가 없어도 크래시 없이 처리', () {
      final edges = <dynamic>[
        <String, dynamic>{},
        <String, dynamic>{'edge': null},
        <String, dynamic>{'edge': {'bridge': true}},
      ];
      expect(() => RoutingService.classifyOffRouteEdges(edges), returnsNormally);
      expect(RoutingService.classifyOffRouteEdges(edges), StructureType.bridge);
    });
  });
}
