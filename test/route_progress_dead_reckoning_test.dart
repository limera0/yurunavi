// S7 — 터널 dead reckoning(HANDOFF_0807_S7_tunnel_dead_reckoning.md) 통합
// 테스트.
//
// 실벽시계 sleep 대신 package:fake_async로 Timer.periodic을 제어한다 —
// RouteProgressNotifier._startDeadReckoning()이 만드는 500ms 주기 타이머는
// 별도 주입 없이 호출 시점의 Zone.current를 그대로 쓰므로, fakeAsync(...)
// 콜백 안에서 동기적으로 트리거되는 한 자동으로 가짜 타이머가 된다.
//
// 커버리지(HANDOFF §검증 요구):
//  ① 정상 주행 중 stale 전환 시 터널 밖이면 dead reckoning 미진입
//  ② 터널 안에서 stale 전환 시 진입 + _traveledM 시간 비례 전진
//  ③ 터널 끝 도달 시 더 전진하지 않고 유지
//  ④ 실측 fix 복귀 시 정상 _advance()로 복귀(+ 알려진 리스크 완화책: 뒤쪽
//     스냅 1회 허용 확인)
//  + _pointAtCumulativeM 경계값(0, 끝, 세그먼트 정확히 위) — private 헬퍼라
//    직접 호출은 못 하므로 RouteProgress.estimatedPos(공개 필드)를 통해
//    간접 검증한다.
import 'package:fake_async/fake_async.dart';
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

NavigationState _fixAt(
  LatLng pos, {
  double speedKmh = 0,
  bool stale = false,
  DateTime? fixAt,
  double? headingDeg,
}) =>
    NavigationState(
      pos: pos,
      speedKmh: speedKmh,
      moving: speedKmh > 0,
      headingDeg: headingDeg,
      firstFix: true,
      fixAt: fixAt ?? DateTime.now(),
      stale: stale,
    );

