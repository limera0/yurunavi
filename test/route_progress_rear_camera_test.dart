import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/navigation/models/rear_camera.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';
import 'package:yurunavi/features/navigation/providers/route_progress_provider.dart';

class _FakeNavStateNotifier extends NavStateNotifier {
  @override
  NavigationState? build() => null;
}

NavigationState _fixAt(LatLng pos, {double? headingDeg}) => NavigationState(
      pos: pos,
      speedKmh: 0,
      moving: false,
      headingDeg: headingDeg,
      firstFix: true,
      fixAt: DateTime.now(),
      stale: false,
    );

void main() {
  // 직선 경로: 41포인트, 10m 간격, 동쪽(경도 증가) 방향, 위도 0(경도 1도==111320m).
  // 총 길이 400m. 헤딩 90°(동쪽)로 이동 중이라고 가정.
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  const headingEast = 90.0;
  final stepDeg = stepM / metersPerDegreeLon;
  final points =
      List<LatLng>.generate(41, (i) => LatLng(lat, baseLon + i * stepDeg));

  // 카메라: 300m 지점(points[30])에 위치, 제한속도 60km/h, 사후구간 90m.
  final camera = RearCamera(
    lat: points[30].latitude,
    lng: points[30].longitude,
    speedKmh: 60,
    postZoneM: 90,
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('정면 150m 접근 시 카메라가 탐지되어 거리·제한속도·사후구간이 반영된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setRearCameras([camera]);

    final navNotifier = container.read(navStateProvider.notifier);
    // points[15] == 150m 지점, 카메라(300m)까지 정확히 150m 전방, 헤딩 90°(동)로
    // 카메라 방위(동)와 일치.
    navNotifier.state = _fixAt(points[15], headingDeg: headingEast);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, closeTo(150, 1.0));
    expect(prog.nextCameraSpeedKmh, 60);
    expect(prog.nextCameraPostZoneM, 90);
    expect(prog.inPostZone, isFalse);
  });

  test('후방(반대 헤딩)에 있는 카메라는 탐지되지 않는다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setRearCameras([camera]);

    final navNotifier = container.read(navStateProvider.notifier);
    // points[35] == 350m 지점: 카메라(300m)는 이미 50m 뒤에 있고, 이 시나리오에선
    // 사전에 전방 접근 이력(추적 상태)이 전혀 없으므로 새로 탐지되면 안 된다.
    navNotifier.state = _fixAt(points[35], headingDeg: headingEast);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, double.infinity);
    expect(prog.nextCameraSpeedKmh, 0);
    expect(prog.inPostZone, isFalse);
  });

  test('카메라 통과 후 postZoneM 이내에서는 inPostZone이 true가 된다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setRearCameras([camera]);

    final navNotifier = container.read(navStateProvider.notifier);

    // 1) 카메라(300m) 전방 50m 지점(250m)에서 먼저 접근 탐지되어 추적 시작.
    navNotifier.state = _fixAt(points[25], headingDeg: headingEast);
    var prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, closeTo(50, 1.0));
    expect(prog.inPostZone, isFalse);

    // 2) 카메라를 지나쳐 20m 진행(320m 지점). 사후구간(90m) 이내이므로
    // inPostZone이 true로 전환되어야 한다.
    navNotifier.state = _fixAt(points[32], headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, closeTo(20, 1.0));
    expect(prog.nextCameraSpeedKmh, 60);
    expect(prog.nextCameraPostZoneM, 90);
    expect(prog.inPostZone, isTrue);

    // 3) 사후구간(90m)마저 완전히 벗어나면(400m 지점, 통과 후 100m > 90m) 추적이
    // 해제되어 "탐지 없음" 상태로 돌아온다.
    navNotifier.state = _fixAt(points[40], headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, double.infinity);
    expect(prog.inPostZone, isFalse);
  });

  test(
      '경로에서 옆으로 오프셋된 카메라도 접근~통과~사후구간 전 구간에서 '
      'distToNextCameraM이 infinity로 튀지 않는다 (70°/90° 데드존 회귀)', () {
    // 카메라를 경로에서 북쪽으로 8m 오프셋시킨 퇴화 아닌 케이스. 경로상 정확히
    // 300m 지점(along=300m)의 abeam(최근접) 지점 기준, 진행(동쪽)에 따라
    // 카메라까지의 방위각이 0°→90°→180°로 연속적으로 변한다. 오프셋 0m(경로
    // 직선상)인 기존 3개 테스트는 이 전이 구간을 전혀 지나지 않는 퇴화 케이스라
    // 놓쳤던 버그: angleDiff가 70°(fresh 탐색 tolerance)~90°(통과 확정 threshold)
    // 사이일 때(오프셋 8m 기준 abeam 전 약 2.9m 구간) distToNextCameraM이
    // 잘못 infinity로 튀는 문제를 검증한다.
    const camOffsetM = 8.0;
    final camLatOffsetDeg = camOffsetM / metersPerDegreeLon;
    final offsetCamera = RearCamera(
      lat: lat + camLatOffsetDeg,
      lng: points[30].longitude, // along=300m 지점과 같은 경도(=abeam 지점)
      speedKmh: 60,
      postZoneM: 90,
    );

    // along-track 300m 지점을 기준으로 임의의 전후 거리(alongM, 동쪽 +)에
    // 대응하는 위치(경로 직선상, lat=0)를 만든다.
    LatLng posAtOffsetFromCamera(double alongM) =>
        LatLng(lat, points[30].longitude + alongM / metersPerDegreeLon);

    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);
    rp.setRearCameras([offsetCamera]);

    final navNotifier = container.read(navStateProvider.notifier);

    // 1) 카메라 abeam 지점 100m 전방(dx=100m, dy=8m) — angleDiff≈4.6°, 여유
    //    있게 70° tolerance 이내라 fresh 탐색으로 최초 탐지된다.
    navNotifier.state =
        _fixAt(posAtOffsetFromCamera(-100), headingDeg: headingEast);
    var prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, closeTo(100.32, 0.5));
    expect(prog.nextCameraSpeedKmh, 60);
    expect(prog.inPostZone, isFalse);

    // 2) abeam 지점 2m 전방(dx=2m) — angleDiff≈75.96°, 70°~90° 데드존. 수정
    //    전에는 fresh 탐색(70° tolerance)에서 탈락하고 tracked 분기도 90°
    //    문턱을 못 넘어 조기반환 못 해 distToNextCameraM이 infinity로
    //    잘못 튀었다. 수정 후에는 추적 중인 카메라 값을 그대로 반환해야 한다.
    navNotifier.state =
        _fixAt(posAtOffsetFromCamera(-2), headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, isNot(double.infinity));
    expect(prog.distToNextCameraM, closeTo(8.25, 0.5));
    expect(prog.nextCameraSpeedKmh, 60);
    expect(prog.inPostZone, isFalse);

    // 3) abeam 지점 1m 통과(dx=-1m) — angleDiff≈97.1°(>90), 통과 확정 직후.
    //    사후구간(90m) 이내이므로 inPostZone=true, 카메라는 계속 유지된다.
    navNotifier.state =
        _fixAt(posAtOffsetFromCamera(1), headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, isNot(double.infinity));
    expect(prog.distToNextCameraM, closeTo(8.06, 0.5));
    expect(prog.nextCameraSpeedKmh, 60);
    expect(prog.inPostZone, isTrue);

    // 4) abeam 지점 80m 통과 — 여전히 사후구간(90m) 이내.
    navNotifier.state =
        _fixAt(posAtOffsetFromCamera(80), headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, isNot(double.infinity));
    expect(prog.inPostZone, isTrue);

    // 5) abeam 지점 95m 통과 — 사후구간(90m)마저 벗어나 추적 해제.
    navNotifier.state =
        _fixAt(posAtOffsetFromCamera(95), headingDeg: headingEast);
    prog = container.read(routeProgressProvider)!;
    expect(prog.distToNextCameraM, double.infinity);
    expect(prog.nextCameraSpeedKmh, 0);
    expect(prog.inPostZone, isFalse);
  });
}
