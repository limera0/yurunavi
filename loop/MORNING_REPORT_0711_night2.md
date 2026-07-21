# MORNING_REPORT — 2026-07-11 밤 (HANDOFF_0711_night2 이어받음, VS Code 세션)

사용자 요청: "실제 주행 테스트는 최대한 한 번에 묶어서" — 오늘 밤은 device/실기기 접근이
전혀 없는 헤드리스 서버 세션이라(adb devices 빈 목록), 라이딩·육안 확인이 필요한 항목은
전부 **구현만 완료해 하나의 verify 브랜치/APK로 묶어두고**, 다음 라이딩에서 한 번에 검증하는
방향으로 진행했다.

---

## 완료

### 1. EXIT-LANDMARK (RECON + 구현, `feat/exit-landmark-voice`)
- 전 세션 추정("MapLibre `queryRenderedFeaturesInRect`로 재사용 가능")이 틀렸음을 확인 —
  그건 화면좌표 뷰포트 쿼리라 3km 지리 반경 검색 불가. 대신 `korea.mbtiles`의 place 레이어를
  빌드 시점에 추출(`scripts/build_place_index.py`, z10, city/town/village 5,412건)해
  `assets/data/kr_places.json`로 번들 — 완전 오프라인.
  - 추출 과정에서 타일 경계 버퍼(중복 사본) 좌표를 안 걸러내면 같은 지명이 최대 55km
    어긋난 좌표로 중복 추출되는 버그 발견·수정 (스크립트 주석 + RECON_exit_landmark.md 참조).
- `exitName`(OSM) 있으면 그대로, 없고 3km 내 후보 있으면 "{지명} 방면 {좌/우}측 출구입니다",
  둘 다 없으면 기존 "진출" 유지. class 우선(city>town>village)·동급 최근접.
- `feat/exit-name-voice`(구 미병합 브랜치) 기반 위에 구현 — 그 브랜치가 main보다 39커밋
  뒤처져 있어 main으로 rebase(충돌 없이 성공, `voice_engine.dart`의 continue/sharp-curve
  분기와 exit-name 분기가 다른 라인이라 자동 병합됨).
- 테스트 17개 신규(ExitLandmarkService 5 + VoiceEngine 연동 7 + rebase로 딸려온 exit-name 3
  등), analyze/test 전부 통과.

### 2. ARRIVAL-EXIT-GEOFENCE (RECON + 구현, `feat/arrival-exit-geofence`)
- `feat/arrival-fix`(미병합, 6/26 방치)의 diff 조사 — 핸드오프가 지적한 대로 마커/도착판정/
  TTS·POI는 main에 이미 더 단순한 형태로 독립 구현돼 있어 그 부분은 버림. 유일하게 main에
  없던 §1d(지오펜스+속도 게이트 수동종료 버튼)만 그 브랜치의 `SPEC_arrival_v2.md`를 참고해
  이식.
- SPEC 자체가 "정차게이트(속도<1.0)+10초 카운트다운"을 실측 실패로 폐기하고 지오펜스로
  교체한 기록이 있어, 카운트다운 방식은 재도입하지 않음.
- 목적지 직선거리 ≤30m AND 속도 ≤30km/h일 때만 도착배너의 "종료" 버튼 활성화(그 전엔
  "정차 후 종료 가능" 힌트), 자동종료 없음. 오버슈트 재탐색은 기존 이탈감지(off-route)
  경로가 이미 커버해 별도 구현 불필요(SPEC 원안은 새로 구현해야 했으나 main 쪽 아키텍처가
  이미 더 나음).
- 순수 게이트 판정(`exitGateOpen`)을 top-level 함수로 분리해 6개 유닛테스트 추가 — NavScreen
  자체는 이 repo에 위젯테스트 하네스가 없어(placeholder뿐) 최대한 로직을 뽑아 테스트.

### 3. verify/ride-0711 통합 + APK 빌드
- `feat/exit-landmark-voice` → `feat/arrival-exit-geofence` → `feat/osm-road-style`(전
  세션에 이미 준비된 것) 3개 브랜치를 순서대로 `--no-ff` 머지, 전부 충돌 없이 자동 병합.
  analyze 0 issues, test 89/89.
