// S5 — 정차 모드 상태머신(StationaryDetector) 단위 테스트.
//
// HANDOFF_0807_S5_stationary_mode.md 검증 요구 ①~④를 그대로 커버한다.
// 실제 Timer/sleep 대신 주입 가능한 clock으로 가짜 시간을 진행시킨다
// (StationaryDetector 자체가 실시각 대신 clock 콜백을 받도록 설계됨).
import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/providers/stationary_detector.dart';

/// 테스트에서 수동으로 진행시키는 가짜 시계.
class _FakeClock {
  DateTime _now = DateTime(2026, 8, 7, 12, 0, 0);
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  group('StationaryDetector', () {
    late _FakeClock clock;
    late StationaryDetector detector;

    setUp(() {
      clock = _FakeClock();
      detector = StationaryDetector(clock: clock.call);
    });

    test('① 5km/h 미만이 10초 미만 지속 — 아직 미진입', () {
      expect(detector.feed(3.0), isFalse);
      clock.advance(const Duration(seconds: 9, milliseconds: 900));
      expect(detector.feed(3.0), isFalse);
      expect(detector.isStationary, isFalse);
    });

    test('② 10초 도달 — 정차 모드 진입', () {
      expect(detector.feed(3.0), isFalse);
      clock.advance(const Duration(seconds: 10));
      expect(detector.feed(3.0), isTrue);
      expect(detector.isStationary, isTrue);
    });

    test('③ 진입 후 속도 5km/h 이상 단발 — 지연 없이 즉시 해제', () {
      detector.feed(2.0);
      clock.advance(const Duration(seconds: 10));
      expect(detector.feed(2.0), isTrue, reason: '정차 모드 진입 전제조건');

      // 단 한 번의 회복 fix만으로 같은 호출에서 즉시 false여야 한다
      // (다음 틱까지 기다릴 필요 없음 — 지연 없는 해제).
      expect(detector.feed(6.0), isFalse);
      expect(detector.isStationary, isFalse);
    });

    test('④-a 경계값: 정확히 5km/h는 "미만"이 아니므로 카운트에 들어가지 않는다', () {
      expect(detector.feed(3.0), isFalse);
      clock.advance(const Duration(seconds: 9));
      // 9초 시점에 정확히 5.0km/h fix — 임계값 미만이 아니므로 리셋.
      expect(detector.feed(5.0), isFalse);

      // 리셋 이후 다시 저속으로 9.9초만 지속 — 아직 미진입이어야 한다
      // (5.0km/h 시점에서 카운트가 이어졌다면 여기서 잘못 진입한다).
      clock.advance(const Duration(seconds: 9, milliseconds: 900));
      expect(detector.feed(3.0), isFalse);
    });

    test('④-b 경계값: 정확히 10.0초 경과 시점에 진입(경계 포함, ">=")', () {
      detector.feed(1.0);
      clock.advance(const Duration(seconds: 10));
      // 정확히 10.000초 — sustainDuration과 동일 시점이므로 진입해야 한다.
      expect(detector.feed(1.0), isTrue);
    });

    test('9.999초 시점에는 아직 진입하지 않는다(경계 바로 아래)', () {
      detector.feed(1.0);
      clock.advance(const Duration(seconds: 9, milliseconds: 999));
      expect(detector.feed(1.0), isFalse);
    });

    test('임계값 이상으로 계속 유지되면 isStationary는 항상 false', () {
      for (var i = 0; i < 5; i++) {
        clock.advance(const Duration(seconds: 3));
        expect(detector.feed(30.0), isFalse);
      }
    });

    test('진입 후 재정차(속도 회복→재하락)는 10초 지속을 처음부터 다시 요구한다', () {
      detector.feed(2.0);
      clock.advance(const Duration(seconds: 10));
      expect(detector.feed(2.0), isTrue);

      // 잠깐 회복(즉시 해제) → 곧바로 다시 저속.
      expect(detector.feed(6.0), isFalse);
      expect(detector.feed(2.0), isFalse, reason: '재진입은 다시 10초를 기다려야 한다');

      clock.advance(const Duration(seconds: 9, milliseconds: 900));
      expect(detector.feed(2.0), isFalse);

      clock.advance(const Duration(milliseconds: 100));
      expect(detector.feed(2.0), isTrue);
    });

    test('기본 임계값은 5.0km/h · 10초', () {
      final d = StationaryDetector();
      expect(d.thresholdKmh, 5.0);
      expect(d.sustainDuration, const Duration(seconds: 10));
    });
  });
}
