// 후면단속카메라 게이지(18번 Phase 2) 위젯 테스트.
//
// nav_screen.dart를 통째로 마운트하지 않고(GPS/TTS/geolocator 채널 모킹이
// 많이 필요해 무거움), rear_camera_gauge.dart의 위젯들이 순수 데이터만 받는
// 독립 컴포넌트라는 성질을 이용해 직접 pump한다 — DaylightBar 등 기존
// 위젯과 동일 패턴.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/presentation/nav_screen.dart';
import 'package:yurunavi/features/navigation/presentation/rear_camera_gauge.dart';
import 'package:yurunavi/features/navigation/providers/route_progress_provider.dart';

/// [RouteProgress]는 필드 16개 전부 required라 테스트마다 통째로 채우면
/// 장황해진다 — 이 테스트에서 관심 있는 카메라 관련 값만 인자로 받고 나머지는
/// "카메라와 무관"한 기본값으로 채우는 헬퍼.
RouteProgress _progress({
  required bool inPostZone,
  double distToNextCameraM = double.infinity,
  int nextCameraSpeedKmh = 0,
  int nextCameraPostZoneM = 0,
}) =>
    RouteProgress(
      snapIdx: 0,
      activeStepIdx: 0,
      distToNextTurnM: 100,
      distToDestM: 1000,
      arrived: false,
      offRoute: false,
      structureZoneIdx: -1,
      distToNextStructureM: double.infinity,
      nextStructureType: null,
      curveZoneIdx: -1,
      distToNextCurveM: double.infinity,
      nextCurveDirection: null,
      distToNextCameraM: distToNextCameraM,
      nextCameraSpeedKmh: nextCameraSpeedKmh,
      nextCameraPostZoneM: nextCameraPostZoneM,
      inPostZone: inPostZone,
    );

void main() {
  group('CameraPostZoneGauge', () {
    testWidgets('사후구간 진입 시 SLOW 링(둘레 문자)과 카운트다운 숫자가 렌더된다',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraPostZoneGauge(remainingM: 42),
          ),
        ),
      );
      await tester.pump();

      // 카운트다운 숫자(반올림 정수).
      expect(find.text('42'), findsOneWidget);
      // 원형 배치된 "SLOW" 각 글자.
      for (final letter in ['S', 'L', 'O', 'W']) {
        expect(find.text(letter), findsOneWidget);
      }
    });

    testWidgets('remainingM이 바뀌면 카운트다운 숫자도 갱신된다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CameraPostZoneGauge(remainingM: 90)),
        ),
      );
      await tester.pump();
      expect(find.text('90'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CameraPostZoneGauge(remainingM: 10)),
        ),
      );
      await tester.pump();
      expect(find.text('10'), findsOneWidget);
      expect(find.text('90'), findsNothing);
    });
  });

  group('CameraApproachGauge', () {
    testWidgets('남은 거리(정수)와 METER. 라벨이 렌더된다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CameraApproachGauge(distanceM: 120)),
        ),
      );
      await tester.pump();

      expect(find.text('120'), findsOneWidget);
      expect(find.text('METER.'), findsOneWidget);
    });
  });

  group('SpeedWarningOverlay', () {
    testWidgets('active=false면 아무것도 렌더하지 않는다', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SpeedWarningOverlay(active: false)),
        ),
      );
      await tester.pump();

      expect(find.byType(Container), findsNothing);
    });

    testWidgets('active=true면 빨강 반투명 오버레이가 렌더되고 오파시티가 진동한다',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SpeedWarningOverlay(active: true)),
        ),
      );
      await tester.pump();

      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      Color colorAt(Duration d) {
        return tester
            .widget<Container>(containerFinder)
            .color!;
      }

      final first = colorAt(Duration.zero);
      expect(first.r, greaterThan(0)); // 빨강 계열
      expect(first.a, closeTo(0.15, 0.02)); // 시작 오파시티

      // 심장박동 진동 — 절반 주기(325ms) 뒤엔 오파시티가 상승해 있어야 한다.
      await tester.pump(const Duration(milliseconds: 325));
      final second = colorAt(Duration.zero);
      expect(second.a, greaterThan(first.a));
    });
  });

  group('RearCameraGaugeSwitcher (nav_screen.dart)', () {
    // 회귀 가드: didUpdateWidget()은 위젯이 처음 마운트될 때는 호출되지 않는다
    // (initState+build만). 이미 inPostZone=true인 상태로 새로 생성된
    // 위젯(예: 앱 재시작/화면 복귀 시 라이더가 마침 사후구간 안에 있는 경우)이
    // 그 다음 진행값 갱신에서 "false→true 전환"으로 오인해 CameraTransitionFlash를
    // 허위 재생하면 안 된다.
    testWidgets(
      '이미 사후구간(inPostZone=true)인 상태로 마운트된 뒤 같은 상태로 갱신돼도 '
      '전환 플래시가 뜨지 않는다',
      (tester) async {
        Future<void> pumpWith(RouteProgress p) => tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: RearCameraGaugeSwitcher(
                    progress: p,
                    speedKmh: 40,
                    firstFixReceived: true,
                    brandColor: Colors.blue,
                  ),
                ),
              ),
            );

        // 마운트 시점부터 이미 사후구간 안 — initState에서 _wasInPostZone이
        // true로 시드돼야 한다.
        await pumpWith(_progress(
          inPostZone: true,
          distToNextCameraM: 20,
          nextCameraPostZoneM: 100,
        ));
        await tester.pump();
        expect(find.byType(CameraTransitionFlash), findsNothing);

        // 다음 GPS tick — 여전히 사후구간(값만 진행). didUpdateWidget에서
        // nowPost(true) && !_wasInPostZone이 성립하면 안 된다.
        await pumpWith(_progress(
          inPostZone: true,
          distToNextCameraM: 40,
          nextCameraPostZoneM: 100,
        ));
        await tester.pump();
        expect(find.byType(CameraTransitionFlash), findsNothing);
      },
    );

    testWidgets(
      '실제로 접근구간에서 사후구간으로 전환되는 순간엔 플래시가 뜬다',
      (tester) async {
        Future<void> pumpWith(RouteProgress p) => tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: RearCameraGaugeSwitcher(
                    progress: p,
                    speedKmh: 40,
                    firstFixReceived: true,
                    brandColor: Colors.blue,
                  ),
                ),
              ),
            );

        // 접근구간(0m 도달 전)으로 먼저 마운트.
        await pumpWith(_progress(inPostZone: false, distToNextCameraM: 5));
        await tester.pump();
        expect(find.byType(CameraTransitionFlash), findsNothing);

        // 0m 통과 — false→true 실제 전환이므로 플래시가 떠야 한다.
        await pumpWith(_progress(
          inPostZone: true,
          distToNextCameraM: 0,
          nextCameraPostZoneM: 100,
        ));
        await tester.pump();
        expect(find.byType(CameraTransitionFlash), findsOneWidget);
      },
    );
  });
}
