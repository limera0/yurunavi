GOAL: 로터리(회전교차로) 안내에서 신뢰할 수 없는 `roundabout_exit_count` 기반 출구 번호 발화를 완전히 폐기하고, 경로 shape의 진입/진출 방위차를 직접 계산해 좌/직/우로 안내한다.

- 작성 2026-08-07 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S6 (348~366행),
  [RECON_0805_testride0802_master_plan.md:590-660](RECON_0805_testride0802_master_plan.md) (원인 확정 근거)
- 원인은 이미 확정됨 — **조사 불필요, 바로 구현.** 공개 업스트림 Valhalla도 검단회전교차로
  6개 조합 전부 `roundabout_exit_count=2`를 반환함을 확인했다(포크 결함도 앱 파싱 버그도 아님).
  근거: memory `feedback_accurate_maneuver_wording` — 틀린 번호를 말하느니 안 말하는 게 낫다.

## 착수 전 자체 검증 (2026-08-07, 이 세션에서 수행)

로컬 prod Valhalla(`localhost:8002`)에 검단회전교차로(37.5988,126.6506) 주변 5개 진입/진출
조합을 직접 프로브해 아래 알고리즘의 실현 가능성과 대략적 타당성을 확인했다(6번째 조합
S→N은 로터리를 거치지 않는 경로가 나와 제외):

| 조합 | entry bearing | exit bearing | signed turn | 판정(±45°) |
|---|---|---|---|---|
| S→E | 56.2° | 64.6° | +8.4° | 직 |
| S→W | 56.2° | 265.3° | −150.9° | 좌 |
| N→S | 171.7° | 154.2° | −17.5° | 직 |
| E→W | 254.4° | 265.3° | +10.9° | 직 |
| W→N | 56.2° | 315.1° | −101.1° | 좌 |

**주의**: 이 프로브에 쓴 N/S/E/W 지점은 로터리 중심에서 250m 떨어진 "정확히 정방위" 좌표일
뿐, 실제 도로가 정방위로 뻗어 있다는 보장은 없다(entry bearing이 56.2°인 것만 봐도 남쪽
진입로가 실제로는 ENE 방향으로 휘어 있음). 즉 **이 표는 "알고리즘이 동작하고 좌/직/우가
고르게 나뉜다"는 실현 가능성 확인일 뿐, "각 판정이 실제 지형과 일치한다"는 정답 확인이
아니다** — 위성지도/실기기 대조 없이는 여기서 더 확정할 수 없다. 아래 검증 항목 참고.

## 현재 코드 구조

- `lib/features/navigation/voice_engine.dart:150-170` — `onProgress()` 안,
  `event == 'roundabout_enter'`(:151-158)일 때 `steps[turnIdx].roundaboutExitCount`를
  `vars['exit']`로 주입. `event == 'roundabout_exit' && isImminent`(:159-170)일 때도
  **바로 앞 enter maneuver**(`enterIdx = turnIdx - 1`)의 `roundaboutExitCount`를 이어받아
  `vars['exit']`로 주입 — 두 곳 다 신뢰 불가 값을 쓰고 있다.
  - `roundabout_exit` 이벤트 자체는 S4b(`guidance_profile.json`의
    `"roundabout_exit": { "enabled": false }`)로 **이미 비활성화**돼 있어 :159-170 블록은
    현재 실행되지 않는 죽은 코드다. 그래도 JSON 설정 하나에만 의존하지 않도록 이번에
    코드 자체도 지운다(방어적 이중 차단, `{exit}` 주입 경로를 완전히 없앤다는 체크리스트
    문구와도 일치).
  - `onProgress()`는 이미 `shapePoints` 파라미터(전역 인덱스, `beginShapeIdx`/`endShapeIdx`와
    같은 좌표계 — :123-129에서 랜드마크 조회에 이미 이 방식으로 쓰임)를 받는다.
    **시그니처 변경 불필요.**
