# HANDOFF — YuruNavi (2026-07-06 세션 종료, 7번째 세션으로 인계)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장/출퇴근길). 질문은 ask_user_input.
2. **RECON → SPEC(=tick 동봉) → 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거, 하루 1회뿐.** T3(거동변경) 브랜치가 2개 이상 라이딩 대기면 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개로 배포.
4. **T3는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 개별 main 머지.
5. **commit-gate 훅:** `flutter analyze`(전체 0개, info 레벨도 fatal)+`flutter test` 강제. **이번 세션에 main 자체를 정리함(아래 성과 참고)** — `d9d78d5`(unused field 2 + deprecated Radio 2 정리)를 main에 직접 cherry-pick(`198e936`). 이제 main HEAD(`419b730`)는 analyze 0 상태이므로, **새 T3 브랜치를 main에서 분기할 때 더 이상 사전 정리 cherry-pick이 필요 없을 것으로 기대** — 단, 다음 세션에서 새 브랜치 분기 시 실제로 analyze 0으로 시작하는지 한 번 확인해서 이 가정을 검증할 것(만약 여전히 경고가 뜬다면 이 HANDOFF의 가정이 틀린 것이니 원인 재조사).
6. **tick.md 사고 주의:** `git checkout -- loop/tick.md`는 "다른 브랜치의 이미 커밋된 tick.md와 충돌할 때"만. 새 브랜치+미커밋 SPEC 상태에서 치면 SPEC이 날아감. 순서: ①checkout -b, ②그 다음 tick.md 작성. **verify/ride-\* 로 merge할 때 tick.md 충돌은 항상 발생함(각 T3 브랜치가 자기 SPEC을 씀) — `git checkout --theirs loop/tick.md`로 들어오는 브랜치 버전 채택이 관례.**
7. **미커밋 잔존(무관, 손대지 말 것):** 루트 `.md`(MORNING_REPORT_*, RECON_*, REPORT_* 등)의 `D`+`??` 잔존 계속 유지. 이번 HANDOFF_0706_5.md도 동일하게 커밋 안 함(관례 유지).
8. 툴체인: Flutter 3.44.0 / Dart 3.12.0 stable.

---

## 🏆 이번 세션(6번째) 성과

### 1) R5(지하차도/고가 "진출" 오안내) — 실측 완료, 조치 불필요로 종결
`RECON_voice_v2.md` 마지막 남은 보류 항목. R4와 동일하게 curl 실측으로 검증:
- 8경로/98maneuver(exit/ramp 11건) 표본에서, exit/ramp maneuver(type 17-21) 분기점이 tunnel
  edge와 접한 사례 **0건**, bridge 접함은 1건뿐이고 그 1건도 실제 고속도로 출구(한강교량 위
  46번 출구) — 지하차도 오안내가 아님.
- 진입 edge 11/11 모두 `use=ramp`, 도로등급도 전부 간선급 이상 — 이 타일셋 기준 Valhalla가
  exit/ramp를 잘못 붙이는 사례가 없음. trace_attributes 레이어 신설 근거 없음 → **구현 안 함,
  실주행 반례 나오면 재조사**로 종결.
- `RECON_underpass.md`(D절 추가) + `RECON_voice_v2.md`(R5 결론 갱신) 커밋, **main에 직접 커밋**
  (T3 아님, 순수 recon). `RECON_voice_v2.md`의 R1~R5 전부 종결됨.

### 2) main 사전 analyze 이슈 4개 근본 정리
매 세션 새 T3 브랜치마다 `d9d78d5`를 재-cherry-pick하던 반복 우회를 **main에 직접 반영**해서
끝냄(`198e936`). 이제 main 자체가 analyze 0.

