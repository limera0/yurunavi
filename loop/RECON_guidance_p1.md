# RECON_guidance_p1.md — Layer 1: shape_index 단조 진행추적

작성일: 2026-06-28 (토요일 야간 세션, Layer 0 머지 후)
근거: Valhalla 응답 실측(begin/end_shape_index 확인), nav_screen 정독, routing_service 정독.
대상: `lib/services/routing_service.dart`,
      신설 `lib/features/navigation/providers/route_progress_provider.dart`,
      `lib/features/navigation/presentation/nav_screen.dart`.
분류: **T3 (라이딩 회귀 필수)** — 카드/도착/TTS 거동 전면 변경.
브랜치: `feat/layer1-progress` (main 기준, Layer 0 머지 후).
전제: navStateProvider(Layer 0) = 단일 운동학 SoT. 이번엔 그 위에 진행추적 SoT를 얹음.

---

## §0 한 줄 목표

진행추적을 **단조 스냅 포인터(snapIdx) 하나**로 통일. 카드 잔여거리·step 전환·도착·
TTS 발화를 전부 이 포인터에서 파생. 현재의 분리 계산(최근접 완전탐색 + 직선거리 도착)을 폐기.

레퍼런스: OsmAnd `RouteCalculationResult` + `FollowedPolyline.updateToCurrentLocation`
(뒤로 안 가는 단조 iterator), Organic Maps `FollowedPolyline::Iter`(동일 패턴).

---

## §A 확정된 근본원인 (코드 레벨)

### A-1. shape_index 파싱 폐기 (routing_service)
Valhalla 응답에 maneuver마다 `begin_shape_index`/`end_shape_index`가 옴(실측 확인:
maneuver[0] = begin 0 / end 1). 그런데 파싱 2곳(:320, :386)이 **type/instruction/length만**
받고 shape_index를 버림. `ManeuverStep`(routing_service:31~44)에 필드 자체가 없음.
→ maneuver와 폴리라인의 연결고리 소멸 = 근본원인 (A).

### A-2. 두 개의 독립 거리 추적 (nav_screen)
shape_index가 없으니 진행을 좌표 거리로 역산:
- **카드**: `_updateStepByDistance`(:255) → `_traveledDistM`(:239)가 매 fix마다 전체
  `_routePoints` 순회(:244)하며 최근접 세그먼트 탐색 → 누적거리 역산. **단조성 없음**.
  자기교차·평행구간에서 최근접점이 튀어 카드 518m 고착.
- **도착**: `_checkArrival`(:388)는 위와 **무관하게** `_distanceM(loc, dest)` 직선거리만 봄.
- **step 전환**: `_updateStepByDistance`에서 remaining<50m면 `_stepIdx++`(거리 자동 진행).
  최근접 오판 1회로 인덱스가 통과한 maneuver에 고착 → "통과한 maneuver 표시".

### A-3. 증상3 ("300m 앞 좌회전" 고정)
`_traveledDistM` 오판 → remaining이 실제와 어긋남 → 300m 임계(:271)를 실제 위치와
무관하게 통과/고정. 거리 산출 자체가 신뢰 불가라 발화 거리도 신뢰 불가.

### A-4. leg 인덱스 오프셋 함정 (신규 발견, 구현 시 필수)
`_extractPoints`(routing_service:434)가 leg 이어붙일 때 중복점 skip:
```dart
points.addAll(decoded.skip(1));   // 2번째 leg부터 첫 점 버림
```
Valhalla `begin_shape_index`는 **leg 내부 기준**. `_routePoints`는 전체 leg 병합 배열이라
leg별 인덱스를 그냥 쓰면 오프셋 불일치. → shape_index를 **전역 인덱스로 변환** 필수
(leg마다 누적 오프셋 더하고, skip(1) 만큼 보정).

---

## §B 현 데이터 흐름 (정독 결과)