- `steps[turnIdx]`가 `roundabout_enter`(type 26) maneuver. **바로 다음 스텝
  `steps[turnIdx + 1]`이 항상 `roundabout_exit`(type 27)** — Valhalla가 26/27을 항상
  붙여서 낸다는 걸 위 프로브 5건 전부에서 확인(및 기존 RECON들에서도 일관). 그래도 방어적으로
  `turnIdx + 1 < steps.length && steps[turnIdx+1].type == 27` 체크 후, 실패 시 방향 계산을
  건너뛰고 기존처럼 `roundabout_$phase`(방향 없는 일반 문구, 이미 JSON에 존재하는 안전한
  폴백) 키로 폴백한다.
- `lib/services/poi_service.dart:329-343` — `PoiService.bearing(LatLng, LatLng)`(부호 없는
  0~360 방위각), `PoiService.bearingDiff(a, b)`(0~180 절대 차이, **부호 없음** — 이번에 필요한
  좌/우 판별에는 못 씀, 새 부호 있는 diff 필요).
- `lib/services/routing_service.dart:98` `enum CurveDirection { left, right }` — 급커브
  판정에서 이미 쓰는 부호 관례: `delta = segEnd - segStart`(정규화 -180~180),
  **`delta < 0 → left, delta >= 0 → right`**(`:997-1001`). 이번 로터리 방향 계산도
  **동일 부호 관례**를 따를 것 — 다른 부호 규칙을 새로 만들면 나중에 헷갈린다.
- `lib/services/routing_service.dart:74-83` `extension StructureTypeLabel on StructureType`
  — `labelKo` getter 패턴. 이번에 만들 방향 enum도 같은 패턴을 따르면 자연스럽다.

## 작업 항목

### 1. 부호 있는 방위차 계산 + 3분류 판정 함수 신설

