import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/tour_summary/tour_share_helper.dart';

void main() {
  group('centerHorizontalOffset', () {
    test('centers a narrower item inside a wider container', () {
      expect(centerHorizontalOffset(200, 100), 50.0);
    });

    test('returns 0 when the item fills the container exactly', () {
      expect(centerHorizontalOffset(150, 150), 0.0);
    });

    test('returns a negative offset when the item is wider than the container '
        '(caller is expected to just draw at that offset, no clamping/cropping)', () {
      expect(centerHorizontalOffset(100, 140), -20.0);
    });

    test('handles odd-pixel differences without throwing (fractional offset)', () {
      expect(centerHorizontalOffset(101, 100), 0.5);
    });
  });
}
