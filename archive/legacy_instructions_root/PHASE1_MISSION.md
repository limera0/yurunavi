# PHASE1_MISSION — 출발 정확성
# 오케스트레이터(메인/Opus) 운영 지침. 한 세션에서 RECON→자기판단→구현(AMBER)→빌드→보류→리포트까지 자율 진행.
#
# ★ 이 미션은 RECON과 실행을 한 세션에서 잇는다. 안전장치는 "인라인 중지 게이트"가 아니라:
#   (1) RECON은 읽기전용 → 그 자체로 안전
#   (2) 모든 코드 변경은 AMBER 브랜치 = main 미반영 = 완전 가역
#   (3) 사람에게 묻는 지점은 단 하나(가설 N 판정 = 설계방향 분기)
#   → 따라서 "통합 프롬프트 = 게이트 무시" 위험이 제거된다(핸드오프 §7 우려 해소).

## 불변 규칙
- 한 커밋 = 한 파일 = 한 논리변경. 추측 금지. 모든 주장 file:line 근거.
- 라인번호는 편집마다 드리프트 → 매 편집 직전 재-grep. 스테일 라인번호 신뢰 금지.
- 시크릿 커밋 금지. push 금지. rm -rf / git push --force / 대량삭제 금지. 스코프 확장 금지.
- 빌드/analyze 통과 ≠ 동작 증명. 이 결과물은 폰 주행으로만 검증됨 → AMBER, **main 머지 금지**.
- 코드작업 = flutter-coder(sonnet) 위임. 검토 = code-auditor 위임. 서브에이전트는 서브에이전트 spawn 불가
  → 오케스트레이터가 coder→결과→auditor 순차 체이닝.

## 스코프 울타리 (벗어나면 정지)
이번 Phase 1 = "출발 정확성"만. 고칠 것:
  (1) GPS 락 전 경로계산/표시 → 진짜 첫 GPS fix 후로 게이팅 (홈 + 내비 둘 다)
  (2) _announceStep: 현재스텝 _steps[_stepIdx] → 다가오는 스텝 _stepIdx+1, 정적 step.dist → live remaining
  (3) 출발 step(type=1): "Xm 앞 출발" 버그 → "출발합니다" (거리·방향 안 읽음)
❌ 하지 말 것 (= Phase 2~5, 건드리면 스코프 위반):
  500/300/50 임계값 시스템, 음성팩 모듈 구조, UI 레이아웃, 거리 보간(5초→부드럽게),
  지도회전/속도줌 튜닝, 고가도로 안내.
※ (3) 멘트 문자열은 Phase 2 음성팩이 갈아끼울 수 있게 최소 변경만. 구조화는 Phase 2 몫.

## M0 — 진입 게이트 (코드 변경 금지)
- `git status --porcelain` 비어있나? 아니면 정지 + MORNING_REPORT 기록.
- 베이스 브랜치 = `feat/guidance-fix` (T1~T3 검증분 보존). 없으면 정지 + 보고.

## M1 — RECON (읽기전용) → flutter-coder 위임
flutter-coder에 위임 (Read/Grep만, **Edit 금지**). 결과를 `RECON_startup_accuracy.md`로 저장.
A. 초기 경로계산 시점: 앱 시작~첫 fetchRoutes 호출 추적(file:line). 그 시점 origin이
   실GPS현위치 / _lastKnown / 광화문폴백 중 무엇인지. 첫 fix 대기 가드 유무.
   앵커: nav_screen.dart 폴백 _kInitialMapView=광화문 :28, 초기카메라 :833 /
         main_map_screen.dart 폴백 kInitialMapView(36.5,127.5) :35, 초기줌 :117.
B. 첫 GPS fix 딜레이: _onPosition(:294) 첫 호출 흐름, getPositionStream 정확도/거리필터 file:line.
   첫 fix 전 표시되는 위치/거리가 폴백 기반인지.
C. _announceStep off-by-one: _announceStep(:508)이 _steps[idx] 사용 → upcoming 아님 확인.
   출발 step(type=1) 분기 유무(없으면 "Xm 앞 출발" 발화 원인).
   step.dist(정적) vs live remaining(:411). 400m예비(:421)는 remaining인데 _announceStep은 정적 → 불일치.
판정: 슬라이드1(서울 폴백) + 슬라이드3(거리 통째 오류)가 'GPS락 전 경로계산' 한 뿌리인가? → **Y / N / 부분**.

## M2 — 오케스트레이터 자기판단 (★ 핵심)
오케스트레이터가 `RECON_startup_accuracy.md`를 **직접 읽고** 분기한다(사람에게 안 물음):
- 판정 = Y 또는 부분 → **M3 진행** (가설대로 GPS-fix 게이트 수정).
- 판정 = N → **정지.** 구현 금지. RECON 발견사항을 MORNING_REPORT에 적고
  "설계방향 갈림, 마스터 판단 필요"로 마감. (이 한 곳만 사람 게이트)

## M3 — 구현 (AMBER, 브랜치만) → flutter-coder 위임
- 브랜치 생성: `phase1/startup-accuracy` (base feat/guidance-fix). 체크포인트 커밋.
- RECON이 짚은 **실제 file:line** 기준 최소 수정. RECON에 없는 수정 발명 금지.
- 커밋 분할 (한 커밋 = 한 파일 = 한 논리):
  · C1: 출발 origin 정확성 — 진짜 첫 GPS fix 후 경로계산/표시 (RECON이 지목한 파일).
  · C2: 나머지 화면(홈/내비) 동일 게이트 적용.
  · C3: _announceStep → upcoming(_stepIdx+1) + live remaining.
  · C4: 출발 step → "출발합니다".
  (RECON 결과에 따라 커밋 수 가감 가능. 한 커밋=한 파일 원칙은 불변.)
- 각 커밋 직후 code-auditor 실행. FAIL → 최소수정 → 재감사 (최대 3회).
  3회 초과 시 해당 항목 BLOCKED 기록 후 다음 커밋으로.

## M4 — 빌드 + 보류 (머지 금지)
- `flutter analyze` 클린 확인.
- `flutter build apk --debug` 성공 → `outputs/yurunavi_phase1_$(date +%Y%m%d).apk` 복사.
- **main 머지 절대 금지.** 작업은 phase1/startup-accuracy 브랜치에 그대로 둔다.

## M5 — MORNING_REPORT.md 작성 (종료 시 1회)
```
# MORNING REPORT — Phase 1 (출발 정확성) — <date>
## RECON 판정
- 가설(GPS락 전 경로계산): Y / N / 부분  (근거 file:line)
## 변경 (AMBER · 브랜치 phase1/startup-accuracy · main 미반영)
- C1 <commit> <file:line> : <무엇을 왜>
- C3 <commit> <file:line> : _announceStep upcoming+live
- C4 <commit> <file:line> : 출발 "출발합니다"
## ★ 마스터 폰 주행 체크리스트 (이것만 확인)
1) 앱 켤 때 서울 안 뜨고 현위치에서 시작? (홈 + 내비)
2) 출발 시 TTS가 "출발합니다"라고만? (거리/방향 안 읽음)
3) 첫 회전까지 거리가 실제와 일치? (예전 101m → 실제 ~10m)
## APK
- outputs/yurunavi_phase1_<date>.apk
## BLOCKED (있으면)
- <항목> : 사유 file:line
## Phase 2 인계
- 500/300/50 임계값 + 음성팩 모듈 구조는 다음 세션. 이번엔 정확성만.
```
