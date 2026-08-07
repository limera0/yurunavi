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

NavigationState _fixAt(LatLng pos) => NavigationState(
      pos: pos,
      speedKmh: 0,
      moving: false,
      headingDeg: null,
      firstFix: true,
      fixAt: DateTime.now(),
      stale: false,
    );

void main() {
  // Straight route: 21 points, 10m apart, along latitude 0 (so 1 degree
  // longitude == 111320m, no cos(lat) correction needed). Total ~200m.
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;
  final points = List<LatLng>.generate(
      21, (i) => LatLng(lat, baseLon + i * stepDeg));

  // 다리 구간: shape idx 5~8 (50m~80m 지점). 터널 구간: shape idx 15~18 (150m~180m 지점).
  const zones = [
    StructureZone(type: StructureType.bridge, beginShapeIdx: 5, endShapeIdx: 8),
    StructureZone(type: StructureType.tunnel, beginShapeIdx: 15, endShapeIdx: 18),
  ];

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('setStructureZones 직후: 첫 구조물(bridge)까지 거리·타입이 즉시 반영된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 0);
    expect(prog.nextStructureType, StructureType.bridge);
    expect(prog.distToNextStructureM, closeTo(50, 1.0));
  });

  test('접근하며 distToNextStructureM이 감소하고, 진입 후 0으로 클램프된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final navNotifier = container.read(navStateProvider.notifier);

    navNotifier.state = _fixAt(points[3]);
    var prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 0);
    expect(prog.nextStructureType, StructureType.bridge);
    // points[3]는 세그먼트 2(20m)를 10m 지나 traveledM=30m 지점. 브릿지 진입은
    // beginShapeIdx=5(50m) 이므로 정확한 잔여거리는 50-30=20m.
    expect(prog.distToNextStructureM, closeTo(20, 1.0));

    navNotifier.state = _fixAt(points[6]);
    prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 0);
    expect(prog.nextStructureType, StructureType.bridge);
    expect(prog.distToNextStructureM, closeTo(0, 1.0),
        reason: '구간 진입 후에는 남은 거리가 0으로 클램프되어야 함');
  });

  test('다리 구간 통과 후 다음 구조물(tunnel)로 전환된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final navNotifier = container.read(navStateProvider.notifier);

    navNotifier.state = _fixAt(points[9]); // bridge(end=8) 통과 직후
    var prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 1);
    expect(prog.nextStructureType, StructureType.tunnel);
    // points[9]는 세그먼트 8(80m)을 10m 지나 traveledM=90m 지점. 터널 진입은
    // beginShapeIdx=15(150m) 이므로 정확한 잔여거리는 150-90=60m.
    expect(prog.distToNextStructureM, closeTo(60, 1.5));

    navNotifier.state = _fixAt(points[16]); // tunnel 구간 진입 중
    prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 1);
    expect(prog.nextStructureType, StructureType.tunnel);
    expect(prog.distToNextStructureM, closeTo(0, 1.0));
  });

  test('모든 구조물 통과 후: "다음 구조물 없음" 상태(-1, ∞, null)를 보고한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final navNotifier = container.read(navStateProvider.notifier);
    navNotifier.state = _fixAt(points[19]); // tunnel(end=18) 통과 직후

    final prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, -1);
    expect(prog.distToNextStructureM, double.infinity);
    expect(prog.nextStructureType, isNull);
  });

  test('빈 리스트로 setStructureZones 호출 시 크래시 없이 "다음 구조물 없음"을 보고한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final navNotifier = container.read(navStateProvider.notifier);
    navNotifier.state = _fixAt(points[3]);
    expect(container.read(routeProgressProvider)!.structureZoneIdx, 0);

    rp.setStructureZones(const []);
    final prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, -1);
    expect(prog.distToNextStructureM, double.infinity);
    expect(prog.nextStructureType, isNull);
  });

  test('모든 구조물이 이미 지나간 시점에 setStructureZones를 다시 호출해도 안전하다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setStructureZones(zones);

    final navNotifier = container.read(navStateProvider.notifier);
    navNotifier.state = _fixAt(points[19]); // 두 구조물 모두 통과
    expect(container.read(routeProgressProvider)!.structureZoneIdx, -1);

    // 같은 zone 목록으로 재주입해도 크래시 없이 "다음 구조물 없음" 유지.
    rp.setStructureZones(zones);
    final prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, -1);
    expect(prog.distToNextStructureM, double.infinity);
    expect(prog.nextStructureType, isNull);
  });

  test('setRoute 후 GPS로 이미 전진한 뒤 setStructureZones가 도착해도 '
      '전진한 위치 기준으로 정확히 재계산된다 (trace_attributes 응답 지연 시나리오)', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);

    final navNotifier = container.read(navStateProvider.notifier);
    // trace_attributes(setStructureZones) 도착 전에 라이더가 이미 전진.
    navNotifier.state = _fixAt(points[3]); // traveledM=30m, snapIdx=2

    // 아직 zone 정보 없음 — "다음 구조물 없음" 상태여야 함.
    var prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, -1);
    expect(prog.distToNextStructureM, double.infinity);

    // trace_attributes 응답이 뒤늦게 도착.
    rp.setStructureZones(zones);

    prog = container.read(routeProgressProvider)!;
    expect(prog.structureZoneIdx, 0);
    expect(prog.nextStructureType, StructureType.bridge);
    // 이미 전진해있던 30m 지점 기준으로 재계산되어야 함: 50-30=20m (0m이 아님).
    expect(prog.distToNextStructureM, closeTo(20, 1.0));
  });

  test('setRoute 전 setStructureZones 호출은 크래시 없이 무시된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    // setRoute를 아직 호출하지 않은 상태(state == null).
    expect(() => rp.setStructureZones(zones), returnsNormally);
    expect(container.read(routeProgressProvider), isNull);
  });
}
