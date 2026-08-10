import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/models/tour_log.dart';

TourLog _log({
  String id = '1000',
  String? startAddress,
  String? endAddress,
  String? memo,
  String? resumedFromId,
}) {
  return TourLog(
    id: id,
    startedAt: DateTime(2026, 7, 17, 9, 0, 0),
    endedAt: DateTime(2026, 7, 17, 11, 30, 0),
    startLat: 37.5665,
    startLng: 126.9780,
    endLat: 37.4563,
    endLng: 126.7052,
    startAddress: startAddress,
    endAddress: endAddress,
    distanceM: 45230.5,
    durationS: 9000,
    avgSpeedKmh: 18.09,
    maxSpeedKmh: 102.3,
    trackFilePath: '/tmp/tracks/$id.jsonl',
    memo: memo,
    resumedFromId: resumedFromId,
  );
}

void main() {
  group('TourLog JSON round-trip', () {
    test('모든 필드를 왕복 직렬화한다 (nullable 필드가 non-null인 경우)', () {
      final log = _log(
        startAddress: '서울시청',
        endAddress: '인천대공원',
        memo: '좋은 라이딩이었다',
      );
      final restored = TourLog.fromJsonString(log.toJsonString());

      expect(restored.id, log.id);
      expect(restored.startedAt, log.startedAt);
      expect(restored.endedAt, log.endedAt);
      expect(restored.startLat, log.startLat);
      expect(restored.startLng, log.startLng);
      expect(restored.endLat, log.endLat);
      expect(restored.endLng, log.endLng);
      expect(restored.startAddress, log.startAddress);
      expect(restored.endAddress, log.endAddress);
      expect(restored.distanceM, log.distanceM);
      expect(restored.durationS, log.durationS);
      expect(restored.avgSpeedKmh, log.avgSpeedKmh);
      expect(restored.maxSpeedKmh, log.maxSpeedKmh);
      expect(restored.trackFilePath, log.trackFilePath);
      expect(restored.memo, log.memo);
    });

    test('nullable 필드(startAddress/endAddress/memo)가 null인 경우도 왕복한다', () {
      final log = _log();
      final restored = TourLog.fromJsonString(log.toJsonString());

      expect(restored.startAddress, isNull);
      expect(restored.endAddress, isNull);
      expect(restored.memo, isNull);
      expect(restored.resumedFromId, isNull);
      expect(restored.id, log.id);
      expect(restored.distanceM, log.distanceM);
    });

    test('resumedFromId가 non-null이면 왕복 직렬화된다', () {
      final log = _log(resumedFromId: '1720000000000');
      final restored = TourLog.fromJsonString(log.toJsonString());

      expect(restored.resumedFromId, '1720000000000');
    });

    test('resumedFromId가 null이면 toJson에 키 자체가 없다', () {
      final log = _log();
      expect(log.toJson().containsKey('resumedFromId'), isFalse);
    });
  });

  group('TourLog.copyWith', () {
    test('memo만 지정하면 memo만 바뀌고 나머지는 그대로 유지된다', () {
      final original = _log(startAddress: '서울시청', endAddress: '인천대공원');
      final updated = original.copyWith(memo: 'x');

      expect(updated.memo, 'x');
      expect(updated.id, original.id);
      expect(updated.startedAt, original.startedAt);
      expect(updated.endedAt, original.endedAt);
      expect(updated.startLat, original.startLat);
      expect(updated.startLng, original.startLng);
      expect(updated.endLat, original.endLat);
      expect(updated.endLng, original.endLng);
      expect(updated.startAddress, original.startAddress);
      expect(updated.endAddress, original.endAddress);
      expect(updated.distanceM, original.distanceM);
      expect(updated.durationS, original.durationS);
      expect(updated.avgSpeedKmh, original.avgSpeedKmh);
      expect(updated.maxSpeedKmh, original.maxSpeedKmh);
      expect(updated.trackFilePath, original.trackFilePath);
    });

    test('memo: null을 명시적으로 지정하면 memo가 null로 지워진다 '
        '(sentinel 패턴 회귀 가드)', () {
      final original = _log(memo: '지워질 메모');

      final cleared = original.copyWith(memo: null);

      expect(cleared.memo, isNull);
    });

    test('memo를 아예 지정하지 않으면(생략) 기존 non-null memo 값이 보존된다', () {
      final original = _log(memo: '보존되어야 할 메모');

      final unchanged = original.copyWith();

      expect(unchanged.memo, '보존되어야 할 메모');
    });

    test('resumedFromId를 지정하면 반영되고 나머지는 유지된다', () {
      final original = _log(startAddress: '서울시청', endAddress: '인천대공원');

      final updated = original.copyWith(resumedFromId: '999');

      expect(updated.resumedFromId, '999');
      expect(updated.startAddress, original.startAddress);
      expect(updated.endAddress, original.endAddress);
      expect(updated.memo, original.memo);
    });

    test('resumedFromId: null을 명시적으로 지정하면 null로 지워진다 '
        '(sentinel 패턴 회귀 가드)', () {
      final original = _log(resumedFromId: '888');

      final cleared = original.copyWith(resumedFromId: null);

      expect(cleared.resumedFromId, isNull);
    });

    test('resumedFromId를 아예 지정하지 않으면(생략) 기존 값이 보존된다', () {
      final original = _log(resumedFromId: '777');

      final unchanged = original.copyWith();

      expect(unchanged.resumedFromId, '777');
    });
  });
}
