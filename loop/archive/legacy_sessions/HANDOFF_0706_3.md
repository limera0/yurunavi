# HANDOFF — YuruNavi (2026-07-06 세션 종료, 5번째 세션으로 인계)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장/출퇴근길). 질문은 ask_user_input.
2. **RECON → SPEC(=tick 동봉) → 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거, 하루 1회뿐.** T3(거동변경) 브랜치가 2개 이상 라이딩 대기면 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개로 배포.
4. **T3는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 개별 main 머지.
5. **commit-gate 훅:** `flutter analyze`(전체 0개, info 레벨도 fatal)+`flutter test` 강제. **매 세션 새 T3 브랜치를 main에서 분기할 때마다 main의 사전 analyze 경고 4개(unused field 2 + deprecated Radio 2)가 재발함** — 아직 main엔 그 정리 fix가 안 올라가 있기 때문. 대응: 브랜치 만들자마자 `git cherry-pick d9d78d5`(단일 목적 커밋, 무관 변경 안 섞여 있음 확인됨)를 첫 커밋으로 실행.
6. **tick.md 사고 주의:** `git checkout -- loop/tick.md`는 "다른 브랜치의 이미 커밋된 tick.md와 충돌할 때"만. 새 브랜치+미커밋 SPEC 상태에서 치면 SPEC이 날아감. 순서: ①checkout -b, ②그 다음 tick.md 작성.
7. **미커밋 잔존(무관, 손대지 말 것):** 루트 `.md`(MORNING_REPORT_*, RECON_*, REPORT_* 등)의 `D`+`??` 잔존 계속 유지. 이번 HANDOFF_0706_3.md도 동일하게 커밋 안 함(관례 유지).
8. 툴체인: Flutter 3.44.0 / Dart 3.12.0 stable.

---

## 🏆 이번 세션(4번째) 성과 — #3 급커브(45°+) 감속 음성 안내 분리

**배경:** HANDOFF_0705_1에서부터 지목된 "급커브 누락" — Valhalla type 11(kSharpRight)/14(kSharpLeft,
45°+)가 완만한 회전(9/10/15/16)과 **완전히 동일한 문구·타이밍**으로 발화되던 문제. RECON 없어서
신규 작성 후 진행.

- 신규 RECON `loop/RECON_sharp_curve.md`: type enum은 `/data/projects/valhalla-src/proto/descriptors/directions.proto`에서 직접 확인(kSlightRight=9, kRight=10, kSharpRight=11, kSharpLeft=14, kLeft=15, kSlightLeft=16) — 3번째 세션 학습("Valhalla 소스 직접 확인이 더 빠름") 그대로 재적용.
- 브랜치 `feat/sharp-curve-voice` (main에서 분기, main 미머지 · **라이딩 전**).
- `voice_engine.dart`: `eventForType`에서 11/14를 `sharp_turn_right`/`sharp_turn_left`로 분리(9/10/15/16은 기존 turn_right/turn_left 유지).
- `guidance_profile.json`: 두 신규 이벤트 enabled=true, **tier는 손대지 않음**(공통 tier로 폴백 — 실주행 없이 타이밍 추정은 과도하다고 RECON에서 명시적으로 보류).
- `default_ko.json`: `sharp_turn_left/right_approach/imminent` 4종 — "{dist}미터 앞 급좌회전, 감속하세요" / "급좌회전 주의" (우측 동일 패턴).
- `_fast`(고속 축약 문구) 접미사는 **의도적으로 급커브에 미적용** — 감속 대상이므로 축약 없음.
- 테스트 7건 신규(`voice_engine_sharp_curve_test.dart`): 타입 분리 + 9/10/15/16 회귀가드 + `_fast` 미부착 확인.
- analyze 0 / test 62 전체 통과. code-auditor PASS(이슈 없음).

## 🏆 verify/ride-0706 갱신 — 4개 T3 브랜치 통합, APK 재빌드

