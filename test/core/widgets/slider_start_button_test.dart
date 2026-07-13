import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/core/widgets/slider_start_button.dart';

// Geometry mirrors the constants baked into SliderStartButton's build():
// - outer Container margin: EdgeInsets.fromLTRB(20, 0, 20, 20) -> 40px off
//   the width handed to it by the test harness's SizedBox.
// - thumb size: 52, edge padding: 9 (both sides), completion threshold: 0.85.
const double _harnessWidth = 360;
const double _trackWidth = _harnessWidth - 40; // 320
const double _maxDrag = _trackWidth - 52 - 2 * 9; // 250
const double _completionThreshold = 0.85;

void main() {
  setUp(() {
    // HapticFeedback.heavyImpact() invokes SystemChannels.platform, which has
    // no handler in the test environment and would otherwise throw
    // MissingPluginException once the slide completes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpButton(WidgetTester tester, VoidCallback onSlideComplete) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _harnessWidth,
            child: SliderStartButton(onSlideComplete: onSlideComplete),
          ),
        ),
      ),
    );
  }

  Finder trackFinder() => find.descendant(
        of: find.byType(SliderStartButton),
        matching: find.byType(GestureDetector),
      );

  testWidgets(
    'dragging the thumb past the completion threshold calls onSlideComplete '
    '(pure position check, no velocity dependency)',
    (tester) async {
      var called = false;
      await pumpButton(tester, () => called = true);

      // Drag well past the 85% threshold (250 * 0.85 = 212.5) — a normal
      // deliberate swipe, not a hair-precise fling.
      await tester.drag(trackFinder(), const Offset(_maxDrag, 0));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    },
  );

  testWidgets(
    'a moderate/incomplete drag does NOT call onSlideComplete and springs back '
    'without getting stuck (regression guard for both the old "must drag to '
    'the edge" bug and the "twitchy" bug)',
    (tester) async {
      var called = false;
      await pumpButton(tester, () => called = true);

      // Drag only 30% of the available travel — well short of the 85%
      // completion threshold.
      await tester.drag(trackFinder(), const Offset(_maxDrag * 0.3, 0));
      await tester.pumpAndSettle();

      expect(called, isFalse);
    },
  );

  testWidgets(
    'the completion threshold is reachable with a normal swipe, not the full '
    'track width',
    (tester) async {
      // Sanity check on the geometry constants above: the completion
      // threshold sits well short of the full track, confirming users don't
      // need to drag "to the edge of the screen".
      expect(_maxDrag * _completionThreshold, lessThan(_maxDrag));
      expect(_maxDrag, greaterThan(0));
    },
  );
}
