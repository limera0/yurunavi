import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<void> _pump(WidgetTester tester, double height, double progress) async {
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
            ),
          ),
        ),
      ),
    ),
  );
}

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
}
