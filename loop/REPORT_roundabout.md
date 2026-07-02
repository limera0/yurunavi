# REPORT — 회전교차로 안내 (#4, 슬라이스 1+2+3)

브랜치: `feat/roundabout-guidance` (main 머지 금지, T3). 슬라이스4(GPS 스냅 window)는 이번 범위 제외 — RECON_roundabout.md "추가 조사" 항목으로 남겨둠.

## 커밋 (5개, analyze 신규 0, `flutter test` 51/51 green)

1. `0206cd8` feat(guidance): roundabout dedicated short-segment tiers
   - `assets/config/guidance_profile.json:35-42` — `roundabout` 이벤트에 전용 `tiers` 추가. 핵심: `min_entry_m:0` tier의 `points_m`가 `[20]`(비어있지 않음) — 기존엔 전역 폴백의 `points_m:[]`를 그대로 써서 진입 46m/로터리 내부 53m 같은 짧은 세그먼트에서 pending 포인트가 완전히 비어 무음이 됐던 게 근본 원인(RECON §3).

2. `4ef0d6d` feat(routing): parse roundabout_exit_count
   - `lib/services/routing_service.dart:42` — `ManeuverStep.roundaboutExitCount` (nullable) 필드 추가.
   - `lib/services/routing_service.dart:434` — `_collectManeuvers`에서 `m['roundabout_exit_count']` 파싱 주입. Valhalla가 type26 maneuver에 이미 제공하는 필드였으나 기존엔 즉시 버려짐(RECON §4).

3. `37f5cd3` feat(voice): split roundabout enter/exit + exit-count phrasing
   - `lib/features/navigation/voice_engine.dart:19-20` — `eventForType`가 type26→`roundabout_enter`, type27→`roundabout_exit`로 분리(기존엔 둘 다 `'roundabout'`로 뭉개짐).
   - `lib/features/navigation/voice_engine.dart:26-27` — **설계 판단 (SPEC에 없던 보강)**: `guidance_profile.json`의 `roundabout` 설정 키는 단수형 그대로 유지했기 때문에(위 C1), split된 이벤트 문자열을 그대로 `tiersForEvent`/`isEnabled` 조회에 쓰면 `roundabout_enter`/`roundabout_exit` 키가 없어 조회가 실패 → 전역 폴백 재발(=이번 작업의 핵심 목적인 무음 버그가 되살아남). `_profileEventKey()` 헬퍼로 두 이벤트를 `'roundabout'`로 정규화해 tier/enabled 조회는 정규화된 키로, 발화 템플릿 키(`'${event}_$phase$suffix'`)는 split된 원본 이벤트로 분리했다. 이 지점은 code-auditor가 별도로 검증(PASS, "highest-risk item" 확인).
   - `lib/features/navigation/voice_engine.dart:59,68-75` — `roundabout_enter`이고 `roundaboutExitCount`가 있으면 `vars['exit']` 주입 + `roundabout_enter_*` 키 유지; 없으면 `roundabout_*`(기존 범용 키)로 폴백해 `{exit}` 미해결 텍스트가 발화되는 것을 방지.

4. `3b70ba2` feat(voice): add roundabout enter/exit ko phrase templates
   - `assets/voice_packs/default_ko.json:29-32` — `roundabout_enter_approach`/`_imminent`(출구번호 포함), `roundabout_exit_approach`/`_imminent`(진출 전용 문구) 4키 추가. 기존 `roundabout_approach`/`_imminent`(27-28행)는 폴백용으로 그대로 유지.

5. `7f5a9c6` test(voice): roundabout enter/exit + exit-count
   - `test/voice_engine_roundabout_test.dart` 신규, 5케이스 (A: eventForType 매핑 x2, B: exit count 있음→`roundabout_enter_*`+`vars['exit']`, C: exit count 없음→`roundabout_*` 폴백, D: 진출→`roundabout_exit_*`).
   - `flutter test test/voice_engine_roundabout_test.dart`: 5/5 green.
   - `flutter test`(전체): 51/51 green — 기존 `voice_engine_test.dart`(11) / `voice_engine_speed_test.dart`(4) 포함 회귀 없음.

## 라이딩 검증 체크리스트 (실측 전까지 미완료 상태로 간주)
- [ ] 회전교차로 진입 시 "N번째 출구" 발화가 실제로 들리는지 (exitCount 파싱·전달 확인)
- [ ] 진입("...N번째 출구")과 진출("...진출") 문구가 서로 다르게 구분되는지
- [ ] 짧은 로터리(진입로/내부 세그먼트 <100m급)에서 기존에 있던 무음이 사라졌는지
- [ ] exitCount가 응답에 없는 로터리에서도(폴백 경로) 최소 "회전교차로" 발화는 나오는지

## 범위 밖 (다음 판단)
- 슬라이스4: `route_progress_provider.dart`의 GPS 스냅 window(`_kSnapWindow=50`)가 로터리 같은 짧은 연속 세그먼트에서 activeStepIdx를 건너뛸 위험 — RECON_roundabout.md "추가 조사" 항목. 코드 변경 전 재현 테스트 필요, 이번 티어/문구 수정 결과 라이딩 검증 후 별도 판단.
