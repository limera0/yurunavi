import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:yurunavi/models/tour_log.dart';
import 'package:yurunavi/services/geocoding_service.dart';
import 'package:yurunavi/services/tour_log_service.dart';
import 'package:yurunavi/services/tour_recovery_service.dart';

/// 실제 SharedPreferences를 건드리지 않는 인메모리 스텁.
class _FakeTourLogService extends TourLogService {
  final List<TourLog> existing;
  final List<TourLog> saved = [];
  _FakeTourLogService([this.existing = const []]);

  @override
  Future<List<TourLog>> loadAll() async => existing;

  @override
  Future<void> add(TourLog log) async {
    saved.add(log);
  }
}

/// 실제 플랫폼 지오코더를 건드리지 않는 스텁 (항상 고정 문자열 반환).
class _FakeGeocodingService extends GeocodingService {
  @override
  Future<String?> reverseGeocode(double lat, double lng) async =>
      '가짜주소 $lat,$lng';
}

void main() {
  late Directory tempDir;
  late Directory toursDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tour_recovery_test_');
    toursDir = Directory('${tempDir.path}/tours');
    await toursDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const dist = Distance();
  const base = LatLng(37.0, 127.0);

  Future<File> writeTrack(String id, List<List<num>> rows) async {
    final f = File('${toursDir.path}/tour_$id.jsonl');
    final buf = StringBuffer();
    for (final r in rows) {
      buf.writeln(jsonEncode(r));
    }
    await f.writeAsString(buf.toString());
    return f;
  }

  group('TourRecoveryService — 정상 고아 파일 복구', () {
    test('임계값 이상의 고아 트랙은 요약이 계산되어 저장된다', () async {
      const id = '1234567890';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);

      // 시작점(속도 0) + 10회, 30초/500m 간격, 60km/h 등속.
      final points = <List<num>>[
        [startedAt.millisecondsSinceEpoch, base.latitude, base.longitude, 0],
      ];
      var pos = base;
      for (var i = 1; i <= 10; i++) {
        pos = dist.offset(pos, 500, 90);
        final t = startedAt.add(Duration(seconds: i * 30));
        points.add([t.millisecondsSinceEpoch, pos.latitude, pos.longitude, 60.0]);
      }
      final file = await writeTrack(id, points);

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved.length, 1);
      final log = fakeLogs.saved.first;
      expect(log.id, id);
      expect(log.durationS, 300);
      expect(log.distanceM, closeTo(5000, 50));
      expect(log.maxSpeedKmh, 60.0);
      expect(log.avgSpeedKmh, closeTo(60.0, 1.0));
      expect(log.trackFilePath, file.path);
      expect(log.memo, '비정상 종료로 자동 복구됨');
      expect(log.startAddress, isNotNull);
      expect(log.endAddress, isNotNull);
      // 트랙 파일 자체는 삭제하지 않는다 (trackFilePath가 계속 가리켜야 함).
      expect(await file.exists(), isTrue);
    });
  });

  group('TourRecoveryService — 굽은 경로(지그재그) 근사치 문서화', () {
    test('sparse chord-sum은 연속 곡선을 따라간 실제 길이보다 적게 나온다 (coarse approximation)',
        () async {
      const id = '2468';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);

      // 25m 간격으로 60°/120°(90° 기준 ±30°)를 번갈아 가며 20 스텝 진행하는
      // "조밀한" 지그재그 경로를 만든다. 이 20 스텝을 모두 이어 붙인
      // 길이(연속적으로 곡선을 따라갔을 때의 실제 경로 길이)는 정확히
      // 20 * 25m = 500m다.
      const stepM = 25.0;
      const totalSteps = 20;
      const denseTruePathLengthM = stepM * totalSteps; // 500m
      final densePoints = <LatLng>[base];
      var cursor = base;
      for (var i = 1; i <= totalSteps; i++) {
        final bearing = i.isOdd ? 60.0 : 120.0;
        cursor = dist.offset(cursor, stepM, bearing);
        densePoints.add(cursor);
      }

      // TourRecorder의 트랙 채택 게이트를 흉내내어, 조밀한 포인트 4개마다
      // 1개만 실제로 파일(.jsonl)에 남는다고 가정한다 — 실제 게이트는
      // 20m 이동 또는 8초+3m 기준이지만, 여기서는 "다운샘플되어 굽은 구간이
      // 잘려나간다"는 사실 자체가 요점이다.
      const keepEvery = 4;
      final sparsePoints = <LatLng>[
        for (var i = 0; i <= totalSteps; i += keepEvery) densePoints[i],
      ];

      // 서비스가 실제로 계산할 chord-sum을 동일한 Distance 공식으로 미리
      // 계산해둔다 — 이것이 "hand-computed" 기대값이다.
      var expectedChordSumM = 0.0;
      for (var i = 1; i < sparsePoints.length; i++) {
        expectedChordSumM +=
            dist.as(LengthUnit.Meter, sparsePoints[i - 1], sparsePoints[i]);
      }
      // 지그재그이므로 삼각부등식에 의해 sparse chord-sum은 dense 경로를
      // 연속으로 따라간 실제 길이(500m)보다 뚜렷하게(계산상 대략 433m) 짧다.
      expect(expectedChordSumM, lessThan(450));

      final rows = <List<num>>[];
      for (var i = 0; i < sparsePoints.length; i++) {
        final t = startedAt.add(Duration(seconds: i * 15));
        final p = sparsePoints[i];
        rows.add([t.millisecondsSinceEpoch, p.latitude, p.longitude, 40.0]);
      }
      final file = await writeTrack(id, rows);

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved.length, 1);
      final log = fakeLogs.saved.first;
      // 서비스가 계산한 distanceM은 sparse 포인트 간 chord-sum과 정확히
      // 일치해야 한다 — 거리 알고리즘이 바뀌면 이 assert가 깨져 감지된다.
      expect(log.distanceM, closeTo(expectedChordSumM, 0.01));
      // 그리고 이 값은 지그재그를 연속으로 따라간 실제 경로(500m)보다
      // 뚜렷하게 짧다 — 이것이 이 서비스의 "성긴 근사"(coarse approximation)
      // 특성이며, 위 직선(동쪽 일직선) 테스트(chord-sum == 실제 경로)와
      // 대비된다.
      expect(log.distanceM, lessThan(denseTruePathLengthM));
      expect(await file.exists(), isTrue);
    });
  });

  group('TourRecoveryService — 임계값 미달', () {
    test('시간/거리 기준 미달 고아 파일은 삭제되고 저장되지 않는다', () async {
      const id = '999';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      final points = [
        [startedAt.millisecondsSinceEpoch, base.latitude, base.longitude, 0],
        [
          startedAt.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
          base.latitude,
          base.longitude,
          5.0,
        ],
      ];
      final file = await writeTrack(id, points);

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved, isEmpty);
      expect(await file.exists(), isFalse);
    });
  });

  group('TourRecoveryService — 이미 저장된 id', () {
    test('이미 TourLogService에 있는 id의 파일은 재처리되지도, 삭제되지도 않는다', () async {
      const id = '555';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      final points = [
        [startedAt.millisecondsSinceEpoch, base.latitude, base.longitude, 0],
        [
          startedAt.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
          base.latitude + 0.01,
          base.longitude,
          40.0,
        ],
      ];
      final file = await writeTrack(id, points);

      final existing = TourLog(
        id: id,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 5)),
        startLat: base.latitude,
        startLng: base.longitude,
        endLat: base.latitude,
        endLng: base.longitude,
        distanceM: 1000,
        durationS: 300,
        avgSpeedKmh: 12,
        maxSpeedKmh: 40,
        trackFilePath: file.path,
      );

      final fakeLogs = _FakeTourLogService([existing]);
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved, isEmpty); // add()가 호출되지 않음 — 재처리 안 함
      expect(await file.exists(), isTrue); // 삭제도 안 함
    });
  });

  group('TourRecoveryService — 손상된 라인 방어', () {
    test('일부 라인이 깨져 있어도 남은 유효한 포인트로 복구된다', () async {
      const id = '777';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      final endPos = dist.offset(base, 1000, 90);
      final endedAt = startedAt.add(const Duration(seconds: 120));

      final f = File('${toursDir.path}/tour_$id.jsonl');
      final content = [
        jsonEncode([startedAt.millisecondsSinceEpoch, base.latitude, base.longitude, 0]),
        '{"garbage": true, incomplete', // 손상된 라인 (kill 도중 partial write)
        jsonEncode([endedAt.millisecondsSinceEpoch, endPos.latitude, endPos.longitude, 50.0]),
        '', // 후행 빈 줄
      ].join('\n');
      await f.writeAsString(content);

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved.length, 1);
      final log = fakeLogs.saved.first;
      expect(log.id, id);
      expect(log.durationS, 120);
      expect(log.distanceM, closeTo(1000, 5));
      expect(log.maxSpeedKmh, 50.0);
    });
  });

  group('TourRecoveryService — 복구할 것이 없는 통상 케이스', () {
    test('tours 디렉터리가 없으면 조용히 반환한다', () async {
      final emptyBase = await Directory.systemTemp.createTemp('tour_recovery_empty_');
      addTearDown(() async {
        if (await emptyBase.exists()) await emptyBase.delete(recursive: true);
      });

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: emptyBase);

      expect(fakeLogs.saved, isEmpty);
    });

    test('1개 포인트뿐인 고아 파일은 삭제되고 저장되지 않는다', () async {
      const id = '111';
      final startedAt = DateTime(2026, 1, 1, 9, 0, 0);
      final file = await writeTrack(id, [
        [startedAt.millisecondsSinceEpoch, base.latitude, base.longitude, 0],
      ]);

      final fakeLogs = _FakeTourLogService();
      final service = TourRecoveryService(
        tourLogService: fakeLogs,
        geocodingService: _FakeGeocodingService(),
      );

      await service.recoverOrphans(baseDirOverride: tempDir);

      expect(fakeLogs.saved, isEmpty);
      expect(await file.exists(), isFalse);
    });
  });
}