- `flutter build apk --debug` 성공. **주의: 기본 JAVA_HOME이 JDK17이라 실패함** —
  `JAVA_HOME=/home/limera/.local/jdk/jdk-21.0.7+6`로 override해야 빌드됨(CLAUDE.md
  "JDK21 required" 캡션이 정확히 이 문제였음, 다음 세션도 동일하게 필요).
- APK: `build/app/outputs/flutter-apk/app-debug.apk` (224MB). 라이딩 시 설치 필요.
- 상세 체크리스트: `loop/REPORT_verify_ride0711.md`.

### 4. loop/BACKLOG.md 정리
- EXIT-LANDMARK를 READY→RIDING_QUEUE로 이동(구현 완료 표시).
- ARRIVAL-EXIT-GEOFENCE를 RIDING_QUEUE에 신규 등록.
- CORNER-VOICE-50M(§3.1) 항목을 "스펙 불명확, 보류"로 등록 — 아래 참조.

---

## 보류 (스펙 불명확 — 추측 구현 안 함)

**§3.1 코너 음성 문구 ("50m 즉시 '곧 좌/우회전' + 0m 삭제")**
- 원본 스펙 문서(HANDOFF_0712_batch.md)가 이 저장소에 없어 tonight's HANDOFF의 요약 한 줄만
  가지고 있음. 현재 코드 확인 결과:
  - turn_left/right 기본 tier: `[500,300,50]` + imminent(10m). "곧 ~"(`_fast` 접미사)는
    imminent 시점에서 속도≥20km/h일 때만 붙음.
  - "50m 즉시 곧 ~"가 (a) 50m approach 문구 자체를 "곧 ~"로 바꾸란 건지 (b) `_fast` 트리거를
    10m→50m로 앞당기란 건지 불명확.
  - "0m 삭제"도 현재 코드에 0m 발화 지점 자체가 없어(imminent=10m) 무엇을 가리키는지 불명확
    — 카드 UI의 "0m" 텍스트일 가능성도 있는데 그럼 음성이 아니라 별개 작업.
- 안전 관련 음성 안내를 추측으로 바꾸는 리스크가 커서 STOP. `loop/BACKLOG.md`
  CORNER-VOICE-50M 항목에 상세 기록.

## 손 못 댐 (우선순위상 다음)
- §3.4 POI(소상공인시장진흥공단 API 연동) — 설계부터 필요, 외부 API 키 발급 여부도 미확인.
- §3.6 백그라운드 서비스 + 오버레이 — 가장 무거움, 단독 세션 권장(전 세션 판단 유지).
- feat/osm-road-style 육안 확인 — verify/ride-0711에 이미 포함, 다음 라이딩 때 같이 확인.
- 구형 브랜치 정리(`feat/tts-audibility` 구버전, `backup-osm-20260531`, 원격 흡수 완료 브랜치들,
  `stash@{0}`) — 삭제 전 사용자 확인 필요, 미착수.

---

## 다음 세션 순서
1. **라이딩 1회로 전부 검증**: verify/ride-0711 APK 설치 → 지난 세션 미확인분(U턴 패치,
   국도 costing, continue/sharp-curve/audibility, nav-reroute-ui) + 오늘 3개(exit-landmark,
   arrival-exit-geofence, osm-road-style 육안) 한 번에.
2. PASS한 브랜치들 개별 `--no-ff` main 머지(verify 브랜치는 관례대로 보존).
3. CORNER-VOICE-50M — 원본 스펙 확인 후 착수.
4. §3.4 POI 설계 → §3.6 백그라운드(단독 세션) 순.
5. 구형 브랜치/스태시 정리 — 사용자 확인 후 일괄.

## 토큰/시간 비고
EXIT-LANDMARK의 mbtiles 좌표 변환 버그(타일 버퍼 중복) 디버깅에 예상보다 많은 시간 사용 —
다음에 비슷한 오프라인 지오데이터 추출 작업이 필요하면 `scripts/build_place_index.py`의
`tile_to_lonlat()`/버퍼 필터 로직을 그대로 재사용 가능(범용화돼 있음).
