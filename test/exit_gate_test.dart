import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/presentation/nav_screen.dart';

void main() {
  group('exitGateOpen — 도착배너 종료버튼 지오펜스+속도 게이트', () {
    test('within geofence and under speed limit → open', () {
      expect(exitGateOpen(distanceM: 10, speedKmh: 5), isTrue);
    });

    test('exactly at both bounds → open (inclusive)', () {
      expect(exitGateOpen(distanceM: 30, speedKmh: 30), isTrue);
    });

    test('outside geofence → closed even at 0 speed', () {
      expect(exitGateOpen(distanceM: 31, speedKmh: 0), isFalse);
    });

    test('over speed limit → closed even right at destination', () {
      expect(exitGateOpen(distanceM: 0, speedKmh: 31), isFalse);
    });

    test('both violated → closed', () {
      expect(exitGateOpen(distanceM: 100, speedKmh: 60), isFalse);
    });

    test('custom thresholds override defaults', () {
      expect(
        exitGateOpen(distanceM: 40, speedKmh: 10, geofenceM: 50, speedLimitKmh: 20),
        isTrue,
      );
      expect(
        exitGateOpen(distanceM: 40, speedKmh: 10, geofenceM: 20, speedLimitKmh: 20),
        isFalse,
      );
    });
  });
}
