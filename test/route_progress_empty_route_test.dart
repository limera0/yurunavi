import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yurunavi/features/navigation/providers/nav_state_provider.dart';
import 'package:yurunavi/features/navigation/providers/route_progress_provider.dart';
import 'package:yurunavi/services/routing_service.dart';

// 회귀 대상: `_clampIdx`(내부적으로 `i.clamp(0, _pts.length - 1)`)는 `_pts`가
// 비어 있으면 상한이 -1이 되어 ArgumentError("Invalid argument(s): 0.0")를
// 던졌다. `_pts`/`_cumFromStartM`가 비었을 수 있는 경로(재탐색 중 경로 일시
// 소멸 등)에서 예외 없이 처리되는지 확인한다.
class _FakeNavStateNotifier extends NavStateNotifier {
  @override
  NavigationState? build() => null;
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        navStateProvider.overrideWith(() => _FakeNavStateNotifier()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('setRoute: points·maneuvers 모두 빈 상태에서도 예외 없이 처리한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    expect(
      () => rp.setRoute(
        points: const [],
        maneuvers: const [],
        destination: const LatLng(0, 0),
      ),
      returnsNormally,
    );
  });

  test(
    'setRoute: points가 빈 리스트인데 maneuvers는 비어있지 않은 경우(재탐색 중 '
    '경로 일시 소멸)에도 예외 없이 처리한다',
    () {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      expect(
        () => rp.setRoute(
          points: const [],
          maneuvers: const [
            ManeuverStep(
              type: 15,
              instruction: 'turn left',
              distanceKm: 0.1,
              beginShapeIdx: 3,
              endShapeIdx: 5,
            ),
          ],
          destination: const LatLng(0, 0),
        ),
        returnsNormally,
      );
    },
  );

  test('setStructureZones: 빈 경로 상태에서 zones가 들어와도 예외 없이 처리한다', () {
    container.read(routeProgressProvider);
    final rp = container.read(routeProgressProvider.notifier);
    rp.setRoute(points: const [], maneuvers: const [], destination: const LatLng(0, 0));
    expect(() => rp.setStructureZones(const []), returnsNormally);
  });
}
