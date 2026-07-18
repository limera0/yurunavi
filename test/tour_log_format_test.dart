import 'package:flutter_test/flutter_test.dart';
import 'package:yurunavi/features/tour_summary/tour_log_format.dart';
import 'package:yurunavi/models/tour_log.dart';

TourLog _log({
  required String id,
  required DateTime startedAt,
  double distanceM = 10000,
  int durationS = 1800,
  double avgSpeedKmh = 20,
  double maxSpeedKmh = 40,
}) {
  return TourLog(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationS)),
    startLat: 37.5,
    startLng: 127.0,
    endLat: 37.6,
    endLng: 127.1,
    distanceM: distanceM,
    durationS: durationS,
    avgSpeedKmh: avgSpeedKmh,
    maxSpeedKmh: maxSpeedKmh,
    trackFilePath: '/tmp/tracks/$id.jsonl',
  );
}

void main() {
  group('formatTourDistanceKm', () {
    test('미터를 km로 변환하고 소수점 첫째자리까지 표기한다', () {
      expect(formatTourDistanceKm(45230.5), '45.2 km');
      expect(formatTourDistanceKm(1000), '1.0 km');
      expect(formatTourDistanceKm(0), '0.0 km');
    });
  });

  group('formatTourSpeedKmh', () {
    test('정수로 반올림해 km/h 단위를 붙인다', () {
      expect(formatTourSpeedKmh(18.09), '18 km/h');
      expect(formatTourSpeedKmh(102.6), '103 km/h');
    });
  });

  group('formatTourDuration', () {
    test('1시간 미만은 분만 표기한다', () {
      expect(formatTourDuration(59 * 60), '59분');
      expect(formatTourDuration(0), '0분');
    });

    test('1시간 이상은 "H시간 M분"으로 표기한다', () {
      expect(formatTourDuration(90 * 60), '1시간 30분');
      expect(formatTourDuration(3 * 3600), '3시간 0분');
    });
  });

  group('normalizeTourMemo', () {
    test('앞뒤 공백을 트림한다', () {
      expect(normalizeTourMemo('  좋은 라이딩이었다  '), '좋은 라이딩이었다');
    });

    test('빈 문자열이나 공백만 있으면 null을 반환한다', () {
      expect(normalizeTourMemo(''), isNull);
      expect(normalizeTourMemo('   '), isNull);
      expect(normalizeTourMemo('\n\t '), isNull);
    });

    test('내부 개행/공백은 보존한다', () {
      expect(normalizeTourMemo('첫 줄\n둘째 줄'), '첫 줄\n둘째 줄');
    });
  });

  group('groupTourLogsByDay', () {
    test('같은 날짜(연-월-일)의 투어를 하나의 그룹으로 묶는다', () {
      final logs = [
        _log(id: '1', startedAt: DateTime(2026, 7, 17, 9, 0)),
        _log(id: '2', startedAt: DateTime(2026, 7, 17, 18, 30)),
        _log(id: '3', startedAt: DateTime(2026, 7, 16, 8, 0)),
      ];

      final groups = groupTourLogsByDay(logs);

      expect(groups.length, 2);
      expect(groups[0].key, DateTime(2026, 7, 17));
      expect(groups[0].value.map((l) => l.id), ['1', '2']);
      expect(groups[1].key, DateTime(2026, 7, 16));
      expect(groups[1].value.map((l) => l.id), ['3']);
    });

    test('입력이 비어있으면 빈 그룹 리스트를 반환한다', () {
      expect(groupTourLogsByDay([]), isEmpty);
    });
  });
}
