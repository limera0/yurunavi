import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';
import 'package:yurunavi/features/navigation/providers/route_progress_provider.dart';
import 'package:yurunavi/services/routing_service.dart';

class _FakeNavStateNotifier extends NavStateNotifier {
  @override
  NavigationState? build() => null;
}

void main() {
  // 21포인트, 10m 간격 (다른 route_progress 테스트들과 동일한 기준선).
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;
  // 60포인트(590m) — "구조물과 너무 멀리 떨어진 exit"(gap > 기본 buffer 300m)
  // 케이스를 구성하려면 21포인트(200m) 기준선보다 긴 경로가 필요하다.
  final points = List<LatLng>.generate(
      60, (i) => LatLng(lat, baseLon + i * stepDeg));

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('exit(type 20) maneuver가 tunnel zone과 겹치면 exitStructureByManeuverIdx에 반영된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    final maneuvers = [
      const ManeuverStep(
          type: 20, instruction: '', distanceKm: 0, beginShapeIdx: 12, endShapeIdx: 14),
    ];
    const zones = [
      StructureZone(type: StructureType.tunnel, beginShapeIdx: 10, endShapeIdx: 13),
    ];

    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);
    rp.setStructureZones(zones);

    expect(rp.exitStructureByManeuverIdx, {0: StructureType.tunnel});
  });

  test('exit maneuver가 구조물 근처가 아니면 맵에 나타나지 않는다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    // zone 종료(shape 2, cum=20m), exit 시작(shape 50, cum=500m) → gap=480m
    // (기본 buffer 300m 초과).
    final maneuvers = [
      const ManeuverStep(
          type: 20, instruction: '', distanceKm: 0, beginShapeIdx: 50, endShapeIdx: 52),
    ];
    const zones = [
      StructureZone(type: StructureType.bridge, beginShapeIdx: 0, endShapeIdx: 2),
    ];

    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);
    rp.setStructureZones(zones);

    expect(rp.exitStructureByManeuverIdx, isEmpty);
  });

  test('type 20/21이 아닌 maneuver는 구조물과 겹쳐도 맵에 포함되지 않는다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    final maneuvers = [
      const ManeuverStep(
          type: 10, instruction: '', distanceKm: 0, beginShapeIdx: 10, endShapeIdx: 12),
    ];
    const zones = [
      StructureZone(type: StructureType.tunnel, beginShapeIdx: 10, endShapeIdx: 12),
    ];

    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);
    rp.setStructureZones(zones);

    expect(rp.exitStructureByManeuverIdx, isEmpty);
  });

  test('setStructureZones 이전(zones 미도착)에는 exitStructureByManeuverIdx가 비어 있다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    final maneuvers = [
      const ManeuverStep(
          type: 20, instruction: '', distanceKm: 0, beginShapeIdx: 12, endShapeIdx: 14),
    ];

    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);

    expect(rp.exitStructureByManeuverIdx, isEmpty);
  });

  test('재탐색(setRoute 재호출)은 이전 경로의 구조물 매핑을 지운다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    final maneuvers = [
      const ManeuverStep(
          type: 20, instruction: '', distanceKm: 0, beginShapeIdx: 12, endShapeIdx: 14),
    ];
    const zones = [
      StructureZone(type: StructureType.tunnel, beginShapeIdx: 10, endShapeIdx: 13),
    ];

    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);
    rp.setStructureZones(zones);
    expect(rp.exitStructureByManeuverIdx, {0: StructureType.tunnel});

    // 재탐색: 새 경로는 아직 구조물 zone을 모른다(trace_attributes 비동기 재조회 전) —
    // 이전 경로의 매핑이 새 maneuver 인덱스에 잘못 남아있으면 안 된다.
    rp.setRoute(points: points, maneuvers: maneuvers, destination: points.last);
    expect(rp.exitStructureByManeuverIdx, isEmpty);
  });
}
