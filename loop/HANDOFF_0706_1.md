# HANDOFF — YuruNavi (2026-07-06 세션 종료, 3번째 세션으로 인계)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장/출퇴근길). 질문은 ask_user_input.
2. **RECON → SPEC(=tick 동봉) → 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거, 하루 1회뿐.** 사용자는 출퇴근길에만 검증 가능 — **T3(거동변경) 브랜치가 2개 이상 동시에 라이딩 대기 상태면 반드시 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개로 배포**(이번 세션 교훈 §성과3). 따로따로 주면 하루에 하나밖에 검증 못 해서 하루를 날림.
4. **T3는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 **개별** main 머지 (verify 통합 브랜치 자체는 머지 안 함, 개별 히스토리 보존용 임시 브랜치).
5. **commit-gate 훅 주의(신규 확인됨):** `loop/hooks/commit-gate.sh`(untracked, `.claude/settings.json`이 연결)가 모든 `git commit` 전에 `flutter analyze`+`flutter test`를 강제 실행해 실패 시 커밋을 막음. **analyze는 "신규 0개"가 아니라 "전체 이슈 0개" 요구** — info 레벨(deprecated_member_use 등)도 fatal 취급됨. 작업 시작 전 baseline analyze를 먼저 돌려서 사전 경고가 있으면 (설사 내 작업과 무관해도) 먼저 없애야 이후 어떤 커밋도 가능.
6. tick.md 충돌 상습: 브랜치 이동/머지 전 `git checkout -- loop/tick.md`.
7. **미커밋 잔존(무관, 손대지 말 것):** 루트의 `.md` 파일들(MORNING_REPORT_*, RECON_*, REPORT_* 등 100+건)이 `loop/`로 옮겨지는 정리 작업이 계속 미커밋 상태(`D`+`??`)로 남아있음. 이번 세션 작업과 무관 — 누군가의 진행 중 정리로 추정, 임의로 커밋/삭제하지 말 것.
8. 툴체인: Flutter 3.44.0 / Dart 3.12.0 stable.

---

## 🏆 이번 세션 성과 1 — U턴 브랜치 main 위 리베이스, 라이딩 대기

`feat/reroute-heading`(main@3ad75fd 위로 **충돌 없이 리베이스**, HEAD `c41859d`, 2커밋) — analyze 0 / test 51 / build 성공. 코드 자체는 지난 세션(HANDOFF_0705_1)에서 완성된 것, 이번엔 최신 main(카메라 3부작) 위로 올리기만 함. **아직 라이딩 미검증.**

## 🏆 성과 2 — 재탐색 버튼 UI 전면 재작업 (`feat/nav-reroute-ui`, main+5커밋)

- 우측 원형 ↻ 버튼 제거 → 하단카드 "재탐색" 텍스트 버튼(`ETA | 재탐색 | 종료`)
- 3코스 재선택 시트 재사용: `CourseSheet`/`RouteInfo`/`RouteCard`를 `main_map_screen.dart`에서 `lib/core/widgets/course_sheet.dart`로 추출해 홈/내비 공용화
- 흐름: 재탐색 탭 → 경로 전체 오버뷰 + 3코스 프리페치 → 카드탭은 **프리뷰만**(실주행 경로 안 건드림) → 슬라이더 확정 시 커밋(경로/ETA/안내 갱신) → 닫기(취소) 시 원래 경로·색·`mapInteractionProvider` 상태로 완전 복원
- **code-auditor가 라이딩 전 레이스 버그 3종 발견 → 즉시 수정:**
  (a) 시트 열려 있는 동안 자동 이탈재탐색(`_reroute`)이 끼어들어 프리뷰를 덮어쓰는 문제
  (b) 지도 터치 10초 자동복귀 타이머가 오버뷰 가드를 무시하고 카메라를 강제로 되돌리는 문제
  (c) 시트 취소 시 `mapInteractionProvider`의 `allRoutes`/`allRouteMeta`에 프리뷰 잔여가 남는 문제 (+ 요청 세대 카운터로 stale fetch 응답 가드)
- 부수 커밋: 사전 존재하던 analyzer 경고 2건(unused field, deprecated Radio→RadioGroup) 정리 — commit-gate 훅 통과에 필수였음
- **알려진 한계(미해결, 향후 참고):** 코스 프리페치가 `_reroute`의 40m 전진오프셋 로직 없이 현재 raw 위치를 그대로 origin으로 씀 — 정상 주행 중 재탐색 버튼 조작에선 무해할 것으로 판단했으나 실주행 미검증.

## 🏆 성과 3 — 두 T3 브랜치를 하나의 라이딩용 APK로 합본

