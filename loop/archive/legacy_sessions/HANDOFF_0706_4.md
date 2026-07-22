# HANDOFF — YuruNavi (2026-07-06 세션 종료, 6번째 세션으로 인계)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장/출퇴근길). 질문은 ask_user_input.
2. **RECON → SPEC(=tick 동봉) → 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거, 하루 1회뿐.** T3(거동변경) 브랜치가 2개 이상 라이딩 대기면 `verify/ride-*` 통합 브랜치로 합쳐서 APK 1개로 배포.
4. **T3는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 개별 main 머지.
5. **commit-gate 훅:** `flutter analyze`(전체 0개, info 레벨도 fatal)+`flutter test` 강제. **매 세션 새 T3 브랜치를 main에서 분기할 때마다 main의 사전 analyze 경고 4개(unused field 2 + deprecated Radio 2)가 재발함** — 아직 main엔 그 정리 fix가 안 올라가 있기 때문. 대응: 브랜치 만들자마자 `git cherry-pick d9d78d5`(단일 목적 커밋, 무관 변경 안 섞여 있음 확인됨)를 첫 커밋으로 실행.
6. **tick.md 사고 주의:** `git checkout -- loop/tick.md`는 "다른 브랜치의 이미 커밋된 tick.md와 충돌할 때"만. 새 브랜치+미커밋 SPEC 상태에서 치면 SPEC이 날아감. 순서: ①checkout -b, ②그 다음 tick.md 작성. **verify/ride-\* 로 merge할 때 tick.md 충돌은 항상 발생함(각 T3 브랜치가 자기 SPEC을 씀) — `git checkout --theirs loop/tick.md`로 들어오는 브랜치 버전 채택이 관례.**
7. **미커밋 잔존(무관, 손대지 말 것):** 루트 `.md`(MORNING_REPORT_*, RECON_*, REPORT_* 등)의 `D`+`??` 잔존 계속 유지. 이번 HANDOFF_0706_4.md도 동일하게 커밋 안 함(관례 유지).
8. 툴체인: Flutter 3.44.0 / Dart 3.12.0 stable.

---

## 🏆 이번 세션(5번째) 성과 — #5 사거리 직진(type 8 Continue) 음성 안내 추가

**배경:** RECON_voice_v2.md R4절이 "보류: 실경로 curl로 type 8 발생빈도 계측 선행 필요"로
남겨둔 항목. 폰 없이 desk에서 끝낼 수 있는 조사라 이번 세션에서 우선 처리.

- **curl 계측 (localhost:8002, 폰 없이 진행):** 국도44(홍천-인제)/부산시내(서면-해운대)/
  국도19(구례-하동)/국도42(여주-원주)/김제 평야 그리드/대전 시내 그리드/정선 오지도로/
  가평 국도 8개 실경로, 합계 285km·maneuver 118개 계측 → **type 8 발생 0건.**
- **원인 확인 (Valhalla 소스, `maneuversbuilder.cc:1880-1996`):** `kContinue`는 turn_degree가
  직진일 때의 fallback 분류일 뿐, 실제 별도 maneuver로 살아남으려면 `internal_intersection`
  이거나 인접 유사도로가 있어 애매한 분기점 조건을 통과해야 함 — 평범한 직진 구간은 아예
  분리 안 되고 이전 maneuver에 흡수됨. **RECON이 우려했던 "과다발화 위험"은 이 타일셋
  기준 근거 없음으로 결론.**
- 브랜치 `feat/continue-straight-voice` (main에서 분기, main 미머지 · **라이딩 전**).
- `voice_engine.dart`: `eventForType`에 `case 8: return 'continue';` 추가.
- `guidance_profile.json`: 기존에 있던 `"continue": {enabled:false}`를 `true`로 전환만
  (tier는 공통 폴백, sharp-curve 때와 동일 원칙 — 실주행 근거 없이 타이밍 새로 안 만듦).
- `default_ko.json`: `continue_approach: "{dist}미터 앞 직진"`, `continue_imminent: "직진입니다"`.
- 테스트 9건 신규(`voice_engine_continue_test.dart`): type8→continue 매핑 + 프로필 게이트
  on/off + 9/10/15/16 회귀가드 + keep(22/23/24)과 구분 확인.
- analyze 0 / test 60(해당 브랜치 기준) 전체 통과. code-auditor PASS(이슈 없음).

## 🏆 verify/ride-0706 갱신 — 5개 T3 브랜치 통합, APK 재빌드

