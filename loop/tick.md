# TICK — #2 _arrived 리셋 수정 + #4-b 회전교차로 카드 출구번호. main에 #4 머지 완료 전제. T3=라이딩 전 머지 금지.
워크플로: 커밋 1=파일1=논리1, 각 경계 flutter analyze 신규0.

## Part A — #2 수정 (브랜치 feat/arrival-dialog-dismiss)
- `git checkout feat/arrival-dialog-dismiss && git merge origin/main`(최신화, 충돌 시 멈추고 보고).
- C1: nav_screen.dart _reroute() 진입부, 다이얼로그 dismiss 하는 그 지점(:288 근처)에서
  다이얼로그를 닫을 때 **`_arrived = false;` 도 함께 리셋**.
  근거: 재탐색=새 경로 적용이므로 "도착 완료 안 됨" 상태로 되돌려야 2차 도착이 재트리거됨.
  (재탐색은 도착 전엔 `_arrived`가 이미 false라 무해 — 단일 규칙 안전.)
  커밋: "fix(nav): reset _arrived on reroute so re-arrival re-triggers (#2 NG)"

## Part B — #4-b 카드 출구번호 (브랜치 feat/roundabout-card-label, main에서 분기)
- `git checkout main && git checkout -b feat/roundabout-card-label`
- C2: nav_screen.dart _labelForType(회전교차로 type 26 라벨 생성부, :1061-1085 근처)가
  ManeuverStep.roundaboutExitCount(이미 main에 파싱됨)를 참조해
  "회전교차로 진입" → exitCount 있으면 "회전교차로 {n}번째 출구"로 표기.
  exitCount null이면 기존 "회전교차로 진입" 유지(폴백).
  _labelForType가 type만 받으면 step/exitCount를 넘기도록 시그니처 최소 확장(호출부 동기 수정).
  커밋: "feat(nav): show roundabout exit number on guidance card (#4-b)"

## Part C — 재검증 합본 빌드
- `git checkout main && git checkout -b verify/ride-0703b`
- `git merge --no-ff feat/arrival-dialog-dismiss -m "verify: #2 arrived reset"`
- `git merge --no-ff feat/roundabout-card-label -m "verify: #4-b card exit number"`
  (충돌 시 멈추고 파일명 보고.)
- flutter analyze 신규0, flutter test 전체 green, flutter build apk --debug 성공.
- loop/REPORT_ride0703b.md: 변경 file:line·충돌여부·테스트·APK경로 기록·커밋.

종료: verify/ride-0703b 빌드 완료. 검증 전용 브랜치이므로 main 머지 금지.
라이딩 PASS 시 feat/arrival-dialog-dismiss·feat/roundabout-card-label 각각 개별 main 머지.