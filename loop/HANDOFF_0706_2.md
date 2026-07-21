# HANDOFF — YuruNavi (2026-07-06 세션 종료, 4번째 세션으로 인계)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장/출퇴근길). 질문은 ask_user_input.
2. **RECON → SPEC(=tick 동봉) → 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거, 하루 1회뿐.** T3(거동변경) 브랜치가 2개 이상 라이딩 대기면 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개로 배포.
4. **T3는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 개별 main 머지.
5. **commit-gate 훅:** `flutter analyze`(전체 0개, info 레벨도 fatal)+`flutter test` 강제. 작업 착수 전 baseline analyze 먼저 확인 — main에 사전 경고가 있으면 무관해도 먼저 없애야 커밋 가능(이번에도 재발함, 아래 §학습).
6. **tick.md 사고 주의(이번 세션 신규 교훈):** `git checkout -- loop/tick.md`는 "다른 브랜치의 이미 커밋된 tick.md와 충돌할 때"만 쓸 것. **새 브랜치 만들고 방금 tick.md에 쓴 미커밋 SPEC이 있는 상태에서 이 명령을 치면 그 SPEC이 통째로 날아간다** (이번 세션에 실제로 겪음 — 재작성으로 복구). 브랜치 이동 순서: ①먼저 checkout -b, ②SPEC은 그 다음에 쓴다, ③이미 써둔 SPEC이 있으면 checkout -- 하지 말 것.
7. **미커밋 잔존(무관, 손대지 말 것):** 루트 `.md` 파일들(MORNING_REPORT_*, RECON_*, REPORT_* 등)의 `D`+`??` 잔존 계속 유지 중. 여러 세션째 미커밋인데 이번 세션과 무관 — 임의로 커밋/삭제 금지.
8. 툴체인: Flutter 3.44.0 / Dart 3.12.0 stable.

---

## 🏆 이번 세션 성과 — #6 IC/출구 안내 슬라이스 C: 출구명 발화

**중요 사전 발견:** RECON_ic_guidance.md는 슬라이스 A/B가 "미구현"이라 적혀 있었으나 실제로는
**2026-07-02에 이미 다른 방식으로 구현·머지·라이딩검증 완료**되어 있었음(`1afb164`). 별도 `'ic'`
이벤트 키를 만드는 원안 대신, `ramp`/`exit` 이벤트 자체에 `guidance_profile.json`의
per-event tier override로 1000/400/120m 조기 티어를 부여하는 방식. **RECON을 그대로 믿지 않고
grep으로 현재 코드부터 재확인**해서 발견 — `loop/RECON_ic_guidance.md` 상단에 정정 기록 남겨둠.

**실제로 이번 세션에 한 작업 = 슬라이스 C만:**
- 브랜치 `feat/exit-name-voice` (main에서 분기, main 미머지 · **라이딩 전**)
- `ManeuverStep.exitName` 필드 추가 + Valhalla `sign.exit_name_elements` 파싱
- `voice_engine.dart`: ramp/exit 이벤트 + exitName 존재 시 `_named` 변형 키로 전환, `vars['exit_name']` 주입
- `voice_pack_service.dart`: `_named` 키가 팩에 없으면 베이스 키로 폴백(`_fast`와 동일 패턴)
- `default_ko.json`: `ramp_approach_named`/`ramp_imminent_named`/`exit_approach_named`/`exit_imminent_named` 4종 추가
- 테스트 4건 추가, analyze 0 / test 55 전체 통과
- **code-auditor가 발견:** `exit_name_elements` 다중 요소를 `join('')`(빈 문자열)로 이어붙이면 단어가
  들러붙음. Valhalla 소스(`/data/projects/valhalla-src/valhalla/odin/signs.h`) 확인 결과 기본
  구분자는 `/`이나 TTS가 "슬래시"라고 읽어버리므로 공백으로 수정(`join(' ')`) — 근거 검증 후 반영, 재검증 통과.
- main 사전 analyzer 경고 4건(unused field 2 + deprecated Radio 2)이 이번 브랜치에도 재발 —
  `feat/nav-reroute-ui`의 동일 수정을 cherry-pick 시도했으나 그 커밋이 무관한 course_sheet.dart
  추출과 뒤섞여 있어서 **cherry-pick 취소하고 수동으로 2파일만 재현**해서 별도 커밋으로 정리.

