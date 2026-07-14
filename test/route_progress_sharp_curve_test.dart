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
    );

void main() {
  // 21포인트, 10m 간격, 위도 0(경도 1도==111320m, cos(lat) 보정 불필요).
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;

  // 직선(구조물 테스트와 동일한 기준선).
  final straightPoints = List<LatLng>.generate(
      21, (i) => LatLng(lat, baseLon + i * stepDeg));

  // 급커브 경로: 0~150m 동쪽 직진 → 급격히 북쪽으로 꺾음(90도 좌회전).
  // detectSharpCurves 계산 결과 shape idx 6~14(60m~140m) 구간이 좌회전 zone.
  final bentPoints = <LatLng>[
    for (int i = 0; i <= 15; i++) LatLng(lat, baseLon + i * stepDeg),
    for (int i = 1; i <= 5; i++)
      LatLng(lat + i * stepDeg, baseLon + 15 * stepDeg),
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

  test('setRoute 직후: geometry에서 감지된 급커브까지 거리·방향이 즉시 반영된다 '
      '(비동기 setter 불필요)', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: bentPoints, maneuvers: const [], destination: bentPoints.last);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, 0);
    expect(prog.nextCurveDirection, CurveDirection.left);
    expect(prog.distToNextCurveM, closeTo(60, 1.0));
  });

  test('접근하며 distToNextCurveM이 감소하고, 진입 후 0으로 클램프된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: bentPoints, maneuvers: const [], destination: bentPoints.last);

    final navNotifier = container.read(navStateProvider.notifier);

    navNotifier.state = _fixAt(bentPoints[2]); // traveledM≈20
    var prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, 0);
    expect(prog.nextCurveDirection, CurveDirection.left);
    expect(prog.distToNextCurveM, closeTo(40, 1.0));

    navNotifier.state = _fixAt(bentPoints[4]); // traveledM≈40
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCurveM, closeTo(20, 1.0));

    navNotifier.state = _fixAt(bentPoints[10]); // curve 진입 중(traveledM≈100)
    prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, 0);
    expect(prog.distToNextCurveM, closeTo(0, 1.0),
        reason: '구간 진입 후에는 남은 거리가 0으로 클램프되어야 함');
  });

  test('급커브 통과 후: "다음 급커브 없음" 상태(-1, ∞, null)를 보고한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: bentPoints, maneuvers: const [], destination: bentPoints.last);

    final navNotifier = container.read(navStateProvider.notifier);
    navNotifier.state = _fixAt(bentPoints[19]); // curve(end=14) 통과 후

    final prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, -1);
    expect(prog.distToNextCurveM, double.infinity);
    expect(prog.nextCurveDirection, isNull);
  });

  test('maneuvers와 겹치는 급커브는 억제되어 "다음 급커브 없음"을 보고한다', () {
    // 억제 없이 감지되는 커브의 shape 인덱스 범위를 먼저 확인.
    final detected = RoutingService.detectSharpCurves(bentPoints, const []);
    expect(detected, isNotEmpty);
    final curve = detected.first;

    final maneuvers = [
      ManeuverStep(
        type: 14,
        instruction: '좌회전',
        distanceKm: 0.08,
        beginShapeIdx: curve.beginShapeIdx,
        endShapeIdx: curve.endShapeIdx,
      ),
    ];

    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(
        points: bentPoints, maneuvers: maneuvers, destination: bentPoints.last);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, -1);
    expect(prog.distToNextCurveM, double.infinity);
    expect(prog.nextCurveDirection, isNull);
  });

  test('직선 경로(급커브 없음)에서는 "다음 급커브 없음"을 보고한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(
        points: straightPoints, maneuvers: const [], destination: straightPoints.last);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.curveZoneIdx, -1);
    expect(prog.distToNextCurveM, double.infinity);
    expect(prog.nextCurveDirection, isNull);
  });

  test('setStructureZones 호출은 curve 필드를 그대로 보존한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: bentPoints, maneuvers: const [], destination: bentPoints.last);

    final before = container.read(routeProgressProvider)!;
    rp.setStructureZones(const []);
    final after = container.read(routeProgressProvider)!;

    expect(after.curveZoneIdx, before.curveZoneIdx);
    expect(after.distToNextCurveM, before.distToNextCurveM);
    expect(after.nextCurveDirection, before.nextCurveDirection);
  });
}
