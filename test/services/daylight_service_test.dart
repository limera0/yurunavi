import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/services/daylight_service.dart';

// S14 회귀 테스트 — cycleState() 밤 분기 버그(daylight_service.dart:170 nextBmnt
// ±24h 근사 오류) 재발 방지. sunrise_sunset_calc의 실제 결과값(calculate())을
// 직접 조회해 그 값 기준으로 now를 구성한다 — 절기별 일출/일몰 시각을
// 하드코딩하지 않는다.
//
// 좌표 선택 참고: DaylightService._localCalc()는 `DateTime.timeZoneOffset`
// (테스트를 실행하는 호스트 시스템의 타임존)을 그대로 태양 계산의 UTC
// 오프셋으로 사용한다. 실기기는 항상 한국 표준시라 위도/경도(서울)와 오프셋이
// 맞아떨어지지만, 이 저장소에는 TZ 고정 CI가 없어 테스트 호스트가 UTC 등
// 다른 타임존일 수 있다 — 그 경우 서울 경도(126.98)와 호스트 오프셋이
// 어긋나 일출이 자정 근처로 퇴화(wrap)하는 결과가 나올 수 있다. 위도는 서울
// 값을 유지하되(계절별 낮 길이는 현실적으로 유지) 경도만 호스트 오프셋에
// 맞춰 동적으로 선택해, 어떤 호스트에서 실행하더라도 정상적인 주야 패턴이
// 나오도록 한다.
final double _lat = 37.5665;
final double _lng = (DateTime.now().timeZoneOffset.inMinutes / 60.0 * 15.0)
    .clamp(-179.0, 179.0);

void main() {
  group('DaylightService.cycleState — 낮', () {
    test('정오 근처: isDay=true, progress는 이른 시각보다 늦은 시각에 더 크다', () {
      final date = DateTime(2026, 6, 15);
      final today =
          DaylightService.calculate(lat: _lat, lng: _lng, date: date);

      final earlier = today.bmnt.add(const Duration(hours: 1));
      final later = today.bmnt.add(const Duration(hours: 3));

      final earlierState =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: earlier);
      final laterState =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: later);

      expect(earlierState.isDay, isTrue);
      expect(laterState.isDay, isTrue);
      expect(laterState.progress, greaterThan(earlierState.progress));
      expect(earlierState.progress, inInclusiveRange(0.0, 1.0));
      expect(laterState.progress, inInclusiveRange(0.0, 1.0));
    });
  });

  group('DaylightService.cycleState — 일몰 직후', () {
    test('일몰 몇 분 뒤: isDay=false, progress는 0에 가까운 작은 값', () {
      final date = DateTime(2026, 6, 15);
      final today =
          DaylightService.calculate(lat: _lat, lng: _lng, date: date);

      final now = today.eent.add(const Duration(minutes: 5));
      final state =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: now);

      expect(state.isDay, isFalse);
      expect(state.progress, lessThan(0.1));
      expect(state.progress, greaterThanOrEqualTo(0.0));
    });
  });

  group('DaylightService.cycleState — 자정 전후 연속성 (S14 회귀)', () {
    test('23:59와 익일 00:01(10분 차) 사이 progress가 크게 역행하지 않는다', () {
      final date = DateTime(2026, 6, 15);
      final today =
          DaylightService.calculate(lat: _lat, lng: _lng, date: date);
      final nextDay = DaylightService.calculate(
        lat: _lat,
        lng: _lng,
        date: date.add(const Duration(days: 1)),
      );

      // 자정을 사이에 둔 두 시각을 오늘 일몰 기준으로 상대 구성한다.
      final midnight = DateTime(date.year, date.month, date.day + 1); // 00:00
      final before = midnight.subtract(const Duration(minutes: 1)); // 23:59
      final after = midnight.add(const Duration(minutes: 1)); // 00:01

      final beforeState =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: before);
      final afterState =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: after);

      expect(beforeState.isDay, isFalse);
      expect(afterState.isDay, isFalse);

      // 버그 이전: 자정 넘는 순간 분모가 34h로 튀어 progress가 크게 하락했다.
      // 수정 후에는 시간이 흐른 만큼만(10분치) 이동해야 한다 — 큰 역행 금지.
      expect(afterState.progress,
          greaterThanOrEqualTo(beforeState.progress - 0.02));

      // 야간 구간의 논리적 경계(topTime=일몰, bottomTime=일출)가 여러 날치
      // 근사가 아니라 실제 전일 일몰/오늘 일출, 오늘 일몰/익일 일출로 유지된다.
      expect(beforeState.topTime, today.eent);
      expect(beforeState.bottomTime, nextDay.bmnt);
      expect(afterState.topTime, today.eent);
      expect(afterState.bottomTime, nextDay.bmnt);
    });
  });

  group('DaylightService.cycleState — 일출 직전 (S14 제보 케이스)', () {
    test('오늘 일출 몇 분 전: isDay=false, progress는 1.0에 가까운 큰 값', () {
      final date = DateTime(2026, 6, 15);
      final today =
          DaylightService.calculate(lat: _lat, lng: _lng, date: date);

      final now = today.bmnt.subtract(const Duration(minutes: 5));
      final state =
          DaylightService.cycleState(lat: _lat, lng: _lng, now: now);

      expect(state.isDay, isFalse);
      expect(state.progress, greaterThan(0.9));
      expect(state.progress, lessThanOrEqualTo(1.0));
      expect(state.bottomTime, today.bmnt);
    });
  });
}