사용자가 "출퇴근길 1회만 검증 가능, 하나만 되어 있으면 하루 날림"이라 지적 → `verify/ride-0706` = main + `feat/reroute-heading` + `feat/nav-reroute-ui` (`--no-ff` 병합 2건, **충돌 없음** — 둘 다 `nav_screen.dart`의 `_reroute()`를 건드리지만 서로 다른 라인). analyze 0 / test 51 / build 성공. 리포트: `loop/REPORT_verify_ride0706.md`.
**`verify/ride-0706`은 검증 전용, main 머지 금지.** PASS 시 `feat/reroute-heading`·`feat/nav-reroute-ui`를 각각 개별 main 머지.

---

## 🔑 이번 세션 핵심 학습

- **RECON은 시간이 지나면 stale — 실행 전 "현재 코드가 RECON과 같은가" 재확인 필수.** 예: `RECON_home_ui.md`의 3항목(화살표 크기·홈 마커 회전·코스색 배선)이 전부 지난 세션 카메라 3부작 머지(`3ad75fd`)로 이미 완료돼 있었음 — 재작업 없이 스킵. `RECON_reroute_button.md`가 우려한 "bearingTo 별도 게이팅 필요"도 카메라 통합 커밋(`1eb96b9`)으로 이미 해소됨. **RECON을 맹신하지 말고 grep으로 먼저 현재 상태를 찍어볼 것.**
- **여러 T3 브랜치가 동시에 라이딩 대기 상태면, 검증 기회가 제한적인 사용자에겐 반드시 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개 배포.** 이 저장소엔 이미 그 관례가 있었음(`verify/ride-0703b`, `verify/ride-2branch`) — 처음부터 그걸 알았으면 더 빨랐을 것. **다음부터 T3 브랜치가 2개 이상 쌓이면 먼저 이 패턴부터 적용.**
- **commit-gate 훅이 "전체 analyze 0개"를 요구** — 무관한 사전 경고(pre-existing warning)도 내 커밋을 막는다. 작업 착수 전 baseline analyze로 확인하는 습관.

---

## ▶ 다음 순번 (3번째 세션에서 이어감)

**0순위 — 확인만:** `verify/ride-0706` 라이딩 결과 청취. PASS면 두 feat 브랜치 개별 main 머지(merge 순서 무관, 서로 독립). FAIL이면 어느 쪽 문제인지부터 특정.

**3순위 — 안내로직** (RECON 완비된 것부터 SPEC 작성 후 바로 구현):
- a) **#6 IC/터널 안내**: `RECON_ic_guidance.md` + `RECON_underpass.md` 완비. 구현 슬라이스 제안: **A**(IC 1000m 조기 티어, JSON 설정만, 무위험) → **B**(`eventForType()`에서 ic/ramp event key 분리, 순수함수 교체) → **C**(출구명 파싱: `ManeuverStep.exitName` 필드 추가 + `sign.exit_name_elements` 파싱 + TTS 치환). 터널/교량 안내는 `/trace_attributes` 별도 호출 설계 필요(RECON_underpass.md 하단) — 별도 슬라이스.
- b) **#3 급커브 누락 / R4 사거리 과다발화**: RECON 없음 — 신규 RECON부터.

**보류 중인 나머지 (순서 무관, 필요시 픽업):**
- `feat/tts-audibility`: main과 크게 divergence(과거 RECON 다수 삭제 diff 포함) — 단순 머지 불가, 리베이스/재작업 필요.
- **#7 지도 스타일**: `RECON_style_loading.md` 완료. 실행 전 호스트 확인 필요 — 스타일 JSON엔 `tiles.westinx.com`, CLAUDE.md엔 `192.168.0.57` 기재, 실제 운영환경 불일치 미해결.
- **로터리 미태깅(고덕좌교로, way_id=1304219907)**: OSM 그래프 데이터 이슈(`junction=roundabout` 미태깅), 이 리포 코드로 해결 불가 — 별도 대형 프로젝트(OSM 정비 AI)로 보류.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개(단, 시트처럼 하나의 기능 단위면 여러 줄 변경도 한 커밋 허용), 각 커밋 전 commit-gate 훅이 `flutter analyze`(전체 0개)+`flutter test`(51/51) 강제.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall com.example.yurunavi` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.

## 📌 참고

- 현재 `main` HEAD: `3ad75fd` (카메라 3부작 머지, 변동 없음 — 이번 세션은 main에 아무것도 머지 안 함).
- 대기 브랜치: `feat/reroute-heading`(HEAD `c41859d`) / `feat/nav-reroute-ui`(HEAD `acb36f0`) / `verify/ride-0706`(HEAD `23563b4`, 라이딩 전용 합본).
- 패키지: `com.example.yurunavi`.
- IC/터널 안내 실측 데이터: `loop/recon_route.json` (RECON_underpass.md의 강변북로/경수대로/남산터널 경로 curl 응답).