```
routing_service:316,383  leg['maneuvers'] → ManeuverStep(type,instruction,length)  [shape_index 버림]
routing_service:434      _extractPoints → leg shape 디코드 병합 → points (skip(1) 보정)
        ↓
main_map:565,672         _selectedManeuvers + routePolyline → NavScreen
        ↓
nav_screen:136           _routePoints = List.of(widget.routePolyline)
nav_screen:222           _applyRouteGuidance → _TurnStep.fromManeuver → _steps
nav_screen:213           _computeStepEndDistances → _stepEndDistM (rawDistKm 누적)
        ↓ (매 fix, navStateProvider 구독에서)
nav_screen:255 _updateStepByDistance(loc)
        ├─ _traveledDistM(loc)  [O(n) 최근접 완전탐색 — 단조성 없음]
        ├─ remaining = stepEnd - traveled → _cardRemainingM
        ├─ 500/300/50m 발화 (_pre500/300/50 플래그)
        └─ remaining<50 → _stepIdx++
nav_screen:203 _checkArrival(loc)  [직선거리, 별도 계산]
```

`_TurnStep`(1069~): icon/label/dist/rawDistKm. shape_index 없음.
`_routePoints` 채워지는 곳: 초기 :136, 재탐색 :346.

---

## §C 설계 — routeProgressProvider (신설)

### C-1. ManeuverStep 확장 (routing_service)
```dart
class ManeuverStep {
  final int type;
  final String instruction;
  final double distanceKm;
  final int beginShapeIdx;   // 추가: 전역 인덱스(leg 오프셋 적용 후)
  final int endShapeIdx;     // 추가: 전역 인덱스
  // (Layer 2에서 verbal_* 추가 예정 — 이번엔 인덱스만)
}
```
파싱(:320, :386): leg 루프에서 **누적 오프셋** 유지하며 전역 인덱스로 변환.
```dart
int shapeOffset = 0;
for (final leg in legs) {
  final legManeuvers = leg['maneuvers'] as List? ?? [];
  for (final m in legManeuvers) {
    maneuvers.add(ManeuverStep(
      type: ..., instruction: ..., distanceKm: ...,
      beginShapeIdx: shapeOffset + ((m['begin_shape_index'] as num?)?.toInt() ?? 0),
      endShapeIdx:   shapeOffset + ((m['end_shape_index'] as num?)?.toInt() ?? 0),
    ));
  }
  // 다음 leg 오프셋: 이번 leg 점 개수 - 1 (skip(1) 보정과 일치)
  final legPts = _decodePolyline6(leg['shape'] as String? ?? '');
  shapeOffset += (legPts.isEmpty ? 0 : legPts.length - 1);
}
```
※ 첫 leg는 skip 없음 → 오프셋 누적이 `length-1`로 일관(두번째 leg부터 첫 점이 이전 leg
   끝점과 동일). _extractPoints 로직과 정확히 대응하는지 구현 시 점 개수로 교차검증.

### C-2. RouteProgress 상태 + Provider (신설)
`route_progress_provider.dart`:
```dart
@immutable
class RouteProgress {
  final int snapIdx;          // 폴리라인 상 현재 위치 인덱스(단조 증가)
  final int activeStepIdx;    // 현재 진행 중 maneuver
  final double distToNextTurnM; // snap → 다음 step.beginShapeIdx 까지 폴리라인 누적
  final double distToDestM;    // snap → 폴리라인 끝까지 누적
  final bool arrived;
}

final routeProgressProvider =
    NotifierProvider<RouteProgressNotifier, RouteProgress?>(...);
```
- 입력: `routePolyline`(List<LatLng>), `maneuvers`(beginShapeIdx 포함), `destination`.
  → nav 진입 시 `setRoute(...)`로 주입(재탐색 시 갱신).
- navStateProvider.pos 구독 → 매 fix `_advance(pos)`:
  ```
  // 단조 스냅: snapIdx 이후 구간에서만 최근접 탐색(뒤로 안 감)
  최근접 세그먼트를 [snapIdx, snapIdx + window] 범위에서만 탐색
  newSnap = max(snapIdx, foundIdx)   // 단조 보장
  activeStepIdx = snapIdx >= step.endShapeIdx 인 최대 step + 1
  distToNextTurnM = 폴리라인 누적(snapIdx → maneuvers[active].beginShapeIdx)
  distToDestM = 폴리라인 누적(snapIdx → last)
  arrived = distToDestM <= _kArrivalRadiusM (직선거리 아님)
  ```
- window(예: 앞 50세그먼트)로 제한해 O(n)→O(window). 경로이탈 시 window 밖이면
  스냅 실패 → 재탐색 트리거(Layer 3에서 heading 추가, 이번엔 거리 기반만).

