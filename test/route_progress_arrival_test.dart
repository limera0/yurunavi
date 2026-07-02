import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';
import 'package:yurunavi/features/navigation/providers/route_progress_provider.dart';

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
  // Straight route: 5 points, ~10m apart, along latitude 0 (so 1 degree
  // longitude == 111320m, no cos(lat) correction needed).
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;
  final points = List<LatLng>.generate(
      5, (i) => LatLng(lat, baseLon + i * stepDeg));

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('정상 도착: 목적지 도달 시 arrived=true, offRoute=false', () {
    container.read(routeProgressProvider); // registers _advance listener
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);

    final navNotifier = container.read(navStateProvider.notifier);
    navNotifier.state = _fixAt(points.last);

    final prog = container.read(routeProgressProvider)!;
    expect(prog.arrived, isTrue);
    expect(prog.offRoute, isFalse);
  });

  test('목적지 지나쳐 계속 주행: arrived=true 유지되며 offRoute=true 동반', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: points, maneuvers: const [], destination: points.last);

    final navNotifier = container.read(navStateProvider.notifier);
    // 1) 목적지 도착
    navNotifier.state = _fixAt(points.last);
    expect(container.read(routeProgressProvider)!.arrived, isTrue);

    // 2) 도착 후에도 같은 방향으로 60m 더 주행 (지나침)
    final overshootLon = points.last.longitude + (60.0 / metersPerDegreeLon);
    navNotifier.state = _fixAt(LatLng(lat, overshootLon));

    final prog = container.read(routeProgressProvider)!;
    expect(prog.arrived, isTrue,
        reason: 'distToDest는 폴리라인 끝에서 0으로 클램프되어 sticky해야 함');
    expect(prog.offRoute, isTrue,
        reason: '마지막 세그먼트 projection이 endpoint에 clamp되어 실제 이동거리가 perp로 잡혀야 함');
  });
}
