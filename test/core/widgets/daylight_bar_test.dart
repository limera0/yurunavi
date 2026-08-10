import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/core/theme/app_theme.dart';
import 'package:yurunavi/core/widgets/daylight_bar.dart';

// 회귀 대상: num.clamp(lower, upper)는 upper < lower면 ArgumentError를 던진다
// (실기기 YNAV_CRASH "Invalid argument(s): 0.0" 56,789건의 원인). DaylightBar가
// Positioned(top, bottom)처럼 가용 높이가 아주 작거나(핸들 24px, 게이지 최소치
// 미만) 0인 컨테이너 안에 들어갈 때도 절대 던지지 않아야 한다.
//
// 285px = 갤럭시 플립7 커버화면 논리높이 근사.
// 71/72/117은 분기 임계값(_kAbbrevMinH=72, _kFullRenderMinH=118)의 바로 양옆이다 —
// 임계값 자체를 옮기는 회귀가 나면 여기서 먼저 걸린다.
const _heights = <double>[0, 10, 24, 60, 71, 72, 90, 117, 118, 120, 285, 300, 800];
const _progresses = <double>[0.0, 0.5, 1.0];

Future<void> _pump(
  WidgetTester tester,
  double height,
  double progress, {
  bool? isNightMode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height, minHeight: 0),
            child: DaylightBar(
              progress: progress,
              sunriseLabel: '06:00',
              sunsetLabel: '19:00',
              isNightMode: isNightMode,
            ),
          ),
        ),
      ),
    ),
  );
}

// 알약(pill) 배경 Container를 찾는다 — width:38 + BoxDecoration 조합은
// DaylightBar 트리 안에서 이 컨테이너 하나뿐이다(게이지 레일은 width:6).
Finder _pillContainerFinder() => find.byWidgetPredicate((widget) =>
    widget is Container &&
    widget.constraints?.maxWidth == 38 &&
    widget.decoration is BoxDecoration);

void main() {
  for (final h in _heights) {
    for (final p in _progresses) {
      testWidgets(
        'height=${h}px progress=$p never throws',
        (tester) async {
          await _pump(tester, h, p);
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'abbreviated branch (90px): time labels are absent',
    (tester) async {
      await _pump(tester, 90, 0.5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('06:00'), findsNothing);
      expect(find.text('19:00'), findsNothing);
    },
  );

  testWidgets(
    'full-render branch (300px): time labels are present',
    (tester) async {
      await _pump(tester, 300, 0.5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('06:00'), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
    },
  );

  testWidgets(
    'below abbreviation floor (24px): renders nothing (SizedBox.shrink)',
    (tester) async {
      await _pump(tester, 24, 0.5);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('06:00'), findsNothing);
      expect(find.text('19:00'), findsNothing);
      // 아이콘도 그려지지 않는다 — 완전히 빈 위젯이어야 한다.
      expect(find.byType(Icon), findsNothing);
    },
  );

  // S14 ② — 야간 색상 반전 회귀 테스트
  group('S14 night-mode color inversion', () {
    testWidgets(
      'isNightMode=true: pill background is daylightNightBg',
      (tester) async {
        await _pump(tester, 300, 0.5, isNightMode: true);
        await tester.pump();
        expect(tester.takeException(), isNull);

        final pill = tester.widget<Container>(_pillContainerFinder());
        final decoration = pill.decoration as BoxDecoration;
        expect(
          decoration.color,
          AppColors.daylightNightBg.withValues(alpha: 0.95),
        );
      },
    );

    testWidgets(
      'isNightMode=false: pill background is daylightDayBg',
      (tester) async {
        await _pump(tester, 300, 0.5, isNightMode: false);
        await tester.pump();
        expect(tester.takeException(), isNull);

        final pill = tester.widget<Container>(_pillContainerFinder());
        final decoration = pill.decoration as BoxDecoration;
        expect(
          decoration.color,
          AppColors.daylightDayBg.withValues(alpha: 0.95),
        );
      },
    );

    testWidgets(
      'night pill color differs from day pill color',
      (tester) async {
        await _pump(tester, 300, 0.5, isNightMode: true);
        await tester.pump();
        final nightPill = tester.widget<Container>(_pillContainerFinder());
        final nightColor = (nightPill.decoration as BoxDecoration).color;

        await _pump(tester, 300, 0.5, isNightMode: false);
        await tester.pump();
        final dayPill = tester.widget<Container>(_pillContainerFinder());
        final dayColor = (dayPill.decoration as BoxDecoration).color;

        expect(nightColor, isNot(equals(dayColor)));
      },
    );
  });
}
