# REPORT — verify/ride-0711 합본 검증

## 브랜치
- base: main (`804aec2`)
- 합본 브랜치: `verify/ride-0711`
- merge 1: `feat/exit-landmark-voice` → "merge: feat/exit-landmark-voice into verify/ride-0711 (1st T3 branch, one APK for next ride)"
  (base가 `feat/exit-name-voice`라 그 8커밋도 함께 실려있음 — main에 없던 `ManeuverStep.exitName` 파싱 포함)
- merge 2: `feat/arrival-exit-geofence` → "merge: feat/arrival-exit-geofence into verify/ride-0711 (2nd T3 branch, one APK for next ride)"
- merge 3: `feat/osm-road-style` → "merge: feat/osm-road-style into verify/ride-0711 (3rd T3 branch, one APK for next ride)"
  (전 세션에 이미 main 위로 cherry-pick 준비됨, 오늘은 육안확인 없이 그대로 합본 — 시각 변경이라
  실기기에서 확인 필요, 아래 체크리스트 참조)

## 충돌
- 전부 `git merge --no-ff` 자동 병합 성공(ort strategy), 수동 conflict 해결 없음.
- #2 접점: `nav_screen.dart` — #1(exit landmark)은 `voice_engine.dart`/`onProgress` 호출부만
  건드림, #2(geofence)는 도착배너 상태/UI만 건드려 겹치는 라인 없음.
- #3 접점: `nav_screen.dart` — #3(road-style)은 `_loadRawStyle` 근처 스타일 관련 1~2줄만
  추가, #1/#2와 겹치지 않음. `osm_liberty_yurunavi.json`은 #3 단독 소유(다른 브랜치 미변경).

## flutter analyze
No issues found!

## flutter test
89 tests, all passed (main 73 + exit-landmark 관련 11 신규 + arrival-exit-geofence 6신규 —
단 voice_engine_exit_name_test 등 exit-name-voice 쪽 테스트도 base로 함께 들어와 있어 base
71 → 여기 89로 순증가; 정확한 합은 `flutter test` 자체 출력 기준).

## 빌드
- `flutter build apk --debug` 성공 (2026-07-11, JDK21 `/home/limera/.local/jdk/jdk-21.0.7+6`
  로 JAVA_HOME 지정 — 기본 JAVA_HOME은 JDK17이라 CLAUDE.md §CAUTION대로 override 필요했음).
- APK: `/data/projects/yurunavi/build/app/outputs/flutter-apk/app-debug.apk` (224MB)

## 이번 라이딩에서 확인할 것 (한 번에 다 — 사용자 요청대로 묶음)

**#0 (지난 세션 완료, 이 APK에도 포함) U턴 patch / 국도 costing / continue·sharp-curve·audibility / nav-reroute-ui**
- HANDOFF_0711_night2.md §0 참조 — 아직 미확인 항목 전부 이번에 같이 확인.

**#1 출구 랜드마크 폴백 (`feat/exit-landmark-voice`)**
- 출구명(OSM) 있는 IC/출구 → 기존처럼 "OOO 방면 진출" 발화 유지되는지(회귀 확인)
- 출구명 없는 시골 국도 출구 근처 → "{인근 지명} 방면 {좌/우}측 출구입니다" 발화되는지
  - 방향(좌/우)이 실제 출구 방향과 맞는지
  - 지명이 너무 엉뚱하거나(예: 반대편 먼 도시) 너무 안 뜨는지(3km 내 후보 없어 그냥 "진출")
- `adb logcat -d | grep YNAV_TTS` → `key=exit_approach_landmark`/`exit_imminent_landmark` 확인

**#2 도착배너 종료버튼 게이트 (`feat/arrival-exit-geofence`)**
- 목적지 30m+속도 30km/h 이하로 서행 접근 → "종료" 버튼이 도착 직후부터 바로 활성 상태인지
  (골목 서행이면 진입 즉시 조건 충족이라 버튼이 처음부터 켜져 있는 게 정상 — 이전 카운트다운
  방식과 달리 "몇 초 기다렸다 켜짐" 연출이 없음, 오작동 아님)
- 목적지를 30km/h 넘는 속도로 그냥 통과 → 버튼이 안 뜨고 "정차 후 종료 가능" 힌트만 보이는지
- 목적지 30m 밖으로 오버슈트 → 기존 이탈감지(off-route)로 자동 재탐색 붙는지(별도 지오펜스
  로직 없이 기존 경로 재사용 — 안 붙으면 회귀)
- 절대 자동으로는 안 꺼지는지(탭 안 하면 계속 대기)

**#3 OSM 도로 스타일 (`feat/osm-road-style`) — 육안 확인 전용, 안전 문제는 아니지만 필수**
- 도로 line-width/casing, 터널·고가 음영, trunk(국도) 병합, 도로번호 배지(고속도로/국도/지방도
  3종 분리), 한글 라벨 단독 표시, 줌 6~17 제한 등이 의도대로 보이는지
- 문제 없으면 다음 세션에 `git merge --no-ff feat/osm-road-style` main 반영

## 다음 세션 진행 순서 (라이딩 결과에 따라)
- 전부 PASS → 4개 브랜치(exit-landmark-voice, arrival-exit-geofence, osm-road-style,
  그리고 base로 실려온 exit-name-voice) 각각 main에 개별 `--no-ff` 머지, `verify/ride-0711`은
  보존(과거 관례상 verify 브랜치는 삭제 안 함).
- 일부만 PASS → PASS한 것만 개별 머지, 실패분은 RECON 갱신 후 재작업.
- CORNER-VOICE-50M은 스펙 재확인 전까지 미착수(BACKLOG.md 참조).