### 3) #7 지도 스타일 호스트 불일치 — 실은 이미 해결돼 있던 stale 문서였음
`CLAUDE.md`가 "192.168.0.57 LAN IP + cleartext 예외" 상태로 기술돼 있었지만, 실제 코드
(`assets/images/osm_liberty_yurunavi.json`, `routing_service.dart`, `native_engine.dart`,
`network_security_config.xml`)는 이미 2026-06-05(`9b31cf8`)에 `*.westinx.com` HTTPS로 전환
완료된 상태였음(CLAUDE.md만 그 전날 6/4에 써놓고 안 갱신됨). curl로 `tiles.westinx.com`/
`valhalla.westinx.com` 생존 확인 후 **CLAUDE.md만 정정**(`419b730`). 코드 변경 없음.
**교훈: "미해결" 백로그 항목은 먼저 실제 코드/git log로 재확인부터 — 문서가 stale할 수 있음.**

### 4) #TTS 가청성 재작업 — `feat/tts-audibility` → `feat/tts-audibility-v2`
옛 `feat/tts-audibility`가 main 대비 44커밋 divergence(리베이스 불가 수준)라, **필요한 기능
커밋 3개만 골라 main 위에 새로 cherry-pick**:
- `docs: TTS 볼륨 가청성 recon` (RECON_tts_volume.md, 원본 `33aa6d4`)
- `feat(tts): route speech to navigation audio usage` — `nav_screen.dart` `_initTts()`에
  `setAudioAttributesForNavigation()` 추가 (원본 `07feb5b`)
- `feat(tts): request audio focus + ducking on speak` — `voice_pack_service.dart`
  `speak(text, focus: true)` (원본 `98b71b0`)
- 리포트 재작성(`REPORT_tts_audibility.md`, 새 커밋 해시 반영).
- analyze 0 / test 71 전부 통과 (오디오 usage/focus는 플랫폼 채널 의존이라 유닛테스트 불가 —
  원본 RECON 때부터 알려진 한계).
- **옛 `feat/tts-audibility`는 그대로 방치(삭제 안 함)** — TTS 3커밋 외에 **무관한 recon
  커밋 3개**(사유지 도로 회피 조사 `324cc1a` / 게이트·access 태깅 PoC `df715a8` / 오버레이
  파이프라인 설계 `0eb505c`, 전부 read-only docs, 코드 변경 없음)가 얹혀 있음 — 이번 세션
  범위 밖이라 다음 순번에 처리.

