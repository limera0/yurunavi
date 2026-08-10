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

/// 메모 입력창의 원본 텍스트를 저장용 값으로 정규화한다.
/// 앞뒤 공백을 트림하고, 트림 결과가 빈 문자열이면 `null`을 반환해
/// "메모 없음" 상태로 되돌린다(빈 문자열을 그대로 저장하지 않음).
String? normalizeTourMemo(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
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

/// S15: `resumedFromId`로 연결된 log 체인을 시간순 leg 묶음 하나로 만든다.
/// 원본 두(이상) `TourLog`는 저장소에서 합치지 않는다 — 이 함수는 **표시
/// 시점에만** 묶어서 반환한다(삭제/메모 편집 등 기존 단건 동작을 깨지 않기
/// 위함). 연결이 없는 일반 투어는 leg 1개짜리 그룹이 된다. 체인이 끊겨
/// 있으면(원본이 이미 삭제된 경우 등) 안전하게 단일 leg 그룹으로 취급한다.
class TourLogGroup {
  /// startedAt 오름차순(중단 전 → 재개 후) — 최소 1개.
  final List<TourLog> legs;
  TourLogGroup(this.legs) : assert(legs.isNotEmpty);

  bool get isMerged => legs.length > 1;

  /// 날짜 그룹 배정·카드 대표 표시에 쓰는 leg — 가장 이른(최초 출발) leg.
  TourLog get primary => legs.first;

  double get totalDistanceM =>
      legs.fold(0.0, (sum, l) => sum + l.distanceM);
  int get totalDurationS => legs.fold(0, (sum, l) => sum + l.durationS);
}

/// [logs] 중 `resumedFromId`로 서로 가리키는 것들을 [TourLogGroup]으로
/// 묶는다. id로 명시적으로 연결을 찾으므로 리스트 내 인접 여부와 무관하게
/// 정확히 짝을 찾는다(날짜 그룹 경계를 걸쳐도 무방).
List<TourLogGroup> groupResumedTourLogs(List<TourLog> logs) {
  final byId = {for (final l in logs) l.id: l};

  String rootIdOf(TourLog log) {
    var current = log;
    final visited = <String>{current.id};
    while (true) {
      final parentId = current.resumedFromId;
      final parent = parentId == null ? null : byId[parentId];
      if (parent == null || !visited.add(parent.id)) break; // 연결 없음/순환 방어
      current = parent;
    }
    return current.id;
  }

  final chains = <String, List<TourLog>>{};
  for (final log in logs) {
    chains.putIfAbsent(rootIdOf(log), () => <TourLog>[]).add(log);
  }

  return chains.values
      .map((legs) =>
          TourLogGroup(legs..sort((a, b) => a.startedAt.compareTo(b.startedAt))))
      .toList();
}

/// [groups]를 primary(최초 leg) startedAt의 캘린더 day 기준으로 그룹화한다.
/// 재개로 자정을 넘긴 투어는 **출발한 날**의 그룹 하나에 통째로 표시된다
/// (재개된 날짜 쪽에 따로 쪼개 보여주지 않는다) — "그 날의 라이딩"이라는
/// 사용자 인식과 맞고, 몇 번을 재개하든 배정이 안정적이기 때문.
List<MapEntry<DateTime, List<TourLogGroup>>> groupTourLogGroupsByDay(
    List<TourLogGroup> groups) {
  final map = <DateTime, List<TourLogGroup>>{};
  for (final g in groups) {
    final day = DateTime(g.primary.startedAt.year, g.primary.startedAt.month,
        g.primary.startedAt.day);
    (map[day] ??= <TourLogGroup>[]).add(g);
  }
  return map.entries.toList();
}
