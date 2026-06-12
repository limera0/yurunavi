import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/domain/speed_kalman.dart';

void main() {
  group('SpeedKalman', () {
    test('initial state is zero', () {
      final kf = SpeedKalman();
      expect(kf.v, 0.0);
      expect(kf.b, 0.0);
      expect(kf.speedKmh, 0.0);
    });

    test('predict integrates acceleration into velocity', () {
      final kf = SpeedKalman();
      kf.predict(2.0, 0.5); // +1 m/s
      expect(kf.v, closeTo(1.0, 1e-9));
      kf.predict(2.0, 0.5);
      expect(kf.v, closeTo(2.0, 1e-9));
    });

    test('updateGps pulls velocity toward measurement', () {
      final kf = SpeedKalman();
      kf.predict(0.0, 1.0); // v stays 0, P grows
      kf.updateGps(10.0, 4.0);
      expect(kf.v, greaterThan(0.0));
      expect(kf.v, lessThan(10.0));
      // repeated consistent measurements converge near measurement.
      // The bias state can absorb a small steady-state residual, so the
      // estimate settles close to (but not exactly at) the measurement.
      for (var i = 0; i < 20; i++) {
        kf.predict(0.0, 1.0);
        kf.updateGps(10.0, 4.0);
      }
      expect(kf.v, closeTo(10.0, 2.5));
    });

    test('updateZupt forces velocity toward zero', () {
      final kf = SpeedKalman(v: 12.0, p00: 5.0);
      kf.updateZupt();
      expect(kf.v.abs(), lessThan(1.0));
    });

    test('speedKmh clamps to 75 m/s', () {
      final kf = SpeedKalman(v: 100.0);
      expect(kf.speedKmh, closeTo(75.0 * 3.6, 1e-9));
    });

    test('covariance stays finite over many steps', () {
      final kf = SpeedKalman();
      for (var i = 0; i < 1000; i++) {
        kf.predict(0.5, 0.02);
        if (i % 50 == 0) kf.updateGps(5.0, 4.0);
      }
      expect(kf.v.isFinite, isTrue);
      expect(kf.p00.isFinite, isTrue);
      expect(kf.p11.isFinite, isTrue);
    });
  });
}