`verify/ride-0706`에 `feat/sharp-curve-voice`를 4번째로 merge(`--no-ff`, 충돌 없음,
`voice_engine.dart`/`default_ko.json` auto-merge — #3 exit-name과 다른 라인이라 안전).
analyze 0 / test 62 / build 성공. **APK는 빌드만 완료, 아직 폰에 scp/install 안 함**
(이전 세션과 동일 — 이번 세션도 폰 설치는 사용자 몫/Windows 작업이라 미진행).
리포트 갱신: `loop/REPORT_verify_ride0706.md` (4개 브랜치 검증 체크리스트 포함, #4 급커브 항목 추가).

---

## ▶ 다음 순번 (5번째 세션에서 이어감)

**0순위 — 배포 확인:** `verify/ride-0706`(HEAD `40b9c3e`) APK가 아직 폰에 안 깔려있음.
**오늘(2026-07-07) 새벽 퇴근길에 실주행 검증 예정, 하루 1회뿐** — 세션 시작 시 scp +
`adb uninstall`/`install -r` 여부부터 확인. (사용자가 Windows에서 직접 진행하는 파트 —
Claude가 대신 adb install 할 수 없음, 이 서버엔 연결된 기기 없음.)

**1순위 — 라이딩 결과 청취:** PASS면 `feat/reroute-heading`, `feat/nav-reroute-ui`,
`feat/exit-name-voice`, `feat/sharp-curve-voice` **각각 개별로** main 머지(`verify/ride-0706` 자체는 머지 안 함).
FAIL이면 4개 중 어느 기능 문제인지부터 특정 (로그 태그: REROUTE=#1, GUIDE/카드UI=#2,
TTS `_named`=#3, TTS 급커브=#4). 급커브(#4)는 타이밍(tier)을 이번엔 안 건드렸으므로
"너무 늦다/이르다" 체감 피드백이 있으면 다음 세션에 tier 재조정 대상으로 별도 기록.

**2순위 — 나머지 안내로직:**
- **R4 사거리 직진 과다발화**: RECON은 이미 있음(`loop/RECON_voice_v2.md` R4절, "보류: 실경로
  curl로 type 8 발생빈도 계측 선행 필요"). 이건 **폰 없이 curl만으로 가능** — Valhalla
  `localhost:8002`에 국도/시내 실경로 몇 개 태워서 type 8 비율 확인 후 과다발화 여부 판단.
  다음 세션 유력 후보.
- **터널/교량 안내**: `RECON_underpass.md` 완료, `/trace_attributes` 별도 호출 설계 필요(더 큰 작업).

**보류 중 (순서 무관):**
- `feat/tts-audibility`: main과 크게 divergence, 리베이스/재작업 필요.
- **#7 지도 스타일**: 호스트 불일치(스타일 JSON `tiles.westinx.com` vs CLAUDE.md `192.168.0.57`) 미해결.
- **로터리 미태깅(고덕좌교로, way_id=1304219907)**: OSM 데이터 이슈, 이 리포로 해결 불가.

---

## 🔑 이번 세션 핵심 학습

- **main 사전 analyze 경고가 T3 브랜치마다 재발하는 근본 원인은 "정리 fix가 아직 main에
  안 머지됨"** — `d9d78d5`(단일 목적, 2파일만)를 새 브랜치 첫 커밋으로 cherry-pick하는 게
  가장 빠름. `git show <sha> --stat`으로 무관 변경 안 섞였는지 먼저 확인하고 진행할 것
  (3번째 세션의 "cherry-pick도 stale 대응 필요" 교훈 재확인).
- **모터사이클 안전 관련 안내는 "발화 자체"와 "타이밍(tier)"을 분리해서 접근하는 게 안전** —
  이번엔 문구만 분리하고 tier는 그대로 둠. 실주행 근거 없이 타이밍까지 바꾸면 검증 범위가
  넓어져서 라이딩 1회로 다 확인 못 함.
- **폰 미설치 API(trace_attributes 조사, curl 계측 등)는 리스크 낮은 다음 작업 후보** —
  실주행 슬롯이 하루 1회뿐이라, 폰 없이 책상에서 끝낼 수 있는 조사(R4 type 8 빈도 계측 등)를
  먼저 소진하는 게 세션 효율이 좋음.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개(하나의 기능 단위면 여러 줄 변경도 한 커밋 허용), 각 커밋 전 commit-gate 훅이 `flutter analyze`(전체 0개)+`flutter test`(현재 62/62) 강제.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall com.example.yurunavi` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.

## 📌 참고

- 현재 `main` HEAD: `3ad75fd` (변동 없음 — 이번 세션도 main엔 아무것도 머지 안 함).
- 대기 브랜치: `feat/reroute-heading`(`c41859d`) / `feat/nav-reroute-ui`(`acb36f0`) /
  `feat/exit-name-voice`(`4f656d4`) / `feat/sharp-curve-voice`(`5fff4eb`) /
  `verify/ride-0706`(`40b9c3e`, 4개 통합, 라이딩 전용).
- 패키지: `com.example.yurunavi`.
- IC/터널 안내 실측 데이터: `loop/recon_route.json`.