`verify/ride-0706`에 `feat/continue-straight-voice`를 5번째로 merge(`--no-ff`).
`loop/tick.md`만 충돌(각 브랜치가 자기 SPEC을 쓰는 파일이라 항상 발생) →
`git checkout --theirs`로 들어오는 브랜치 SPEC 채택. 실제 코드 3파일
(`voice_engine.dart`/`guidance_profile.json`/`default_ko.json`)은 자동 병합 성공(#4의
sharp_turn 분기와 #5의 continue 분기가 다른 switch case/JSON 키라 안 겹침).
analyze 0 / test 71 / build 성공. **APK는 빌드만 완료, 아직 폰에 scp/install 안 함**
(이전 세션들과 동일 — 폰 설치는 사용자 몫/Windows 작업).
리포트 갱신: `loop/REPORT_verify_ride0706.md` (5개 브랜치 검증 체크리스트 포함, #5 항목 추가 —
단, "표본 8개 모두 0건이라 이번 라이딩에서도 안 들릴 가능성 높음, 안 들려도 실패 아님"이라고
명시해둠).

---

## ▶ 다음 순번 (6번째 세션에서 이어감)

**0순위 — 배포 확인:** `verify/ride-0706`(HEAD `755d46f`) APK가 아직 폰에 안 깔려있음.
**내일(2026-07-07) 새벽 퇴근길에 실주행 검증 예정, 하루 1회뿐, 5개 기능 한 번에 검증** —
세션 시작 시 scp + `adb uninstall`/`install -r` 여부부터 확인. (사용자가 Windows에서 직접
진행하는 파트 — Claude가 대신 adb install 할 수 없음, 이 서버엔 연결된 기기 없음.)

**1순위 — 라이딩 결과 청취:** PASS면 `feat/reroute-heading`, `feat/nav-reroute-ui`,
`feat/exit-name-voice`, `feat/sharp-curve-voice`, `feat/continue-straight-voice`
**각각 개별로** main 머지(`verify/ride-0706` 자체는 머지 안 함). FAIL이면 5개 중 어느 기능
문제인지부터 특정 (로그 태그: REROUTE=#1, GUIDE/카드UI=#2, TTS `_named`=#3, TTS 급커브=#4,
TTS 직진=#5). **#5는 curl 표본상 발생 자체가 0건이었으므로 "안 들림"은 정상, "이상하게
들림"만 문제로 취급.** #4(급커브)는 타이밍(tier)을 안 건드렸으므로 "너무 늦다/이르다"
피드백 있으면 다음 세션에 tier 재조정 대상으로 기록.

**2순위 — 나머지 안내로직:**
- **터널/교량 안내 (R5)**: `RECON_underpass.md` 완료, `/trace_attributes` 별도 호출 설계
  필요. R4처럼 desk에서 curl 계측 가능한지 먼저 확인해볼 것 — `trace_attributes`는 좌표
  경로(shape/encoded polyline)를 입력받는 API라 `/route` 응답의 shape를 그대로 넣어 tunnel/
  bridge edge.use 비율을 계측할 수 있을지 다음 세션 유력 후보(폰 없이 가능할 듯).

**보류 중 (순서 무관):**
- `feat/tts-audibility`: main과 크게 divergence, 리베이스/재작업 필요.
- **#7 지도 스타일**: 호스트 불일치(스타일 JSON `tiles.westinx.com` vs CLAUDE.md `192.168.0.57`) 미해결.
- **로터리 미태깅(고덕좌교로, way_id=1304219907)**: OSM 데이터 이슈, 이 리포로 해결 불가.

---

## 🔑 이번 세션 핵심 학습

- **"과다발화 위험"류 RECON 보류 항목은 추측 대신 curl 실측으로 빠르게 닫을 수 있다** —
  R4는 폰 없이 8개 실경로(285km) curl 계측만으로 "우려 근거 없음"을 확정했고, Valhalla
  소스(`maneuversbuilder.cc`)를 직접 읽어서 "왜 0건인지"까지 설명 가능했다. 3번째 세션의
  "Valhalla 소스 직접 확인이 더 빠름" 교훈이 이번엔 "행동 결정"까지 이어진 케이스.
- **표본이 0건이어도 구현은 진행 가능 — 단 리포트에 "안 들릴 수 있음"을 명시해야 함** —
  실주행에서 기능이 안 들렸을 때 "버그"와 "애초에 드문 이벤트"를 헷갈리지 않도록
  `REPORT_verify_ride0706.md` #5 항목에 미리 기대치를 적어둠.
- **verify/ride-\* merge 시 tick.md 충돌은 항상 발생하고 항상 같은 방식(--theirs)으로 푼다** —
  이번에 명시적으로 다시 확인됨. 새 세션이 이 충돌을 보고 당황하지 않도록 규칙 6에 추가.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개(하나의 기능 단위면 여러 줄 변경도 한 커밋 허용), 각 커밋 전 commit-gate 훅이 `flutter analyze`(전체 0개)+`flutter test`(현재 71/71) 강제.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall com.example.yurunavi` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.

## 📌 참고

- 현재 `main` HEAD: `3ad75fd` (변동 없음 — 이번 세션도 main엔 아무것도 머지 안 함).
- 대기 브랜치: `feat/reroute-heading`(`c41859d`) / `feat/nav-reroute-ui`(`acb36f0`) /
  `feat/exit-name-voice`(`4f656d4`) / `feat/sharp-curve-voice`(`5fff4eb`) /
  `feat/continue-straight-voice`(`e21b97a`) /
  `verify/ride-0706`(`755d46f`, 5개 통합, 라이딩 전용).
- 패키지: `com.example.yurunavi`.
- IC/터널 안내 실측 데이터: `loop/recon_route.json`.
