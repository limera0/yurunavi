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

  group('groupResumedTourLogs (S15)', () {
    test('resumedFromId 연결이 없으면 각자 leg 1개짜리 그룹이 된다', () {
      final logs = [
        _log(id: '1', startedAt: DateTime(2026, 8, 10, 9, 0)),
        _log(id: '2', startedAt: DateTime(2026, 8, 10, 11, 0)),
      ];

      final groups = groupResumedTourLogs(logs);

      expect(groups.length, 2);
      expect(groups.every((g) => !g.isMerged), isTrue);
    });

    test('resumedFromId로 연결된 두 leg를 하나의 그룹으로 묶고 시간순 정렬한다', () {
      final original = _log(id: 'a', startedAt: DateTime(2026, 8, 10, 9, 0));
      final resumed = _log(id: 'b', startedAt: DateTime(2026, 8, 10, 11, 30))
          .copyWith(resumedFromId: 'a');
      // 리스트 순서를 일부러 최신순(재개 leg 먼저)으로 둔다 —
      // TourLogService.loadAll()의 실제 정렬과 동일 조건에서 검증.
      final groups = groupResumedTourLogs([resumed, original]);

      expect(groups.length, 1);
      final g = groups.single;
      expect(g.isMerged, isTrue);
      expect(g.legs.map((l) => l.id), ['a', 'b']); // startedAt 오름차순
      expect(g.primary.id, 'a');
      expect(g.totalDistanceM, original.distanceM + resumed.distanceM);
      expect(g.totalDurationS, original.durationS + resumed.durationS);
    });

    test('3단 연속 재개(체인)도 하나의 그룹으로 묶인다', () {
      final leg1 = _log(id: '1', startedAt: DateTime(2026, 8, 10, 9, 0));
      final leg2 = _log(id: '2', startedAt: DateTime(2026, 8, 10, 11, 0))
          .copyWith(resumedFromId: '1');
      final leg3 = _log(id: '3', startedAt: DateTime(2026, 8, 10, 13, 0))
          .copyWith(resumedFromId: '2');

      final groups = groupResumedTourLogs([leg3, leg2, leg1]);

      expect(groups.length, 1);
      expect(groups.single.legs.map((l) => l.id), ['1', '2', '3']);
    });

    test('resumedFromId가 가리키는 원본이 리스트에 없으면(삭제됨) 단일 그룹으로 취급한다', () {
      final resumed = _log(id: 'b', startedAt: DateTime(2026, 8, 10, 11, 0))
          .copyWith(resumedFromId: 'missing-a');

      final groups = groupResumedTourLogs([resumed]);

      expect(groups.length, 1);
      expect(groups.single.isMerged, isFalse);
      expect(groups.single.primary.id, 'b');
    });
  });

  group('groupTourLogGroupsByDay (S15)', () {
    test('병합 그룹은 primary(최초 leg) 날짜의 그룹에 배정된다(자정을 넘겨도)', () {
      final original =
          _log(id: 'a', startedAt: DateTime(2026, 8, 10, 23, 30));
      final resumed = _log(id: 'b', startedAt: DateTime(2026, 8, 11, 0, 15))
          .copyWith(resumedFromId: 'a');
      final groups = groupTourLogGroupsByDay(groupResumedTourLogs([original, resumed]));

      expect(groups.length, 1);
      expect(groups.single.key, DateTime(2026, 8, 10));
      expect(groups.single.value.single.isMerged, isTrue);
    });
  });
}