- `PoiService`에 부호 있는 버전 추가 (예: `PoiService.signedBearingDiff(double from, double to)`
  → `-180~180`, 공식: `((to - from + 540) % 360) - 180`. 위 프로브에서 검증한 공식.
- 신규 enum, `CurveDirection`과 같은 파일(`routing_service.dart`)에 두거나 voice_engine
  근처 새 파일 — 코더 판단: `enum RoundaboutDirection { left, straight, right }` +
  `extension RoundaboutDirectionLabel on RoundaboutDirection { String get labelKo => ... }`
  (`좌측`/`직진`/`우측`).
- 분류 함수: `RoundaboutDirection classify(double signedTurnDeg)` —
  **`CurveDirection`과 동일 부호**: `turn <= -45 → left`, `turn >= 45 → right`,
  그 사이 → `straight`. (임계값 ±45°는 이 세션에서 결정 — 표준 turn-by-turn 분류 관례.
  프로브 5건이 이 임계값으로 좌/직 두 버킷에 고르게 나뉘는 것으로 1차 확인됨. 실측 결과
  버킷 경계가 부적절해 보이면 조정하되 근거를 리포트에 남길 것)

### 2. `voice_engine.dart` 수정

- `:151-158`(`roundabout_enter` 블록) — `roundaboutExitCount` 읽기를 제거하고 방향 계산으로
  교체:
  1. `steps[turnIdx].beginShapeIdx`(진입 지점)를 이용해 진입 방위각 계산:
     `PoiService.bearing(shapePoints[beginIdx-1], shapePoints[beginIdx])`
     (경계 가드: `beginIdx >= 1 && beginIdx < shapePoints.length` 필요, 실패 시 폴백)
  2. `turnIdx+1`이 유효하고 type 27이면 그 스텝의 `endShapeIdx`(진출 지점)로 진출 방위각:
     `PoiService.bearing(shapePoints[endIdx-1], shapePoints[endIdx])`
     (경계 가드 동일, `endIdx-1`이 해당 진출 maneuver의 `beginShapeIdx`보다 작아지지 않게)
  3. 위 두 값이 모두 계산됐으면 `signedBearingDiff` → `classify` → `vars['direction'] =
     방향.labelKo`, `key`는 그대로 `roundabout_enter_$phase` 유지(템플릿이 `{direction}` 쓰도록
     교체하므로 키 이름 자체는 안 바꿔도 됨).
  4. 계산 실패(경계 밖, 다음 스텝이 27이 아님 등) → 기존과 동일하게
     `key = 'roundabout_$phase'`(방향 없는 일반 문구)로 폴백.
- `:159-170`(`roundabout_exit && isImminent` 블록) — **통째로 삭제**. 이미 죽은 코드이고
  `{exit}` 주입 경로이므로 체크리스트 요구사항과 정확히 일치.

### 3. `assets/voice_packs/default_ko.json` 템플릿 교체

체크리스트 원문은 "4종"이라 했으나 재확인 결과 **현재 실제로 도달 가능한 `{exit}` 템플릿은
2개뿐**이다(`roundabout_exit_*` 계열은 S4b로 이미 비활성화돼 도달 불가 — RECON이 S4b 이전에
쓰였던 낡은 카운트로 보인다). 이 2개만 교체하면 목표(출구 번호 발화 완전 폐기)가 충족된다:

```json
"roundabout_enter_approach": "{dist}미터 앞 회전교차로에서 {direction} 방향입니다",
"roundabout_enter_imminent": "회전교차로에서 {direction} 방향입니다",
```

(`roundabout_exit_approach`/`roundabout_exit_imminent`/`roundabout_exit_imminent_named`는
S4b로 비활성화된 죽은 경로라 손대지 않아도 안전하지만, 코드에서 그 경로를 통째로 지우므로
JSON 쪽도 정리하고 싶으면 코더 재량 — 다만 이번 스코프의 필수 항목은 아니다.)

### 4. (우선순위 하향, 이번 세션 제외)

체크리스트의 "원형교차로인데 우회전이라고 안내함"(mini_roundabout이 type 26 대신 9/10으로
나오는 별개 증상) — 위 수정 시 어차피 (turn_right 이벤트로) 방향은 맞게 나가므로 이번엔
손대지 않는다.

## 검증 요구

- **단위테스트(순수 로직, 네트워크 의존 없이)**: `signedBearingDiff`/`classify` —
  경계값(정확히 45°, -45°, 0°, 180°/-180° wrap-around) + 위 프로브 표의 5개 실측 bearing
  쌍을 고정 fixture로 넣어 기대 버킷과 일치하는지.
- **`onProgress()` 통합테스트**: 합성 `shapePoints`/`ManeuverStep` 배열로 진입 26 + 진출 27
  쌍을 구성해 `vars['direction']`이 채워지고 `vars['exit']`가 더 이상 나타나지 않는지.
  진출 스텝이 없거나 타입이 다른 경계 케이스에서 `roundabout_$phase` 폴백으로 안전하게
  빠지는지.
- **정확성 검증(이번 세션에서 완결 불가, 마스터 확인 필요)**: 프로브 표의 좌/직/우 판정이
  **실제 도로 형상과 일치하는지**는 위성지도 육안 대조 또는 실기기 주행으로만 확정 가능하다
  (이 세션은 헤드리스 서버라 지도 이미지를 볼 수 없다). 완료 후 리포트에 검단 5개 조합의
  좌표·판정 결과를 표로 남길 테니, 지도에서 눈으로 대조 가능하면 확인 부탁.
- `flutter analyze` 이슈 0, `flutter test` 전건 통과(현재 419건 + 신규분)

## 완료 후

- `code-auditor` PASS 후 커밋, `CHECKLIST_0805_testride0802.md` §S6 `[x]`로 갱신
  (정확성 실측 대조 항목은 `[ ] 마스터 확인 대기`로 남김)
- `loop/MORNING_REPORT_0807_S6_roundabout_direction.md`에 프로브 좌표·판정 표 포함해 기록