void main() {
  // 직선 경로: 21포인트, 10m 간격, 위도 0(경도 1도==111320m, cos(lat) 보정
  // 불필요). 총 200m. 터널 zone: shape idx 10~15(100m~150m).
  const metersPerDegreeLon = 111320.0;
  const lat = 0.0;
  const baseLon = 127.0;
  const stepM = 10.0;
  final stepDeg = stepM / metersPerDegreeLon;
  final points =
      List<LatLng>.generate(21, (i) => LatLng(lat, baseLon + i * stepDeg));

  const tunnel =
      StructureZone(type: StructureType.tunnel, beginShapeIdx: 10, endShapeIdx: 15);

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [navStateProvider.overrideWith(() => _FakeNavStateNotifier())],
    );
    addTearDown(container.dispose);
  });

  test('① 터널 밖에서 stale 전환 시 dead reckoning에 진입하지 않는다', () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      rp.setStructureZones(const [tunnel]);

      final navNotifier = container.read(navStateProvider.notifier);
      final t0 = DateTime(2026, 1, 1);

      // 터널(10~15) 밖: points[2] 부근(snapIdx < 10)에서 실측 주행.
      navNotifier.state =
          _fixAt(points[2], speedKmh: 36, stale: false, fixAt: t0);
      var prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isFalse);
      expect(prog.snapIdx, lessThan(10));
      final snapBeforeStale = prog.snapIdx;
      final traveledBeforeStale = prog.distToDestM;

      // 같은 위치에서 GPS 상실(stale=true) — 터널 밖이므로 미진입.
      navNotifier.state = _fixAt(points[2],
          speedKmh: 0, stale: true, fixAt: t0.add(const Duration(seconds: 8)));
      prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isFalse,
          reason: '터널 밖 GPS 순단은 이번 스코프가 아님 — 기존 동결 동작 유지');

      // 시간이 흘러도(타이머가 시작되지 않았으므로) 위치가 스스로 전진하지 않는다.
      async.elapse(const Duration(seconds: 5));
      prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isFalse);
      expect(prog.snapIdx, equals(snapBeforeStale));
      expect(prog.distToDestM, equals(traveledBeforeStale));
      expect(prog.estimatedPos, isNull);
    });
  });

  test('② 터널 안에서 stale 전환 시 진입하고 _traveledM이 시간에 비례해 전진한다', () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      rp.setStructureZones(const [tunnel]);

      final navNotifier = container.read(navStateProvider.notifier);
      final t0 = DateTime(2026, 1, 1);

      // 실측 fix 2건으로 60초 버퍼에 평균 36km/h(=10m/s)를 쌓는다(30, 42의
      // 평균 — 단순 "마지막 값"이 아니라 진짜 평균이 쓰이는지 확인).
      navNotifier.state =
          _fixAt(points[11], speedKmh: 30, stale: false, fixAt: t0);
      navNotifier.state = _fixAt(points[11],
          speedKmh: 42, stale: false, fixAt: t0.add(const Duration(seconds: 1)));
      var prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isFalse);
      expect(prog.snapIdx, equals(10), reason: 'points[11]은 seg10의 끝점(100m~110m)');
      expect(prog.distToDestM, closeTo(200 - 110, 0.5));

      // GPS 상실 — 현재 snapIdx(10)가 터널(10~15) 범위 안이므로 dead reckoning 진입.
      navNotifier.state = _fixAt(points[11],
          speedKmh: 0, stale: true, fixAt: t0.add(const Duration(seconds: 2)));
      prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue);
      // 진입 직후(아직 타이머 tick 전)엔 전진 없이 현재 위치 그대로 —
      // _pointAtCumulativeM(110)은 세그먼트 경계(cum[11]=110)와 정확히
      // 일치하므로 points[11]과 같아야 한다("세그먼트 정확히 위" 경계값).
      expect(prog.estimatedPos!.latitude, closeTo(points[11].latitude, 1e-9));
      expect(prog.estimatedPos!.longitude, closeTo(points[11].longitude, 1e-9));

      // 500ms 경과 → 1회 tick. avgSpeedMps=10 * 1.05 = 10.5 m/s, 0.5s → 5.25m 전진.
      async.elapse(const Duration(milliseconds: 500));
      prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue);
      expect(prog.distToDestM, closeTo(200 - 115.25, 0.05));
      expect(prog.snapIdx, equals(11));

      // 추가로 1000ms(2 tick) 더 경과 → 총 1500ms(3 tick)에 걸쳐 15.75m 전진
      // (5.25m × 3) — 시간에 비례해 계속 전진함을 확인.
      async.elapse(const Duration(milliseconds: 1000));
      prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue);
      expect(prog.distToDestM, closeTo(200 - 125.75, 0.05));
    });
  });

  test('③ 터널 끝(150m)에 도달하면 더 전진하지 않고 그 자리에서 대기한다', () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      rp.setStructureZones(const [tunnel]);

      final navNotifier = container.read(navStateProvider.notifier);
      final t0 = DateTime(2026, 1, 1);

      navNotifier.state =
          _fixAt(points[11], speedKmh: 36, stale: false, fixAt: t0);
      navNotifier.state = _fixAt(points[11],
          speedKmh: 0, stale: true, fixAt: t0.add(const Duration(seconds: 1)));
      expect(container.read(routeProgressProvider)!.deadReckoning, isTrue);

      // 110m 지점에서 시작, 5.25m/tick으로 터널 끝(150m)까지 40m —
      // 넉넉히 6초(12 tick, 63m 상당) 경과시켜 확실히 넘어서게 한다.
      async.elapse(const Duration(seconds: 6));
      var prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue,
          reason: '터널 끝 도달 후에도 타이머는 유지한 채 실측 fix를 기다린다(종료조건 B)');
      expect(prog.distToDestM, closeTo(200 - 150, 0.05),
          reason: '터널 끝(endShapeIdx=15 → 150m)을 넘어서까지 추정하지 않음');
      expect(prog.snapIdx, equals(15));
      // 150m은 cum[15]와 정확히 일치하는 세그먼트 경계 — estimatedPos는
      // points[15]와 같아야 한다.
      expect(prog.estimatedPos!.latitude, closeTo(points[15].latitude, 1e-9));
      expect(prog.estimatedPos!.longitude, closeTo(points[15].longitude, 1e-9));

      // 더 기다려도(2초 추가) 그 자리에서 계속 대기 — 넘어서지 않는다.
      async.elapse(const Duration(seconds: 2));
      prog = container.read(routeProgressProvider)!;
      expect(prog.distToDestM, closeTo(200 - 150, 0.05));
      expect(prog.snapIdx, equals(15));
    });
  });

  test('④ 실측 fix 복귀 시 정상 _advance()로 복귀한다(뒤처진 위치 포함 — 알려진 리스크 완화)',
      () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      rp.setStructureZones(const [tunnel]);

      final navNotifier = container.read(navStateProvider.notifier);
      final t0 = DateTime(2026, 1, 1);

      navNotifier.state =
          _fixAt(points[11], speedKmh: 36, stale: false, fixAt: t0);
      navNotifier.state = _fixAt(points[11],
          speedKmh: 0, stale: true, fixAt: t0.add(const Duration(seconds: 1)));
      async.elapse(const Duration(seconds: 6)); // 터널 끝(snapIdx=15)에서 대기 중
      expect(container.read(routeProgressProvider)!.snapIdx, equals(15));
      expect(container.read(routeProgressProvider)!.deadReckoning, isTrue);

      // ×1.05로 낙관 추정했던 dead reckoning보다 실제로는 덜 갔던 상황을
      // 재현 — 실측 fix가 points[5](50m), 즉 dead reckoning이 밀어둔
      // snapIdx=15(150m)보다 한참 "뒤"에서 돌아온다.
      navNotifier.state = _fixAt(points[5],
          speedKmh: 30, stale: false, fixAt: t0.add(const Duration(seconds: 10)));
      var prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isFalse,
          reason: '실측 fix 도착(종료조건 A) — 정상 _advance()로 복귀');
      expect(prog.estimatedPos, isNull);
      // 완화책이 없었다면(전방 전용 탐색, start=_snapIdx=15) 이 실측 위치는
      // [15,19] 범위에서 최근접을 찾지 못해 offRoute 오탐 또는 부정확한
      // snapIdx=15 고정으로 이어진다. 완화책 적용 후엔 올바르게 뒤쪽
      // (points[5] 부근)으로 다시 스냅되어야 한다.
      expect(prog.snapIdx, lessThan(10));
      expect(prog.offRoute, isFalse,
          reason: '뒤쪽 스냅 허용 덕분에 실제로는 코리도 위인 위치가 이탈로 오탐되지 않아야 함');

      // 1회성 소진 확인: 바로 다음 실측 fix부터는 다시 순수 전방 전용
      // 단조 스냅으로 복귀한다 — 이번엔 뒤로 가는 위치를 줘도 고정돼야 함.
      final snapAfterRecovery = prog.snapIdx;
      navNotifier.state = _fixAt(points[0],
          speedKmh: 0, stale: false, fixAt: t0.add(const Duration(seconds: 11)));
      prog = container.read(routeProgressProvider)!;
      expect(prog.snapIdx, equals(snapAfterRecovery),
          reason: '뒤쪽 스냅 허용은 1회성 — 소진 후에는 다시 단조 전진만 허용');
    });
  });

  test('_pointAtCumulativeM 경계값: targetM=0 → 경로 시작점', () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      // 터널이 경로 시작(shape idx 0)부터 시작 — 실측 fix 없이 곧바로
      // stale 진입해도(_snapIdx 기본값 0) dead reckoning이 시작된다.
      rp.setStructureZones(const [
        StructureZone(type: StructureType.tunnel, beginShapeIdx: 0, endShapeIdx: 5),
      ]);

      final navNotifier = container.read(navStateProvider.notifier);
      navNotifier.state =
          _fixAt(points[0], speedKmh: 0, stale: true, fixAt: DateTime(2026, 1, 1));

      final prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue);
      expect(prog.estimatedPos!.latitude, closeTo(points[0].latitude, 1e-9));
      expect(prog.estimatedPos!.longitude, closeTo(points[0].longitude, 1e-9));
    });
  });

  test('_pointAtCumulativeM 경계값: targetM=경로 끝(_totalM) → 마지막 점', () {
    fakeAsync((async) {
      container.read(routeProgressProvider);
      final rp = container.read(routeProgressProvider.notifier);
      rp.setRoute(points: points, maneuvers: const [], destination: points.last);
      // 터널이 경로 전체를 덮음 — 매우 빠른 평균속도로 한 tick 만에
      // 종점(200m)까지 캡되는지 확인.
      rp.setStructureZones(const [
        StructureZone(type: StructureType.tunnel, beginShapeIdx: 0, endShapeIdx: 20),
      ]);

      final navNotifier = container.read(navStateProvider.notifier);
      final t0 = DateTime(2026, 1, 1);
      navNotifier.state =
          _fixAt(points[0], speedKmh: 3600, stale: false, fixAt: t0); // 1000 m/s
      navNotifier.state = _fixAt(points[0],
          speedKmh: 0, stale: true, fixAt: t0.add(const Duration(seconds: 1)));

      async.elapse(const Duration(milliseconds: 500));

      final prog = container.read(routeProgressProvider)!;
      expect(prog.deadReckoning, isTrue);
      expect(prog.distToDestM, closeTo(0, 0.5));
      expect(prog.estimatedPos!.latitude, closeTo(points.last.latitude, 1e-9));
      expect(prog.estimatedPos!.longitude, closeTo(points.last.longitude, 1e-9));
    });
  });
}
