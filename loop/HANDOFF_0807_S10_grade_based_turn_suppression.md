GOAL: 진입 도로 대비 진출 도로의 등급이 유지되거나 상승하는 회전/갈림길 안내는 음성 억제하고, 등급이 하락할 때만 정상 안내해 지방도 진입 시의 오안내(불필요한 "좌회전" 등)를 없앤다.

- 작성 2026-08-07 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S10 (580~586행)
- 마스터 확인 완료 사항(2026-08-07 인터랙티브 세션):
  - **적용 범위: 모든 회전 방향** (좌/우/직진 갈림 전부 — 체크리스트 제목은
    "좌회전"이지만 실제 규칙은 방향 무관하게 등급 기준으로 통일하기로 확정).
- 이 항목은 원인 조사가 아니라 **신규 기능 설계**. 아래는 Valhalla 실제 응답을
  curl로 검증하고 기존 아키텍처(trace_attributes 파이프라인, VoiceEngine)에
  꽂아 넣는 구체 설계다 — 첫 체크리스트 항목("Valhalla 응답에 road_class
  포함 여부 계약 확인")은 이미 이 세션에서 완료했다, 아래 §0 참조.

## §0. Valhalla 계약 확인 결과 (curl 실측, 2026-08-07)

- **`/route`의 `maneuvers` 배열에는 road_class가 없다.** (`type`,
  `instruction`, `street_names`, `begin_shape_index`, `end_shape_index` 등만
  있음 — 직접 확인.)
- **`/trace_attributes`의 `edges` 배열에는 `edge.road_class`를 요청하면
  포함된다.** 이미 `RoutingService.fetchStructureZones()`가 다리/터널
  판정을 위해 같은 엔드포인트를 호출 중이다 — **새 HTTP 호출을 추가하지 말고
  기존 호출의 `filters.attributes`에 `'edge.road_class'` 한 줄만 추가해
  재사용할 것.** (S2에서 429 폭주로 크게 데인 이력이 있다 — 같은 정보를 위해
  두 번째 trace_attributes 호출을 만드는 건 명백한 회귀다. memory
  `project_valhalla_rate_limit` 참조.)
- 실측 값 예시(화성시 팔탄면 인근 실제 라우팅 응답):
  ```json
  {"begin_shape_index": 14, "end_shape_index": 15, "road_class": "tertiary", "names": ["내향로"]}
  {"begin_shape_index": 15, "end_shape_index": 16, "road_class": "primary",  "names": ["발안로", "82"]}
  ```
  `road_class` 문자열 값은 Valhalla `RoadClass` enum과 정확히 일치
  (`/data/projects/valhalla-src/valhalla/baldr/graphconstants.h:131-139`):
  `motorway`(0) > `trunk`(1) > `primary`(2) > `secondary`(3) > `tertiary`(4)
  > `unclassified`(5) > `residential`(6) > `service_other`(7). 숫자가 낮을수록
  상위 등급 — 이 순서가 스타일 파일(S12, 커밋 45580bd)의 국도=trunk+primary,
  지방도=secondary 매핑과도 일치한다.
- edges의 `begin_shape_index`/`end_shape_index`는 `points`(=`ManeuverStep`과
  동일 전역 좌표계, `_routePoints`)를 그대로 인코딩해 보낸 polyline 기준이라
  **오프셋 변환 없이 `ManeuverStep.beginShapeIdx`와 직접 비교 가능**
  (`buildStructureZones`가 이미 이 가정으로 동작 중 — 동일 전제 재사용).

## 현재 코드 구조 (2026-08-07 확인)

- `lib/services/routing_service.dart`
  - `ManeuverStep`(:35) — road_class 필드 없음. **필드를 추가하지 말 것**
    (아래 이유). 대신 `StructureType`과 동일한 "별도 맵 + provider 캐싱"
    패턴을 따른다.
  - `fetchStructureZones(points)`(:1096) — `/trace_attributes` 호출,
    `filters.attributes`에 `edge.begin_shape_index`/`end_shape_index`/
    `length`/`bridge`/`tunnel`/`names`를 요청 중(:1118-1129). 여기에
    `'edge.road_class'` 추가.
  - `buildStructureZones(edges)`(:859) — 순수 동기 함수, edges → zones.
    **같은 자리 옆에 병렬로 `buildRoadClassByManeuverIdx(edges, maneuvers)`
    신설**(아래 §1).
- `lib/features/navigation/providers/route_progress_provider.dart`
  - `_exitStructureByManeuverIdx`(:80) + `exitStructureByManeuverIdx` getter
    (:104) + `_recomputeExitStructureMap()`(:538) + `setStructureZones()`
    (:368) + `setOffRouteStructures()`(:407) — **이 넷의 패턴을 정확히
    복제**해 `_roadClassByManeuverIdx`/getter/`setRoadClasses()`를 추가.
    `setStructureZones`처럼 `RouteProgress` state를 재emit할 필요는 없다
    (exitStructureByManeuverIdx와 동일하게 getter로 직접 조회되는 파생
    데이터 — nav_screen이 매 틱 최신값을 직접 읽어간다).
  - `setRoute()`(:296) — 새 경로 주입 시 `_offRouteStructureByManeuverIdx`를
    비우는 것처럼(:304) `_roadClassByManeuverIdx`도 `const {}`로 리셋할 것
    (이전 경로의 shape 인덱스는 새 경로와 무관).
- `lib/features/navigation/presentation/nav_screen.dart`
  - `_applyRouteGuidance(maneuvers)`(:731) — `_maneuvers = maneuvers;`(:734)
    설정 후 `_loadStructureZones(_routePoints, generation)`(:755) 호출 —
    이 시점엔 이미 `_maneuvers`가 채워져 있으니 새 파라미터 없이 그대로
    참조 가능.
  - `_loadStructureZones(points, generation)`(:764) — `fetchStructureZones`
    반환값이 바뀌므로(§1) 여기서 zones/roadClasses 둘 다 받아
    `notifier.setStructureZones(zones)` 옆에 `notifier.setRoadClasses(...)`
    추가.
  - `_handleVoice(prog)`(:669) — `_voiceEngine!.exitStructureByManeuverIdx =
    ref.read(...).exitStructureByManeuverIdx;`(:681) 바로 옆에
    `_voiceEngine!.roadClassByManeuverIdx = ref.read(...).roadClassByManeuverIdx;`
    추가 — **반드시 `onProgress` 호출 전에**(같은 이유: provider 파생
    데이터라 매 틱 최신값 필요).
- `lib/features/navigation/voice_engine.dart`
  - `eventForType(type)`(:14) — Valhalla type → voice event 문자열 매핑.
  - `VoiceEngine.onProgress(step, d, steps, ...)`(:120) — `event`를 구한
    직후(:129-130, `if (event == null) return const [];` 바로 다음) 억제
    체크를 넣는다(아래 §2). **이 지점이 유일한 삽입 지점** — 그 아래의
    tier/pending-point 로직(:132~)은 절대 건드리지 않는다.

## §1. `RoutingService`에 road_class 매핑 함수 추가

```dart
/// maneuvers[i]의 진입(entry)/진출(exit) road_class.
/// entry = beginShapeIdx에서 끝나는 직전 edge의 등급(지금까지 타고 온 도로).
/// exit  = beginShapeIdx에서 시작하는 edge의 등급(이 maneuver로 올라타는 도로).
/// 매칭 실패(트레이스 실패/데이터 누락)는 그냥 맵에서 빠진다 — 호출부가
/// null을 "판단 불가"로 다뤄야 한다(§2 fail-open 참조).
static Map<int, ({String? entry, String? exit})> buildRoadClassByManeuverIdx(
  List<dynamic> edges,
  List<ManeuverStep> maneuvers,
) {
  final map = <int, ({String? entry, String? exit})>{};
  for (int i = 0; i < maneuvers.length; i++) {
    final b = maneuvers[i].beginShapeIdx;
    String? entry, exit;
    for (final e in edges) {
      final m = e as Map;
      if ((m['end_shape_index'] as num?)?.toInt() == b) {
        entry = m['road_class'] as String?;
      }
      if ((m['begin_shape_index'] as num?)?.toInt() == b) {
        exit = m['road_class'] as String?;
      }
    }
    if (entry != null || exit != null) map[i] = (entry: entry, exit: exit);
  }
  return map;
}

static const _roadClassRank = {
  'motorway': 0, 'trunk': 1, 'primary': 2, 'secondary': 3,
  'tertiary': 4, 'unclassified': 5, 'residential': 6, 'service_other': 7,
};

/// exit 등급이 entry보다 실제로 하락(랭크 숫자 증가)했을 때만 true.
/// 값이 없거나 인식 불가하면 판단 불가 → **안내를 억제하지 않는다**
/// (안전 우선 — 불확실할 땐 "억제"보다 "과잉 안내"가 낫다는 원칙,
/// memory `feedback_safety_priority`/S7 HANDOFF §3 동일 판단).
static bool isGradeDowngrade(String? entryClass, String? exitClass) {
  final er = _roadClassRank[entryClass];
  final xr = _roadClassRank[exitClass];
  if (er == null || xr == null) return true;
  return xr > er;
}
```

`fetchStructureZones`는 이제 zones와 road class 맵을 함께 반환해야 한다
(같은 `edges`를 두 순수 함수에 각각 넘기면 됨, 호출은 여전히 1회):

```dart
static Future<({List<StructureZone> zones,
    Map<int, ({String? entry, String? exit})> roadClasses})> fetchStructureZones(
  List<LatLng> points,
  List<ManeuverStep> maneuvers,
) async {
  ...
  filters.attributes에 'edge.road_class' 추가
  ...
  final edges = data['edges'] as List? ?? [];
  return (
    zones: buildStructureZones(edges),
    roadClasses: buildRoadClassByManeuverIdx(edges, maneuvers),
  );
}
```

시그니처가 바뀌므로 유일한 호출부(`nav_screen.dart:765`)도 함께 수정.
실패 시(현재 catch 블록) 빈 zones + 빈 roadClasses 레코드를 반환하도록
기존 안전 폴백(예외 안 던짐)을 유지할 것.

## §2. `VoiceEngine`에 억제 로직 추가

```dart
Map<int, ({String? entry, String? exit})>? roadClassByManeuverIdx;
```
(nullable, settable — `exitStructureByManeuverIdx`와 동일 패턴. 생성자
optional 파라미터에도 추가.)

`onProgress`의 `if (event == null) return const [];` 바로 다음:

```dart
const _gradeSuppressible = {
  'turn_left', 'turn_right', 'sharp_turn_left', 'sharp_turn_right',
  'keep', 'keep_left', 'keep_right',
};
if (_gradeSuppressible.contains(event)) {
  final rc = roadClassByManeuverIdx?[turnIdx];
  if (rc != null && !RoutingService.isGradeDowngrade(rc.entry, rc.exit)) {
    return const [];
  }
}
```

### 이벤트 범위를 이렇게 좁힌 이유 (반드시 이대로 구현할 것)

- 포함: `turn_left`/`turn_right`(type 15,16,9,10), `sharp_turn_*`(14,11),
  `keep`/`keep_left`/`keep_right`(type 22,23,24 = Valhalla
  kStayStraight/kStayRight/kStayLeft, **갈림길 차선유지** — 정확히 memory
  `feedback_accurate_maneuver_wording`가 지적한 "실제 회전 아닌데 회전
  표현 쓰는" 그 이벤트군).
- 제외(등급 무관 항상 정상 안내): `ramp_*`/`exit_*`(고속도로·국도 진출입 —
  등급이 "상승"해도 실제로 차선을 빠져나가야 하는 필수 조작),
  `roundabout_*`(로터리는 별도 방위각 기반 판정 로직이 이미 있음, S6 참조),
  `uturn`(항상 의도적 조작), `merge`, `destination`, `continue`(억제 대상
  자체가 없음). 이 목록을 넓히거나 좁히면 안전 관련 안내가 사라질 수
  있으니 코더가 임의로 조정하지 말 것 — 다르게 판단되면 리포트에 이유를
  남기고 마스터 확인.

### 왜 `ManeuverStep`에 필드를 직접 추가하지 않았는가

`ManeuverStep`은 `/route` 응답만으로 즉시 만들어지는 반면 road_class는
trace_attributes가 비동기로 늦게 도착한다(구조물 zone과 완전히 동일한
타이밍 문제). `exitStructureByManeuverIdx`가 이미 이 문제를 "별도 맵 +
provider 캐싱 + 호출 직전 갱신"으로 풀어놓은 전례가 있으므로 road_class도
똑같은 패턴을 따른다 — `ManeuverStep`을 불변 상태로 유지하면서 새 필드
추가마다 모든 생성 지점을 갱신해야 하는(S7 HANDOFF의 `NavigationState`
`copyWith 금지` 주석과 같은 종류의) 부담을 피한다.

## 알려진 리스크 (감사 시 반드시 확인)

- **음성만 억제하고 화면 상단 턴 카드(`_TurnStep`/`_buildTurnSteps`)는 그대로
  둔다 — 의도적 스코프 제한.** 카드는 `ManeuverStep` 리스트를 그대로
  순회해 만들어지고(nav_screen.dart:708), 이걸 등급 기준으로 스킵/병합하려면
  거리 재계산·"현재 안내" 포커스 로직까지 건드려야 해서 S10 스코프(안내
  "억제" = 음성 억제)를 넘어선다. 결과적으로 등급 유지 갈림길에서 카드는
  "좌회전"을 계속 보여주지만 음성은 조용하다 — 완전한 해결은 아니지만,
  체크리스트가 문제 삼은 건 수동적인 화면 표시가 아니라 능동적으로
  끼어드는 잘못된 음성 지시다. 이 트레이드오프를 리포트에 남길 것(숨기지
  말 것).
- **road_class 판정 실패 시 fail-open(안내함)** — trace_attributes가
  실패하거나 늦게 도착하는 동안은 `roadClassByManeuverIdx`가 비어 있어
  `rc == null` → 억제 조건 자체가 성립하지 않아 항상 정상 안내된다(현재
  동작과 동일, 회귀 없음). 이 폴백을 절대 반대로(데이터 없으면 억제)
  구현하지 말 것 — 실제 필요한 회전 안내가 조용히 사라지는 게 훨씬
  위험하다.
- **정확한 그레이드 판정은 `road_class`뿐, `subclass`/`use`(예:
  `motorroad=yes`)는 보지 않는다** — S9(자동차전용도로 하드 배제)와는
  독립적인 스코프. 섞지 말 것.

## 검증 요구

- 순수 로직 단위테스트:
  - `RoutingService.isGradeDowngrade` — 상승/유지/하락/양쪽 null/한쪽 null
    조합 전부.
  - `RoutingService.buildRoadClassByManeuverIdx` — 합성 edges+maneuvers로
    entry/exit 매칭, 매칭 없는 maneuver는 맵에서 빠지는지.
- `VoiceEngine` 단위테스트: `_gradeSuppressible`에 속한 이벤트가
  등급 유지/상승일 때 `onProgress`가 빈 리스트 반환, 하락일 때 정상
  SpeakIntent 반환, `roadClassByManeuverIdx`가 null이거나 해당 인덱스가
  없을 때 정상 안내(기존 동작 유지) 확인. `ramp_*`/`exit_*`/`roundabout_*`/
  `uturn` 이벤트는 등급 유지·상승이어도 억제되지 않는지 별도 확인(§2 범위
  회귀 방지).
- §0의 curl 실측을 재현할 수 있는 통합 스모크(선택, 헤드리스 가능): 실제
  `/trace_attributes` 호출 대신 §0에 기록된 샘플 JSON을 고정 픽스처로
  써서 `fetchStructureZones` 파싱 경로만 검증해도 충분.
- `flutter analyze` 이슈 0, `flutter test` 전건 통과.
- 실기기 검증(가상GPS): 국도→지방도 갈림길(등급 하락, 안내 나와야 함)과
  지방도 내 등급 유지 갈림길(안내 없어야 함) 두 시나리오 — 실측 좌표는
  마스터가 이미 알고 있을 38번 지방도 관련 지점 활용 가능(memory
  `feedback_dont_conclude_impossible_too_fast` 사례와 같은 지역).

## 완료 후

- `code-auditor` PASS 후 커밋, `CHECKLIST_0805_testride0802.md` §S10 `[x]`로
  갱신.
- `loop/MORNING_REPORT_0807_S10_grade_based_turn_suppression.md`에 기록 —
  특히 "화면 카드는 그대로" 스코프 제한을 목표달성 판정에 명시.
