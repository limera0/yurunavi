import '../../models/tour_log.dart';

/// 투어 요약 화면(목록/상세) 전용 순수 포맷팅/그룹핑 헬퍼.
/// 위젯 두 곳(list/detail)에서 공유하기 위해 별도 파일로 뺐다 — 위젯
/// 테스트 없이도 유닛 테스트가 가능하도록 순수 함수로 유지한다.

String formatTourDistanceKm(double distanceM) =>
    '${(distanceM / 1000).toStringAsFixed(1)} km';

String formatTourSpeedKmh(double kmh) => '${kmh.toStringAsFixed(0)} km/h';

/// durationS를 "H시간 M분" (1시간 이상) 또는 "M분"(1시간 미만)으로 포맷한다.
String formatTourDuration(int durationS) {
  final totalMinutes = durationS ~/ 60;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '$hours시간 $minutes분';
  return '$minutes분';
}

/// [logs]를 startedAt의 캘린더 day(연-월-일) 기준으로 그룹화한다.
/// 입력 순서를 그대로 보존하므로(TourLogService.loadAll()이 이미 최신순
/// 정렬해서 넘겨준다는 전제), 결과도 최신 day가 먼저 온다.
List<MapEntry<DateTime, List<TourLog>>> groupTourLogsByDay(
    List<TourLog> logs) {
  final map = <DateTime, List<TourLog>>{};
  for (final log in logs) {
    final day = DateTime(
        log.startedAt.year, log.startedAt.month, log.startedAt.day);
    (map[day] ??= <TourLog>[]).add(log);
  }
  return map.entries.toList();
}
