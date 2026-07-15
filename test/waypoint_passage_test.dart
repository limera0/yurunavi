import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/navigation/presentation/nav_screen.dart';

void main() {
  group('waypointPassageEvent — 경유지 도착/통과 판정', () {
    test('지오펜스 내 정차 → 즉시 도착, closestDistM 리셋', () {
      final r = waypointPassageEvent(
          distM: 15, speedKmh: 3, closestDistM: null);
      expect(r.event, WaypointPassageEvent.arrived);
      expect(r.closestDistM, isNull);
    });

    test('지오펜스 밖 + 추적 이력 없음 → 아무 일도 없음 (접근 전)', () {
      final r = waypointPassageEvent(
          distM: 500, speedKmh: 60, closestDistM: null);
      expect(r.event, WaypointPassageEvent.none);
      expect(r.closestDistM, isNull);
    });

    test('지오펜스 진입(주행 중) → 통과 처리 대신 최근접 거리만 기록', () {
      final r = waypointPassageEvent(
          distM: 35, speedKmh: 40, closestDistM: null);
      expect(r.event, WaypointPassageEvent.none);
      expect(r.closestDistM, 35);
    });

    test('계속 가까워짐 → 최근접 거리 갱신, 이벤트 없음', () {
      final r = waypointPassageEvent(
          distM: 12, speedKmh: 40, closestDistM: 35);
      expect(r.event, WaypointPassageEvent.none);
      expect(r.closestDistM, 12);
    });

    test('최근접점 지나 약간 멀어짐(margin 미만) → 아직 통과 아님, 최근접값 유지', () {
      final r = waypointPassageEvent(
          distM: 18, speedKmh: 40, closestDistM: 12, passedMarginM: 10);
      expect(r.event, WaypointPassageEvent.none);
      expect(r.closestDistM, 12); // 최근접값 그대로 보존
    });

    test('최근접점보다 margin 이상 멀어짐 → 통과, closestDistM 리셋', () {
      final r = waypointPassageEvent(
          distM: 23, speedKmh: 40, closestDistM: 12, passedMarginM: 10);
      expect(r.event, WaypointPassageEvent.passed);
      expect(r.closestDistM, isNull);
    });

    test('경계값: 정확히 margin만큼 멀어짐 → 통과 (포함)', () {
      final r = waypointPassageEvent(
          distM: 22, speedKmh: 40, closestDistM: 12, passedMarginM: 10);
      expect(r.event, WaypointPassageEvent.passed);
    });

    test('커스텀 임계값 적용', () {
      final r = waypointPassageEvent(
        distM: 45,
        speedKmh: 5,
        closestDistM: null,
        arrivalM: 50,
        stopSpeedKmh: 10,
      );
      expect(r.event, WaypointPassageEvent.arrived);
    });

    test('실제 접근→통과 시퀀스 시뮬레이션 (2026-07-15 밤 라이딩 회귀 가드)', () {
      // 정차 없이 경유지를 그대로 지나치는 라이더 — 지오펜스에 들어서는
      // 순간 바로 "통과"가 나가면 안 되고, 최근접점을 지나 10m 더
      // 전진한 뒤에야 나가야 한다.
      double? closest;
      final events = <WaypointPassageEvent>[];
      // 접근: 200m → 60m(아직 지오펜스 밖) → 35m(진입) → 8m(최근접) →
      // 14m → 22m(최근접+10 이상 못미침, 8+10=18이므로 22는 통과 조건 충족)
      for (final d in [200.0, 60.0, 35.0, 8.0, 14.0, 22.0]) {
        final r = waypointPassageEvent(
            distM: d, speedKmh: 45, closestDistM: closest);
        closest = r.closestDistM;
        events.add(r.event);
      }
      // 접근 구간에서는 도착/통과 이벤트가 전혀 나가면 안 됨.
      expect(events.sublist(0, 5), everyElement(WaypointPassageEvent.none));
      // 최근접점(8m)에서 10m 이상 멀어진 마지막 지점에서만 통과.
      expect(events.last, WaypointPassageEvent.passed);
    });
  });
}
