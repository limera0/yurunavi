import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/routing_service.dart';

void main() {
  // cumFromStartM[i] = i * 10.0 (10m per shape index step), matching the
  // 10m-spaced synthetic fixtures used elsewhere in this test suite.
  final cumFromStartM = List<double>.generate(50, (i) => i * 10.0);

  ManeuverStep exitManeuver({
    int type = 20,
    required int beginShapeIdx,
    required int endShapeIdx,
  }) =>
      ManeuverStep(
        type: type,
        instruction: '',
        distanceKm: 0,
        beginShapeIdx: beginShapeIdx,
        endShapeIdx: endShapeIdx,
      );

  group('A — overlap은 즉시 확정', () {
    test('exit maneuver의 shape 범위가 tunnel zone과 겹치면 tunnel 반환', () {
      const zones = [
        StructureZone(
            type: StructureType.tunnel, beginShapeIdx: 10, endShapeIdx: 15),
      ];
      final m = exitManeuver(beginShapeIdx: 12, endShapeIdx: 20);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, StructureType.tunnel);
    });

    test('exit maneuver의 shape 범위가 bridge zone과 겹치면 bridge 반환', () {
      const zones = [
        StructureZone(
            type: StructureType.bridge, beginShapeIdx: 18, endShapeIdx: 22),
      ];
      final m = exitManeuver(beginShapeIdx: 20, endShapeIdx: 25);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, StructureType.bridge);
    });
  });

  group('B — overlap은 없지만 buffer(기본 300m) 이내에서 zone이 먼저 끝난 경우', () {
    test('zone 종료 지점으로부터 270m 지점에서 시작하는 exit → 그 zone 타입 반환', () {
      const zones = [
        StructureZone(
            type: StructureType.tunnel, beginShapeIdx: 5, endShapeIdx: 10),
      ];
      // zone 종료(shape 10, cum=100m) 이후 exit 시작(shape 37, cum=370m)
      // → gap=270m ≤ 300m
      final m = exitManeuver(beginShapeIdx: 37, endShapeIdx: 40);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, StructureType.tunnel);
    });

    test('정확히 buffer 경계(300m)에서도 포함된다', () {
      const zones = [
        StructureZone(
            type: StructureType.bridge, beginShapeIdx: 0, endShapeIdx: 10),
      ];
      // zone 종료(shape 10, cum=100m), exit 시작(shape 40, cum=400m) → gap=300m
      final m = exitManeuver(beginShapeIdx: 40, endShapeIdx: 45);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, StructureType.bridge);
    });
  });

  group('C — buffer 밖(너무 멂) → null', () {
    test('gap이 300m를 초과하면 null', () {
      const zones = [
        StructureZone(
            type: StructureType.tunnel, beginShapeIdx: 0, endShapeIdx: 5),
      ];
      // zone 종료(shape 5, cum=50m), exit 시작(shape 40, cum=400m) → gap=350m
      final m = exitManeuver(beginShapeIdx: 40, endShapeIdx: 45);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, isNull);
    });

    test('exit이 zone보다 앞서 있으면(음수 gap) null', () {
      const zones = [
        StructureZone(
            type: StructureType.tunnel, beginShapeIdx: 30, endShapeIdx: 35),
      ];
      final m = exitManeuver(beginShapeIdx: 5, endShapeIdx: 8);

      final result =
          RoutingService.structureNearExit(m, zones, cumFromStartM);

      expect(result, isNull);
    });
  });

  group('D — 경계값 방어', () {
    test('zone이 비어 있으면 null', () {
      final m = exitManeuver(beginShapeIdx: 10, endShapeIdx: 15);

      final result = RoutingService.structureNearExit(m, const [], cumFromStartM);

      expect(result, isNull);
    });

    test('cumFromStartM이 비어 있어도 크래시 없이 null', () {
      const zones = [
        StructureZone(
            type: StructureType.tunnel, beginShapeIdx: 0, endShapeIdx: 5),
      ];
      final m = exitManeuver(beginShapeIdx: 10, endShapeIdx: 15);

      expect(
          () => RoutingService.structureNearExit(m, zones, const []),
          returnsNormally);
      expect(RoutingService.structureNearExit(m, zones, const []), isNull);
    });
  });
}
