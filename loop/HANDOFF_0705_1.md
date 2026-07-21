# HANDOFF — YuruNavi (2026-07-05 밤 세션 종료)

## ⛔ 새 세션이 가장 먼저 읽을 것

1. **모든 답 10줄 이내, 핵심만.** 모바일 소통(공사현장). 질문은 ask_user_input 버튼으로.
2. **RECON → SPEC(=tick 동봉) → `claude -p --verbose < loop/tick.md` 실행 → 폰 검증** 엄수. `file:line` 앵커 후 변경, 추측 패치 금지.
3. **실주행이 유일한 증거.** 순수 로직은 `flutter test` 후 라이딩 1회. (단, 주행 중 캡처 금지 — 로그 버퍼가 알아서 쌓이니 정지 후 `adb logcat -d`.)
4. **T3(거동변경)는 라이딩 PASS 전 main 머지 금지.** PASS분만 원래 feat 브랜치에서 **개별** main 머지.
5. **`claude -p` 헛돎 이번 세션 2회 발생** — tick 끝에 HEAD 해시 명시 + "N개 NEW 커밋" 못박기 + `git log --oneline -N` 붙여넣기. **의심되면 `git show -s --format='%ci %h %s' <hash>`로 커밋 타임스탬프 검증**(이번에 "세션 전부터 있었다"는 오보를 타임스탬프로 잡음).
6. **tick.md 충돌 상습:** 브랜치 이동/머지 전 `git checkout -- loop/tick.md`.
7. **툴체인:** Flutter 3.44.0 / Dart 3.12.0 stable. analyze·test·build 동일 → null-aware map-entry `'k': ?v` 안전.

---

## 🏆 이번 세션 성과 1 — U턴 블로커 대형→2커밋 강등 (미검증 대기)

thor C++ 코어 패치(대형)로 추정됐으나 RECON 체인으로 **클라 2커밋**으로 강등.

- 근원 = `src/loki/search.cc:86-88` heading_filter가 `has_heading_case()` false면 방향필터 스킵.
- curl 계약(/locate)로 실증: heading 넣으면 양방향 edge 2→1 필터. **이전 "heading 무시"는 파라미터를 location 객체 밖에 넣은 착시.**
- `offsetOrigin(40m)`은 좌표 이동일 뿐 edge 방향 필터 아님 → U턴 못 막음. **heading 하드게이트가 진짜 해결책.**

**`feat/reroute-heading`** (main@b575c28 분기, 2커밋, 책상게이트 통과, **미검증**):

```
30350b8 feat(nav): pass heading to reroute for u-turn suppression
1aa572b feat(routing): optional origin heading on reroute payload
```

검증(다음 주행 세션): 지나침→재탐색 시 제자리 U턴 소멸 / 정상 재탐색 / 과잉보정 없나. `YNAV_REROUTE originHeading=` 로그. **오늘 카메라 주행과 절대 안 섞음.**

---

## 🏆 이번 세션 성과 2 — 카메라 3부작 정복 → main 머지 완료 ✅

`feat/nav-ui-redesign` **라이딩 PASS → main 개별 머지(`3ad75fd`, --no-ff).**
포함: 화살표 puck(회전)+물방울 핀, 코스별 경로색(국도 파랑/지방도 초록/시골길 진노랑), 하단앵커 카메라, 마커 크기통일, A 도착배너, #10 부근/도착 순서, 목적지핀 버그.

**카메라 두 근본버그 — 로그·좌표·타임스탬프로 증명하며 순차 격파:**

- **뒤집힘(진행방향이 화면 아래로):** 원인 = 분리된 두 카메라 명령 경쟁 — `:237 bearingTo`(회전만)와 `_recenter`의 `newLatLngZoom`(위치+줌만, 회전없음)이 비동기 순서로 충돌, newLatLngZoom이 bearing을 덮어써 회전 취소. 로그상 `brg=hdg` 정상계산인데 화면만 어긋남. **수정: 단일 `newCameraPosition`(target+zoom+bearing 원자적)** = `1eb96b9`.
- **초과 하강(puck이 하단25% 지나 화면밖):** 원인 = 오프셋 `mpp × physH(=logicalH×dpr) × 0.25`. `getMetersPerPixelAtLatitude`는 **논리px 기준**이라 물리높이(×dpr) 곱하면 정확히 dpr배 초과(실측 초과배율=2.81=dpr). **수정: 논리높이 사용(×dpr 제거)** = `6de228f`. mAhead 257m→~90m.

