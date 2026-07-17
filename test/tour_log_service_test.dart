import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yurunavi/models/tour_log.dart';
import 'package:yurunavi/services/tour_log_service.dart';

TourLog _log({
  required String id,
  required DateTime startedAt,
  String trackFilePath = '/tmp/does_not_exist.jsonl',
  String? memo,
}) {
  return TourLog(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(hours: 1)),
    startLat: 37.0,
    startLng: 127.0,
    endLat: 37.1,
    endLng: 127.1,
    distanceM: 20000,
    durationS: 3600,
    avgSpeedKmh: 20.0,
    maxSpeedKmh: 80.0,
    trackFilePath: trackFilePath,
    memo: memo,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TourLogService.add / loadAll', () {
    test('add() 후 loadAll()이 해당 항목을 반환한다', () async {
      final service = TourLogService();
      final log = _log(id: '1', startedAt: DateTime(2026, 7, 1));

      await service.add(log);
      final all = await service.loadAll();

      expect(all.length, 1);
      expect(all.first.id, '1');
    });

    test('시간 순서와 무관하게 추가해도 loadAll()은 최신순(내림차순)으로 정렬한다', () async {
      final service = TourLogService();
      final older = _log(id: 'older', startedAt: DateTime(2026, 1, 1));
      final newest = _log(id: 'newest', startedAt: DateTime(2026, 7, 1));
      final middle = _log(id: 'middle', startedAt: DateTime(2026, 4, 1));

      // 일부러 시간순이 아닌 순서로 추가한다.
      await service.add(older);
      await service.add(newest);
      await service.add(middle);

      final all = await service.loadAll();

      expect(all.map((l) => l.id).toList(), ['newest', 'middle', 'older']);
    });
  });

  group('TourLogService.update', () {
    test('update()는 id가 일치하는 항목만 교체하고 나머지는 영향받지 않는다', () async {
      final service = TourLogService();
      final a = _log(id: 'a', startedAt: DateTime(2026, 1, 1));
      final b = _log(id: 'b', startedAt: DateTime(2026, 2, 1));
      await service.add(a);
      await service.add(b);

      final updatedA = a.copyWith(memo: '메모 추가됨');
      await service.update(updatedA);

      final all = await service.loadAll();
      final resultA = all.firstWhere((l) => l.id == 'a');
      final resultB = all.firstWhere((l) => l.id == 'b');

      expect(resultA.memo, '메모 추가됨');
      expect(resultB.memo, isNull);
      expect(all.length, 2);
    });
  });

  group('TourLogService.delete', () {
    test('delete()는 인덱스에서 항목을 제거하고 트랙 파일도 삭제한다', () async {
      final service = TourLogService();
      final tempDir = await Directory.systemTemp.createTemp('tour_log_test_');
      final trackFile = File('${tempDir.path}/track.jsonl');
      await trackFile.writeAsString('{"lat":37.0,"lng":127.0}\n');
      expect(await trackFile.exists(), isTrue);

      final log = _log(
        id: 'to-delete',
        startedAt: DateTime(2026, 1, 1),
        trackFilePath: trackFile.path,
      );
      await service.add(log);

      await service.delete('to-delete');

      final all = await service.loadAll();
      expect(all, isEmpty);
      expect(await trackFile.exists(), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('존재하지 않는 id를 delete()해도 예외 없이 안전하게 무시된다', () async {
      final service = TourLogService();
      final log = _log(id: 'kept', startedAt: DateTime(2026, 1, 1));
      await service.add(log);

      await service.delete('does-not-exist');

      final all = await service.loadAll();
      expect(all.length, 1);
      expect(all.first.id, 'kept');
    });
  });
}