## 🏆 verify/ride-0706 갱신 — 3개 T3 브랜치 통합, APK 재빌드

`verify/ride-0706`에 `feat/exit-name-voice`를 3번째로 merge(`--no-ff`, 충돌 없음,
`routing_service.dart` auto-merge). analyze 0 / test 55 / build 성공.
**APK는 빌드만 완료, 아직 폰에 scp/install 안 함** (사용자가 이번 세션엔 보류 요청).
리포트 갱신: `loop/REPORT_verify_ride0706.md` (3개 브랜치 검증 체크리스트 포함).

---

## ▶ 다음 순번 (4번째 세션에서 이어감)

**0순위 — 배포 확인:** `verify/ride-0706`(HEAD `e7a52ef`) APK가 아직 폰에 안 깔려있음.
**내일(2026-07-07) 새벽 퇴근길에 실주행 검증 예정, 하루 1회뿐** — 세션 시작 시 먼저
scp + `adb uninstall`/`install -r` 진행 여부부터 확인할 것. 이미 설치돼 있다면 스킵.

**1순위 — 라이딩 결과 청취:** PASS면 `feat/reroute-heading`, `feat/nav-reroute-ui`,
`feat/exit-name-voice` **각각 개별로** main 머지(merge 순서 무관, 서로 독립 —
`verify/ride-0706` 자체는 머지 안 함). FAIL이면 3개 중 어느 기능 문제인지부터 특정
(로그 태그: REROUTE=#1, GUIDE/카드UI=#2, TTS `_named`=#3).

**2순위 — 나머지 안내로직:**
- b) **#3 급커브 누락 / R4 사거리 과다발화**: RECON 없음 — 신규 RECON부터.
- **터널/교량 안내**: `RECON_underpass.md`만 존재, `/trace_attributes` 별도 호출 설계 필요.

**보류 중 (순서 무관):**
- `feat/tts-audibility`: main과 크게 divergence, 리베이스/재작업 필요.
- **#7 지도 스타일**: `RECON_style_loading.md` 완료. 호스트 불일치(스타일 JSON `tiles.westinx.com` vs CLAUDE.md `192.168.0.57`) 미해결.
- **로터리 미태깅(고덕좌교로, way_id=1304219907)**: OSM 데이터 이슈, 이 리포로 해결 불가, 보류.

---

## 🔑 이번 세션 핵심 학습

- **RECON은 stale 될 수 있다 — 이번엔 "미구현"이라 적힌 게 이미 구현·검증까지 끝나 있던 케이스.**
  실행 전 항상 grep으로 현재 코드 상태부터 확인. (`RECON_ic_guidance.md`에 정정 기록 남김)
- **cherry-pick도 stale 대응이 필요하다:** "이 파일의 이 수정만 필요하다"고 생각한 과거 커밋이
  실제로는 다른 무관한 변경과 한 커밋에 뒤섞여 있을 수 있음 — `git show <sha> --stat`으로
  먼저 확인 후 cherry-pick할 것. 이번엔 확인 없이 cherry-pick했다가 무관한 파일까지
  딸려와서 `git reset --hard`로 되돌리고 수동 재현함.
- **tick.md는 "쓴 직후엔 건드리지 말 것"** — §6 참고, 이번 세션 실수 그대로 반복하지 말 것.
- **Valhalla 자체 소스가 로컬에 있음** (`/data/projects/valhalla-src`) — 라우팅 응답 필드의
  실제 의미/기본값이 궁금하면 RECON 문서보다 이쪽을 직접 확인하는 게 더 빠르고 정확함.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개(단, 하나의 기능 단위면 여러 줄 변경도 한 커밋 허용), 각 커밋 전 commit-gate 훅이 `flutter analyze`(전체 0개)+`flutter test`(현재 55/55) 강제.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall com.example.yurunavi` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.

## 📌 참고

- 현재 `main` HEAD: `3ad75fd` (변동 없음 — 이번 세션도 main엔 아무것도 머지 안 함).
- 대기 브랜치: `feat/reroute-heading`(`c41859d`) / `feat/nav-reroute-ui`(`acb36f0`) /
  `feat/exit-name-voice`(`4f656d4`) / `verify/ride-0706`(`e7a52ef`, 3개 통합, 라이딩 전용).
- 패키지: `com.example.yurunavi`.
- IC/터널 안내 실측 데이터: `loop/recon_route.json`.