### 5) `verify/ride-0706`에 6번째 브랜치로 병합, APK 재빌드
`feat/tts-audibility-v2`를 6번째로 merge(`--no-ff`, `d55d5b5`). `loop/tick.md`만 충돌(관례대로
`--theirs`), 실제 코드 3파일 전부 auto-merge(#1~#5 어느 것과도 겹치는 라인 없음). analyze 0 /
test 71 / build 성공. 리포트 갱신 `loop/REPORT_verify_ride0706.md`(`dc091f0`, #6 체크리스트 포함
— "내비 볼륨 슬라이더가 미디어보다 낮게 설정된 기기면 오히려 작게 들릴 수 있음, 이 경우 회귀
아니라 기기 설정 문제"라고 명시).
**APK는 빌드만 완료, 아직 폰에 scp/install 안 함**(폰 설치는 사용자 몫/Windows 작업).

---

## ▶ 다음 순번 (7번째 세션에서 이어감)

**0순위 — 배포 확인:** `verify/ride-0706`(HEAD `dc091f0`) APK가 아직 폰에 안 깔려있음.
**2026-07-07 새벽 퇴근길에 실주행 검증 예정, 하루 1회뿐, 6개 기능 한 번에 검증**(사용자 지시:
"TTS까지 진행하자. 내일 퇴근 때 한 번에 싹 검토하지 뭐") — 세션 시작 시 scp + `adb uninstall`/
`install -r` 여부부터 확인.

**1순위 — 라이딩 결과 청취:** PASS면 아래 6개를 **각각 개별로** main 머지
(`verify/ride-0706` 자체는 머지 안 함):
`feat/reroute-heading` / `feat/nav-reroute-ui` / `feat/exit-name-voice` /
`feat/sharp-curve-voice` / `feat/continue-straight-voice` / **`feat/tts-audibility-v2`**
(⚠️ 옛 `feat/tts-audibility`가 아님 — 이름이 비슷하니 헷갈리지 말 것. 옛 브랜치는 애초에
합본에 안 들어감).
FAIL이면 6개 중 어느 기능 문제인지부터 특정 (로그 태그: REROUTE=#1, GUIDE/카드UI=#2, TTS
`_named`=#3, TTS 급커브=#4, TTS 직진=#5, TTS 볼륨/포커스=#6).
- #5는 curl 표본상 발생 자체가 0건이었으므로 "안 들림"은 정상, "이상하게 들림"만 문제로 취급.
- #6은 유닛테스트 불가 항목이라 이번 라이딩이 유일한 검증 수단. "내비 볼륨이 미디어보다 낮게
  설정된 기기라 더 작게 들림" 증상이면 회귀 아니라 기기 설정 이슈로 기록.
- #4(급커브)는 타이밍(tier) 안 건드렸으므로 "너무 늦다/이르다" 피드백 있으면 다음 세션에
  tier 재조정 대상으로 기록.

**2순위 — 옛 `feat/tts-audibility` 브랜치 정리: 완료.** 무관 recon 3커밋 main에 cherry-pick
(`5c3d959`/`03d70e5`/`3d5e356`).

**4순위 — Settings Phase2 RECON+SPEC: 완료 (7번째 세션 중 추가).** `loop/RECON_settings_phase2.md`
(`baabe00`) + `loop/SPEC_settings_phase2.md`(`6eef7d3`) main 반영. 6개 TODO 항목
(도로선호도/내비뷰설정/안내음성언어/다크모드/지도다운로드/약관) 전부 **실제 구현 전 마스터
결정 필요(D1~D6)** — SPEC이 임의로 답을 안 고름. 다음 세션에서 D1~D6 먼저 사용자와 확정한
뒤에야 착수 가능. 결정 없이 진행 가능한 건 전부 T1 "준비 중" 자리표시 tile뿐이고, 약관은
`showLicensePage()`로 T1 실기능 가능(법률 텍스트만 있으면).

**3순위 — 옛 방치 브랜치 4개 RECON: 완료.** `loop/RECON_stale_branches.md`(main에 병합됨, `56ab527`)
로 file:line 전수 대조 끝. 결론:
- `phase2/heading-fix`(`1821607`) / `phase2/marker-fix`(`1433c48`) / `debug/fix-rate-probe`(`2991a68`)
  → **DELETE 확정** (전부 main에 독립적으로 더 나은 구현으로 이미 대체됨, 근거는 RECON 문서 참조).
- `feat/arrival-fix`(`4332804`) → **KEEP-BUT-REVIEW**. 마커/도착판정/TTS 부분은 superseded인데,
  **지오펜스+속도 게이트 수동종료(§1d)는 main에 대응물이 전혀 없음** — main의 "종료" 버튼(배너/ETA바
  둘 다)은 무조건 `Navigator.pop()`이라 주행 중 실수로 눌러도, 목적지 오버슈트해도 안전장치 없음.
  이 브랜치엔 30m 이탈 시 자동으로 guiding 복귀+재탐색, 8m·30km/h 이하일 때만 종료 버튼 활성화하는
  로직이 있음 — 버릴 아이디어 아니라 판단, main 위에 이식할지는 라이딩으로 현재 "즉시종료" 동작이
  실제로 문제인지 확인 후 결정 권장.
- **삭제 완료(7번째 세션 중)**: `phase2/heading-fix`/`phase2/marker-fix`/`debug/fix-rate-probe`
  로컬 삭제 + `phase2/heading-fix`/`phase2/marker-fix`는 origin 리모트도 삭제(`git push origin
  --delete`, 사용자 명시 확인 후). `debug/fix-rate-probe`는 애초 리모트에 없었음.
  `feat/arrival-fix`(§1d 지오펜스+속도게이트 수동종료)는 KEEP-BUT-REVIEW 유지 — 삭제 안 함,
  다음 순번에서 SPEC 써서 반영할지 여부 결정 필요.

**보류 중 (순서 무관):**
- **로터리 미태깅(고덕좌교로, way_id=1304219907)**: OSM 데이터 이슈, 이 리포로 해결 불가.

---

## 🔑 이번 세션 핵심 학습

- **"미해결" 백로그 항목이 실제로는 이미 코드상 해결돼 있고 문서만 안 갱신된 경우가 있다** —
  #7이 그 사례. 백로그를 다시 집어들 때 먼저 `git log`/실제 코드로 현재 상태부터 재확인할 것,
  핸드오프 문서의 "미해결" 표기를 곧이곧대로 믿지 말 것.
- **main 자체의 사전 analyze 이슈는 매번 브랜치별로 우회하는 것보다 한 번 main에 정리해서
  올리는 게 낫다** — 우회가 반복 패턴으로 굳어지면(4번째 세션부터 매번 재발) 그 자체가
  근본 수정 대상. 이번에 실행, 다음 세션에서 실제 효과(새 브랜치가 analyze 0으로 시작하는지)
  검증 필요.
- **오래된 T3 브랜치가 main과 크게 divergence되면 전체 rebase보다 "필요한 기능 커밋만 골라
  cherry-pick"이 안전하다** — `feat/tts-audibility`(44커밋 차이)를 통째로 rebase하는 대신
  실제 기능 커밋 3개만 골라 새 브랜치(`feat/tts-audibility-v2`)에 재적용. 무관하게 얹힌
  커밋(사유지 도로 회피 recon 등)은 자연히 걸러짐.
- **R4/R5 패턴 확립: "과다발화/오안내 위험"류 RECON 우려는 curl 실측으로 빠르게 기각 가능** —
  두 항목 모두 실측에서 우려 근거 없음으로 판명. 앞으로 유사한 "확신 없는 위험" 항목이 나오면
  이 패턴(desk curl 계측 → 소스 확인 → 결론)을 우선 시도.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개(하나의 기능 단위면 여러 줄 변경도 한 커밋 허용), 각 커밋 전 commit-gate 훅이 `flutter analyze`(전체 0개)+`flutter test`(현재 71/71) 강제.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall com.example.yurunavi` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.
- 지도/라우팅/rust 엔진 공개 호스트: `tiles.westinx.com` / `valhalla.westinx.com` / `navi.westinx.com` (모두 HTTPS, Cloudflare 경유로 추정). 로컬 curl 계측은 `localhost:8002` 등 직접 호출 사용.

## 📌 참고

- 현재 `main` HEAD: `419b730` (이번 세션 3커밋 추가: R5 recon 종결 + analyze 정리 cherry-pick + CLAUDE.md 정정 — 단, T3 코드 머지는 없음, 전부 docs/chore).
- 대기 브랜치(라이딩 PASS 후 개별 main 머지 대상): `feat/reroute-heading`(`c41859d`) /
  `feat/nav-reroute-ui`(`acb36f0`) / `feat/exit-name-voice`(`4f656d4`) /
  `feat/sharp-curve-voice`(`5fff4eb`) / `feat/continue-straight-voice`(`e21b97a`) /
  `feat/tts-audibility-v2`(`4d987bb`, ⚠️ 신규, 옛 것과 구분).
- 방치 브랜치(머지 대상 아님, 처리 보류): `feat/tts-audibility`(`0eb505c`, 옛것, 44커밋
  divergence + 무관 recon 커밋 3개).
- `verify/ride-0706`(`dc091f0`, 6개 통합, 라이딩 전용, main 머지 금지).
- 패키지: `com.example.yurunavi`.
- IC/터널 안내 실측 데이터: `loop/recon_route.json`.
