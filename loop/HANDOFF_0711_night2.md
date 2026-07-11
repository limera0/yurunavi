# HANDOFF — YuruNavi (2026-07-11 밤, Claude Code for VS Code 세션)

전 세션 인수인계 문서(HANDOFF_0712_batch.md, Claude Computer app 작성분)를 이어받아 진행.
이 문서는 그 다음 체크포인트 — 오늘 밤 한 작업 + git 전수조사로 찾은 미결 브랜치 정리.

---

## 0. 오늘 밤 완료된 작업 (모두 main에 반영됨)

| 항목 | 내용 | 검증 상태 |
|---|---|---|
| **U턴 valhalla 패치** | `motorcyclecost.cc` — `AddUturnPenalty`가 `stopimpact>0` 게이트 안에서만 동작하던 것을, `turntype==kReverse`면 무조건 5000 페널티 가산하도록 수정. `valhalla-fork:patch3-uturn` 빌드, 운영(8002) 교체 완료. | 회귀 없음(16+ 경로 A/B 동일) 확인. **긍정검증은 curl로 못함** — 이 지도에서 narrative U턴은 대부분 다중엣지 유턴차로/스위치백이라 단일엣지 kReverse가 거의 안 걸림. 다음 라이딩 재확인 필요. 상세: `loop/REPORT_PATCH3_uturn.md` |
| **feat/nav-reroute-ui 머지** | 재탐색 코스 재선택 시트 + 오버뷰 카메라. | 라이딩 PASS 확인됨(verify/ride-0706 #2). |
| **continue-straight-voice / sharp-curve-voice / tts-audibility-v2 머지** | type8 직진 안내, 45°+ 급커브 감속 안내, TTS 오디오 포커스/덕킹. | **그날 밤(0711) 테스트폰엔 실제로 안 깔려있었음**(APK가 feat/reroute-heading 단독 빌드였음, 이 3개 브랜치 미포함) — "안 들림" 피드백은 버그 아니라 미설치였을 가능성 높음. 새 APK로 재실측 필요. |
| **국도(index 2) costing 버그 수정** | `routing_service.dart`의 `'shortest': true`가 Valhalla `EdgeCost()`에서 `class_factors`/`use_highways`/`use_tolls`/커브·교량·터널 팩터를 전부 건너뛰게 만들던 dead-code 버그. 실측: trunk 36.3%→0%, primary 31.7%→96.3% (거리/시간 +36%/+27%, 자동차전용도로 실제 회피 시작하며 생기는 정상 트레이드오프). | curl A/B 검증 완료. 상세: `loop/RECON_costing_national.md` |
| **EXIT-LANDMARK 백로그 등록** | 출구 이름 없을 때 "~~방면 {좌/우}측 출구입니다" 랜드마크 폴백 — 오프라인 벡터타일 `place` 레이어 재사용 가능해 보임(1차 조사만, 미구현). | `loop/BACKLOG.md` READY 최상단 등록. |
| **debug APK 재빌드 2회** | 위 항목들 전부 포함한 최신 `build/app/outputs/flutter-apk/app-debug.apk`. | 다음 라이딩용. |

각 머지 직후 `flutter analyze` 0 issues / `flutter test` 67/67 확인.

---

## 1. git 전수조사 — 미결 브랜치 (오늘 밤 새로 확인)

시작 시점에 있던 로컬 브랜치 전부와 원격 브랜치를 diff해서 "main에 없는 게 뭐고, 그중 진짜 살아있는 게 뭔지" 확인한 결과.

### 1-1. `feat/osm-road-style` (★ 오늘 밤 새로 준비, 미머지 — 사용자가 이번 요청에서 언급한 "다른 채팅 OSM 도로 표시" 브랜치)

- **정체**: `verify/ride-0706`에 6개 T3 브랜치와 별개로 **직접 커밋된 13개 스타일 커밋**(도로 line-width/casing, 터널·고가 음영, trunk 병합, 도로번호 배지 3종 분리, 한글 라벨 단독표시+버스정류장 줌숨김, 줌 6-17 제한 등). `verify/ride-0706` 자체 리포트에도 이 부분은 별도 브랜치명이 없었음 — 즉 "another chat(다른 채팅)"에서 verify 브랜치에 바로 스타일 작업을 쌓은 것으로 보임.
- **오늘 조치**: 현재 main 위로 **깨끗하게 cherry-pick 성공**(충돌 0), `feat/osm-road-style` 브랜치로 커밋해둠(`efe4a2b`). `flutter analyze` 통과.
- **미머지 이유**: 시각적 변경이라 내가 렌더링 결과를 눈으로 못 봄 — 스크린샷/실기기 확인 없이 머지하면 위험. 또한 자체적으로 독립 라이딩 검증된 적 없음(verify/ride-0706의 6-브랜치 APK 안에 묻혀서 같이 있었을 뿐).
- **다음 세션 할 일**: `flutter build apk --debug` → 설치 → 지도 화면에서 도로 표시(굵기/라벨/줌별 밀도) 육안 확인 → 문제없으면 `git merge --no-ff feat/osm-road-style`.

### 1-2. `feat/exit-name-voice` (base, 미머지)

- OSM에 출구명 있을 때만 발화. **오늘 라이딩 피드백 요청사항(랜드마크 폴백)은 아예 미구현** — 병합만으론 부족.
- `loop/BACKLOG.md`의 **EXIT-LANDMARK** 항목으로 스코프 확정해둠. 다음 세션 RECON부터.

### 1-3. `feat/arrival-fix` (KEEP-BUT-REVIEW, 6/26 이후 방치)

- `loop/RECON_stale_branches.md`(main에 이미 있음, 6/17 작성)의 결론: 마커/도착판정/TTS가드 3가지는 main에 이미 독립적으로 더 나은 형태로 구현되어 있어 폐기 가능하나, **§1d 지오펜스+속도 게이트 수동종료 버튼**(도착 후 8m 이내·30km/h 이하일 때만 "지금 종료" 버튼 활성화 + 30m 이탈 시 자동 재탐색 복귀)은 main에 대응 코드가 전혀 없음.
- 이건 오늘 핸드오프 §3.5(도착 후 하단 카드: 10초 카운트다운 + 계속하기/종료 버튼)와 **겹치는 영역** — §3.5 작업 시작할 때 이 브랜치의 지오펜스 로직을 같이 참고/포팅할 것.
- origin/feat/arrival-fix에도 동일 내용 있음(리모트 동기 상태).

### 1-4. `verify/ride-0703b`, `verify/ride-2branch` (구형 verify 번들, 대부분 이미 흡수됨)

- `verify/ride-2branch`의 "roundabout guidance" 커밋 → **main에 이미 동등 기능 있음**(`voice_engine.dart`에 `roundabout_enter`/`roundabout_exit` 확인) — 폐기 가능.
- `verify/ride-0703b`의 "#2 arrived reset", "#4-b card exit number" (nav_screen.dart 소규모 diff, 5~6줄) — main의 도착 처리 로직이 그 이후 크게 재작성돼서 **십중팔구 이미 흡수/대체됐을 것으로 추정되나 직접 diff 대조는 안 함**. 급하지 않음, 나중에 궁금하면 `git show 4c97e48`/`git show 3b533a0`로 5분이면 확인 가능.

### 1-5. `feat/tts-audibility` (구버전, 삭제 권장)

- `-v2`로 대체되어 오늘 밤 머지 완료. 이 구버전은 main 대비 7커밋 diverge, 이미 죽은 브랜치. **삭제해도 안전**(사용자 확인 후).

### 1-6. `backup-osm-20260531` (구형 백업, 삭제 후보)

- 5/31자 스냅샷, 지금 main과 325개 파일 차이(대부분 그 시절 이후 사라진 옛 구조). 실질적 가치 없음, 이름 그대로 "백업" 용도로 만든 것으로 보임. **삭제해도 안전**(사용자 확인 후).

### 1-7. 원격 브랜치 (origin/*)

- `origin/chore/cleanup-dead-code`, `origin/feat/guidance-engine`, `origin/feat/guidance-fix`, `origin/feat/layer1-progress`, `origin/phase1/loc-unify` — **전부 main의 조상(ancestor), 즉 이미 흡수 완료**. 리모트에서 삭제해도 안전.
- `origin/feat/arrival-fix` — 로컬과 동일 내용, §1-3 참조.

### 1-8. `stash@{0}` (미변경, 처리 대기)

- 내용: 로고 이미지(`yuru_circle.jpeg`) 압축본 교체 + `tools/style-ai-proxy/app.py`(맵 스타일 편집용 AI 프록시 개발툴, OpenRouter/Gemini 듀얼 프로바이더 지원 v3로 개선됨). **앱 코드와 무관한 개발 도구** — 급하지 않음. pop해서 main에 바로 커밋 권장(별도 feat 브랜치 안 묶어도 됨).

---

## 2. 핸드오프(HANDOFF_0712_batch.md) 원본 항목 중 미착수

§3.1(코너 음성 문구: 50m 즉시 "곧 좌/우회전" + 0m 삭제), §3.4(POI = 소상공인시장진흥공단 API 연동), §3.6(백그라운드 서비스 + 오버레이) — **오늘 손 못 댐.** 우선순위는 기존 핸드오프 §4 순서 참고(POI는 설계 먼저, 백그라운드는 가장 무거움·단독 세션 권장).

---

## 3. 다음 세션 권장 순서

1. **다음 라이딩 실측** — 오늘 만든 APK(u턴 패치, 국도 costing, continue/sharp-curve/audibility 3종, nav-reroute-ui)을 실제로 타보고 다 확인. 특히 audibility는 배경음악 덕킹까지 이번엔 꼭 테스트.
2. **feat/osm-road-style 육안 확인 후 머지** — 준비는 끝남, 스크린샷/실기기 확인만 남음.
3. **EXIT-LANDMARK** (`loop/BACKLOG.md`) — RECON부터. `poi_feature_picker.dart`/`poi_name_resolver.dart` 패턴 재사용 가능성 확인.
4. **§3.5 도착 카드 + feat/arrival-fix §1d 지오펜스 로직 포팅** — 겹치는 작업이니 같이.
5. 구형 브랜치 정리(§1-5, 1-6, 1-7) — 사용자 확인 후 일괄 삭제.
6. §3.1(코너 문구), §3.4(POI), §3.6(백그라운드) — 순서대로.

---

## 4. 환경 (불변)

기존 HANDOFF_0712_batch.md §6과 동일. 서버 westinx `/data/projects/yurunavi`, Valhalla 8002(현재 `valhalla-fork:patch3-uturn`), tileserver-gl. 빌드 `flutter build apk --debug` → scp → adb uninstall 후 install -r. 기기 Galaxy A34.