머지된 커밋열: `6de228f`(논리높이) / `1eb96b9`(카메라통합) / `0844f3d`(brg/hdg 진단로그) / `8d9b757`(화살표 에셋 재크롭) / `41cb048`(iconSize) / `5249bb1`(경로색) / `7f1cfb5`(홈 마커통일).

---

## 🔑 이번 세션 핵심 학습 (특히 반전된 것)

- **★ HANDOFF d1 "×dpr" 학습은 틀렸었다 — 오늘 뒤집혀 정정됨.** 그 필드검증은 **뒤집힘 버그에 오염된 화면**에서 25%를 판정한 거라 결론이 오염. 뒤집힘(1eb96b9)을 먼저 고친 뒤에야 진짜 거동이 보였고, 올바른 값은 **논리높이(÷dpr 아님, ×dpr 제거)**. → **오염된 조건의 필드검증은 신뢰 불가. 한 버그가 다른 버그 판정을 오염시킨다.**
- **로그가 가설을 부정할 때 로그를 믿어라:** `brg=hdg` 완전일치 + puck→tgt 방위=heading으로 "180° 반전/offset 부호오류/north-up 굳음" 가설 전부 부정. 진짜는 "명령 경쟁"과 "초과 배율". 좌표·숫자 검산이 눈 짐작을 이김.
- **비개발자 사용자의 증상 서술 번역:** "뒤집혔다/아무것도 안 보인다"의 실체 = puck이 화면 밖으로 밀려남(초과하강). 문자 그대로의 180°가 아니었음.
- **half-migration/분리명령이 desync 낳음:** 카메라 명령을 둘로 나눈 게 뒤집힘의 원인. 위치+줌+회전은 한 CameraUpdate로.
- **`claude -p` 헛돎 2회:** ①이전 상태 재보고 ②"이미 적용됨(세션 전부터)" 오보 → 타임스탬프로 반증. HEAD 명시+커밋수 못박기+git log/타임스탬프 검증이 필수 방어.

---

## ▶ 다음 순번 / 미착수

1. **`feat/reroute-heading` 라이딩 검증** (U턴, 최우선 블로커). 다음 주행 세션. main 갱신됐으니 검증 전 새 main 위 rebase 여부만 그때 결정.
2. **UI 잔여:** A-버튼 분할(계속안내/내비종료), B-재탐색 시 정북 전체경로 3초 조망.
3. **안내 로직:** #3 45°+ 급커브 누락 / R4 사거리 직진 과다발화 / #6 램프·터널(trace_attributes 선행).
4. **#5 TTS 볼륨** 개선 미흡, 별도 RECON. `feat/tts-audibility` 미머지 보존.
5. **#7 지도 도로표시**(dual carriageway) — 스타일 튜너.

## 🅿 별도 대형 프로젝트 (1차 출시 후)

- **YuruNavi OSM 정비 AI:** 미태깅 로터리(고덕좌교로 way_id=1304219907) + 사유지 관통 회피. Overpass 서치→판별→OSM 편집 API. 대량 자동편집 정책 사전확인.

---

## 🔒 환경·워크플로 (불변)

- 서버 westinx `/data/projects/yurunavi`, `claude -p < loop/tick.md`. 지시파일 `loop/`.
- 커밋 1개=파일1개=논리1개, 각 `flutter analyze` 신규0.
- 빌드 `flutter build apk --debug` → scp → 윈도우 `.\adb uninstall <pkg>` 후 `.\adb install -r`.
- 로그 `.\adb logcat -c` → 주행(거치, 캡처금지) → `.\adb logcat -d | Select-String "YNAV_..."`. 태그 PROG/TTS/STEP/ARR/ROUTE/REROUTE/GUIDE/CAM.
- 저장소 `github.com/limera0/yurunavi`. Valhalla `yurunavi-valhalla` v3.7.0 port 8002.

## 📌 참고

- **카메라 검산(정정판):** dpr=2.8125, physH=2340(=logicalH 832×dpr). 오프셋은 **논리높이 832 × 0.25** 사용해야 하단25% 정착. mAhead 정지 settled ~90m 목표. 로그태그 `YNAV_CAM`(puck/tgt/brg/hdg/mpp/physH/mAhead).
- **U턴 curl:** /locate way_id=1195222150. heading 없음=2후보 / heading+tol=단일 필터.
- 미커밋 잔존: `loop/RECON_home_ui.md`, `loop/RECON_reroute_button.md`.