### C-3. nav_screen 이관 (소비 측)
- `_traveledDistM`/`_updateStepByDistance`/`_stepEndDistM`/`_computeStepEndDistances`
  **제거**. `_checkArrival` 직선거리 로직 제거.
- 화면은 `routeProgressProvider` 구독:
  ```
  final p = ref.watch(routeProgressProvider);
  _cardRemainingM = p.distToNextTurnM;
  _stepIdx = p.activeStepIdx;
  if (p.arrived) → 도착 UX
  ```
- 발화(500/300/50): distToNextTurnM 기준으로 이동. 단 **상태추적은 (stepIdx, 임계)별**
  1회(메모리 TTS 사양: 500/300/50m 각 1회). step 바뀌면 플래그 리셋.
- `_steps`(_TurnStep)는 표시용으로 유지하되 거리 자동진행 폐기 → activeStepIdx 구독.

### C-4. 발화/도착은 progress에서만 파생 (단일화 원칙)
- 출발 멘트 "출발합니다"(거리/방향 미포함) — 기존 사양 유지.
- 500/300/50m 발화: distToNextTurnM 임계. 각 이벤트당 1회(상태 추적).
- 도착: progress.arrived (폴리라인 끝 도달). _checkArrival 직선거리 폐기.
  ※ 도착 UX(SPEC_arrival_v2b: 수동 지오펜스 버튼)는 별도 — 이번엔 arrived 판정만 교체.

---

## §D 커밋 분할 (3커밋, 각 analyze 통과)
- **C1** `feat(routing): parse maneuver shape indices with leg offset`
  — routing_service: ManeuverStep + 파싱 2곳 + 전역 인덱스 변환. 미사용이라 단독 OK.
- **C2** `feat(nav): add routeProgressProvider monotonic snap tracker`
  — route_progress_provider.dart 신설(§C-2). 아직 화면 미연결.
- **C3** `refactor(nav): consume routeProgress, drop split distance tracking`
  — nav_screen §C-3/C-4: 최근접탐색·직선도착 제거, progress 구독 전환.
각 커밋 `flutter analyze` 새 에러 0 + code-auditor 7/7.

---

## §E 검증
### 정적
- `flutter analyze` 새 에러 0. `flutter build apk --debug` 성공.
### 스모크 (라이딩 불필요)
- 경로 탐색 → 내비 진입 → 카드에 첫 turn·거리 표시 → 크래시 없음.
- 디버그로그로 snapIdx 단조 증가 확인(YNAV_GUIDE tick).
### 라이딩 회귀 (T3 — main 머지 전 필수)
1. **카드 단조 감소**: 턴 접근 시 잔여거리가 단조 감소(518m 고착·역행 없음).
2. **step 전환**: 턴 통과 후 다음 maneuver로 정확히 전환(통과 maneuver 잔존 없음).
3. **거리 정확도**: "300m 앞 좌회전"이 실제 300m에서 발화(증상3 해소).
4. **TTS 1회**: 500/300/50m 각 1회만 발화(중복·누락 없음).
5. **도착**: 폴리라인 끝 도달 시 도착(직선거리 오판 없음).
6. **Layer 0 무회귀**: 속도계·카메라 5/5 유지.

---

## §F 미결 / 다음 레이어 연결
- **window 크기**: 앞 N세그먼트 탐색 범위. 너무 작으면 GPS 점프 시 스냅 실패, 너무 크면
  자기교차서 오판. 초기값 50, 라이딩에서 튜닝. (OsmAnd는 ~동적, 우선 고정값.)
- **재탐색 트리거**: 이번엔 "snap window 밖 = 이탈" 거리 기반만. **Layer 3**에서
  bearing_after(응답에 존재 확인) + navState.headingDeg로 heading 인식 추가 → 유턴 감지.
- **Layer 2 (다음)**: verbal_pre/post/succinct_transition_instruction, verbal_multi_cue
  (전부 응답에 존재 확인) 파싱 복원 → _labelForType 하드코딩 대체. street_names/lanes는
  중간 maneuver로 존재 재확인 후.
- ManeuverStep 확장이 main_map 카드 전환(_selectedManeuvers)에 영향 없는지 확인
  (필드 추가는 하위호환, 기존 소비처 무변경).
