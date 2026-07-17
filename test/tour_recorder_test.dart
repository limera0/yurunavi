import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:yurunavi/features/navigation/tour_recorder.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tour_recorder_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const base = LatLng(37.0, 127.0);
  const dist = Distance();

  group('TourRecorder — 거리/평균속도', () {
    test('정속 주행 시 거리·평균속도가 참조값(약 65.1km/80분 → 48~49km/h)에 근접한다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      // 65.1km / (4800s/3600) = 48.825km/h. 거리 적분은 speed*time 기반이라
      // 위치는 고정값을 재사용해도 무방하다(onFix의 거리 적분 로직 참고).
      const speedKmh = 48.825;
      var t = startedAt;
      for (var elapsed = 2; elapsed <= 4800; elapsed += 2) {
        t = startedAt.add(Duration(seconds: elapsed));
        recorder.onFix(base, speedKmh, t);
      }

      final log = await recorder.finish(base, t);

      expect(log, isNotNull);
      expect(log!.durationS, 4800);
      expect(log.distanceM, closeTo(65100, 50));
      expect(log.avgSpeedKmh, inInclusiveRange(48.0, 49.0));
    });
  });

  group('TourRecorder — 최고속도', () {
    test('가변 속도 시퀀스 중 최고값을 정확히 캡처한다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      final speeds = [30.0, 80.0, 45.0, 120.0, 20.0, 65.0];
      var t = startedAt;
      for (var i = 0; i < speeds.length; i++) {
        t = startedAt.add(Duration(seconds: (i + 1) * 2));
        recorder.onFix(base, speeds[i], t);
      }

      final log = await recorder.finish(
        base,
        t,
        minDurationS: 0,
        minDistanceM: 0,
      );

      expect(log, isNotNull);
      expect(log!.maxSpeedKmh, 120.0);
    });
  });

  group('TourRecorder — 트랙 포인트 채택 게이트', () {
    test('5m/2초 간격 fix는 대부분 기각되고 누적 임계 통과 시에만 채택된다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      var pos = base;
      var t = startedAt;
      const ticks = 16; // 4틱(8초)마다 1회 채택 예상 → 4회 채택
      for (var i = 1; i <= ticks; i++) {
        pos = dist.offset(pos, 5, 0);
        t = startedAt.add(Duration(seconds: i * 2));
        recorder.onFix(pos, 9.0, t); // 5m/2s ≈ 9km/h, 현실적인 속도
      }

      final log = await recorder.finish(
        pos,
        t,
        minDurationS: 0,
        minDistanceM: 0,
      );
      expect(log, isNotNull);

      final lines = await File(log!.trackFilePath).readAsLines();
      // 시작점(1) + 4회 채택 = 5줄
      expect(lines.length, 5);
    });

    test('25m 간격 fix는 매 fix가 모두 채택된다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      var pos = base;
      var t = startedAt;
      const ticks = 5;
      for (var i = 1; i <= ticks; i++) {
        pos = dist.offset(pos, 25, 0);
        t = startedAt.add(Duration(seconds: i * 2));
        recorder.onFix(pos, 45.0, t); // 25m/2s = 12.5m/s = 45km/h
      }

      final log = await recorder.finish(
        pos,
        t,
        minDurationS: 0,
        minDistanceM: 0,
      );
      expect(log, isNotNull);

      final lines = await File(log!.trackFilePath).readAsLines();
      // 시작점(1) + 5회 모두 채택 = 6줄
      expect(lines.length, 6);
    });
  });

  group('TourRecorder — jump guard', () {
    test('200km/h 초과를 시사하는 튐(noise) fix는 트랙에 기록되지 않고, 이후 정상 fix는 정상 채택된다',
        () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      // 노이즈 fix: 1초 만에 1km 이동한 것으로 보임(3600km/h 시사) → 기각, 기준점 갱신 없음.
      final noisyPos = dist.offset(base, 1000, 0);
      final tNoise = startedAt.add(const Duration(seconds: 1));
      recorder.onFix(noisyPos, 50.0, tNoise);

      // 이어지는 정상 fix: 기준점이 여전히 시작점이므로 시작점 기준 25m 이동.
      final normalPos = dist.offset(base, 25, 0);
      final tNormal = startedAt.add(const Duration(seconds: 3));
      recorder.onFix(normalPos, 45.0, tNormal);

      final log = await recorder.finish(
        normalPos,
        tNormal,
        minDurationS: 0,
        minDistanceM: 0,
      );
      expect(log, isNotNull);

      final lines = await File(log!.trackFilePath).readAsLines();
      // 시작점(1) + 정상 fix 채택(1) = 2줄 (노이즈는 기록되지 않음)
      expect(lines.length, 2);
    });
  });

  group('TourRecorder — finish() 최소 기준', () {
    test('기준 미달(시간/거리)이면 null을 반환하고 트랙 파일도 삭제된다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      final endedAt = startedAt.add(const Duration(seconds: 30)); // < 60s 기준
      recorder.onFix(base, 10.0, endedAt);

      final path = recorder.trackFilePath;
      expect(path, isNotNull);
      expect(await File(path!).exists(), isTrue);

      final log = await recorder.finish(base, endedAt);

      expect(log, isNull);
      expect(await File(path).exists(), isFalse);
    });

    test('기준을 만족하면 TourLog를 반환하고 필드가 올바르게 채워진다', () async {
      final recorder = TourRecorder();
      final startedAt = DateTime(2026, 2, 1, 8, 0, 0);
      await recorder.start(base, startedAt, baseDirOverride: tempDir);

      // 틱 간격은 onFix의 dt clamp(최대 3초)를 넘지 않도록 2초로 유지한다.
      const speedKmh = 60.0;
      var t = startedAt;
      for (var elapsed = 2; elapsed <= 600; elapsed += 2) {
        t = startedAt.add(Duration(seconds: elapsed));
        recorder.onFix(base, speedKmh, t);
      }
      final endPos = dist.offset(base, 500, 90);

      final log = await recorder.finish(endPos, t);

      expect(log, isNotNull);
      expect(log!.id, startedAt.millisecondsSinceEpoch.toString());
      expect(log.durationS, 600);
      expect(log.distanceM, closeTo(60 / 3.6 * 600, 1));
      expect(log.avgSpeedKmh, closeTo(60.0, 0.5));
      expect(log.maxSpeedKmh, 60.0);
      expect(log.trackFilePath, isNotEmpty);
      expect(await File(log.trackFilePath).exists(), isTrue);
      expect(log.startAddress, isNull);
      expect(log.endAddress, isNull);
      expect(log.memo, isNull);
    });
  });
}
