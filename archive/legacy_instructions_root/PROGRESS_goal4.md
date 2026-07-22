# PROGRESS_goal4.md — 증상4 재탐색 maneuver·TTS 복구

## TASK 1 — 사전검증 게이트 ✅ (읽기전용, 커밋 없음)
- `_steps`: `late final List<_TurnStep> _steps;` line 100 — RECON과 일치 ✓
- `_lastAnnouncedIdx`: line 86, `_stepEndDistM`: line 87, `_preAnnounced`: line 88, `_stepIdx`: line 101 ✓
- initState `_steps` 생성: lines 145-151, `_computeStepEndDistances()`: line 153 ✓
- `_reroute` setState: lines 458-461 — `_routePoints`/`_durationMin`만 갱신, maneuvers 버림 ✓ RECON 확정
- `_TurnStep.fromManeuver`: factory at line 1163 ✓
- `routes[selIdx].maneuvers`: `List<ManeuverStep>` (RouteResult.maneuvers, routing_service.dart:51) ✓
- `_announceStep(int idx)`: line 483, `_updateStepByDistance(LatLng loc)`: line 386, `_computeStepEndDistances()`: line 360 ✓
- ⚠️ RECON 라인번호 차이(정찰 후 코드 변경으로 밀림) — 치명적 구조 차이 없음, 진행 가능
- ⚠️ 설계 적응: TASK3 스펙은 `_applyRouteGuidance(RouteResult route)`지만 initState에 RouteResult 없음.
  → `_applyRouteGuidance(List<ManeuverStep> maneuvers)` 사용 (두 호출부 모두 리스트 직접 보유)

## TASK 2 — _steps final 해제 ✅
- `late final` → `late` (line 100). flutter analyze 통과 (기존 unused_shown_name 경고만).
- commit: 8ce980b "refactor(nav): make _steps mutable for reroute rebuild"

## TASK 3 — _applyRouteGuidance 헬퍼 추출 ✅
- `_applyRouteGuidance(List<ManeuverStep> maneuvers)` 정의 (line ~369): steps 생성, _computeStepEndDistances, idx/flag 리셋.
- 설계 적응: RouteResult 대신 List<ManeuverStep> 인자 (두 호출부 모두 리스트 직접 보유).
- 기존 pre-existing `unused_shown_name(max)` 경고도 함께 수정 (analyze 0-error 기준 맞춤).
- commit: 4108368 "refactor(nav): extract _applyRouteGuidance helper"

## TASK 4 — initState 헬퍼 치환 ✅
- initState의 _steps 생성 + _computeStepEndDistances 블록 → `_applyRouteGuidance(widget.maneuvers)` 1줄로 대체.
- `// ignore: unused_element` 제거 (메서드가 이제 참조됨).
- analyze 0 issues 통과.
- commit: ff1c474 "refactor(nav): use _applyRouteGuidance on initial route"

## TASK 5 — _reroute 헬퍼 호출 + step0 재발화 ✅
- `_reroute` setState 블록에 `_applyRouteGuidance(routes[selIdx].maneuvers)` 추가.
- setState 직후 `_announceStep(0)` 호출 (새 step0 TTS 재발화).
- analyze 0 issues 통과.
- commit: 5269b01 "fix(nav): rebuild maneuver/TTS state on reroute"

## TASK 6 — 정합성 점검 + 최종 빌드 ✅
- `_traveledDistM`: `_routePoints` 기반 → 재탐색 후 newPoints로 교체되므로 올바른 새 경로 기준으로 동작 ✓
- `_stepEndDistM`: `_applyRouteGuidance` 내 `_computeStepEndDistances()` 재호출로 새 steps 기준 누적거리 갱신 ✓
- `_stepIdx=0` / `_lastAnnouncedIdx=-1` 리셋 후 `_announceStep(0)` 호출 → 중복방지 게이트 통과 ✓
- 미해결 항목: 없음 (증상4 범위 내 모두 해결)
- flutter analyze: No issues (exit 0)
- APK: build/app/outputs/flutter-apk/app-debug.apk (빌드 성공, Kotlin Gradle 경고는 pre-existing)

---

## 최종 요약

### 완료 TASK 및 커밋 해시
| TASK | 커밋 | 설명 |
|------|------|------|
| T2 | 8ce980b | refactor(nav): make _steps mutable for reroute rebuild |
| T3 | 4108368 | refactor(nav): extract _applyRouteGuidance helper |
| T4 | ff1c474 | refactor(nav): use _applyRouteGuidance on initial route |
| T5 | 5269b01 | fix(nav): rebuild maneuver/TTS state on reroute |

### 미해결 항목
없음 (증상4 완전 해결).
증상3(heading 미전달)은 이번 세션 범위 밖 — RECON_reroute.md §2 참조.

### 퇴근 후 폰 테스트 체크리스트
1. 앱 실행 → 경로 탐색 → 내비 화면 진입 — 첫 안내 카드·TTS 정상 발화 확인 (회귀 없음)
2. 의도적으로 경로 이탈 (20m 이상, 3초 유지) → 재탐색 트리거 대기
3. 재탐색 완료 후:
   - [ ] 안내 카드가 새 경로의 첫 번째 maneuver로 바뀌었는가?
   - [ ] TTS "경로 안내 시작" 또는 새 첫 step 음성 재발화되었는가?
   - [ ] 주행 재개 시 카드가 step 순서대로 진행되는가?
   - [ ] 재탐색 후 ETA(durationMin) 갱신되었는가?
4. 선택: 재탐색 2회 연속 → 매번 카드 리셋 확인
