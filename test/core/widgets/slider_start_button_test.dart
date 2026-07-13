import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slider_button/slider_button.dart';
import 'package:yurunavi/core/widgets/slider_start_button.dart';

void main() {
  testWidgets(
    'SliderButton receives a finite width (not double.infinity) so the '
    'drag-to-confirm zone matches the visible track',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: SliderStartButton(onSlideComplete: () {}),
            ),
          ),
        ),
      );

      final sliderButton = tester.widget<SliderButton>(
        find.byType(SliderButton),
      );

      expect(sliderButton.width.isFinite, isTrue);
      expect(sliderButton.width, isNot(double.infinity));
    },
  );
}
