# HANDOFF — YuruNavi (2026-07-12, Claude Code for VS Code 인터랙티브 세션)

이 세션은 릴리스 로드맵 트랙(`loop/RELEASE_ROADMAP.md`, 13번 "기능 갭 해소")에서 작업했다.
`HANDOFF_0711_night2.md`/`MORNING_REPORT_0711_night2.md`(T1/T2/T3 라이딩 검증 트랙)와는 원래
별개 트랙이었는데, **작업 도중 두 트랙이 사실은 같은 항목을 가리키고 있었다는 걸 발견**했다
— 이 문서 §2 참조. 다음 세션(어느 트랙에서 시작하든) 이 문서부터 읽을 것.

---

## 1. 이번 세션에 완료된 작업

**13-1(POI 탐색 UI) — OSM에서 공공데이터포털로 데이터소스 전면 교체 + 검색바 추가**

- 배경: 지난 세션에 OSM Overpass API로 13-1을 처음 구현했는데, 사용자가 실기기에서 확인한
  결과 한국 OSM 상가 데이터가 거의 비어있어서 못 쓴다는 게 확인됨.
- 공공데이터포털 `소상공인시장진흥공단_상가(상권)정보_API`로 교체. 사용자가 세션 도중
  직접 계정 가입 + 활용신청 + 인증키 발급까지 받아 전달(자동승인, 즉시 사용 가능했음).
  실제 인증키로 curl 라이브 검증까지 다 마치고 구현.
- 카페/편의점/주유소/마트/식당 5종 카테고리(전통시장은 이 API에 대응 업종코드가 없어 제외).
  지도 헤더에 "장소 검색" 바 신규 추가(기존 우측 패널 storefront 아이콘은 제거, 진입점
  하나로 통합), 카테고리 시트 안에 상호명 검색 TextField도 추가.
- code-auditor 2라운드 — 1차 FAIL: 마트 카테고리 코드가 실제로는 데이터가 거의 없는 코드라
  전국 어디서든 결과 0건만 나오는 상태였음(라이브 API로 직접 확인됨), 그리고 검색어/카테고리
  빠르게 바꿀 때 늦게 온 응답이 최신 상태를 덮어쓰는 경쟁 상태. 둘 다 수정 후 2차 PASS.
- **커밋**: `5ab5262`(1차 UI 골격, 이후 OSM 방식 폐기) → `2d91e4d`(공공데이터포털로 전면
  교체 + 검색바) → `d90d58b`(로드맵 갱신). 전부 `verify/ride-0711` 브랜치 위.
- **상세 사양·API 근거**: `~/.claude memory`의 `project_poi_datasource.md`(카테고리별
  정확한 업종코드, JSON 응답 형태, 이 API의 구조적 한계 — 거리순 정렬 없음, 전국 상호명
  검색 오퍼레이션 자체가 없음 등 전부 기록됨) + `loop/RELEASE_ROADMAP.md` 13-1 상세 섹션.
- **시크릿 관리**: 서비스키는 `/data/projects/yurunavi/env.json`(gitignore 처리,
  `{"SEMAS_SERVICE_KEY": "..."}`)에 로컬 저장, 빌드 시 `--dart-define-from-file=env.json`
  플래그로 주입. **이 파일은 git에 없으므로 새 체크아웃/새 서버에선 다시 만들어야 함** —
  값은 이 세션의 사용자만 알고 있음(사용자에게 data.go.kr 마이페이지에서 재확인 가능).
- `flutter analyze` 0 issues, `flutter test` 96/96, `flutter build apk --debug
  --dart-define-from-file=env.json` 빌드 성공.
- **⚠️ 미확인**: 이 서버가 헤드리스라 실기기 육안 확인을 못했음 — 검색바 UX, 카테고리 칩,
  지도 위 POI 핀 색상 렌더링이 의도대로 나오는지 다음 세션에서 `adb install`로 확인 필요.

---

## 2. ⚠️ 중요 — 두 트랙이 같은 항목이었음

`MORNING_REPORT_0711_night2.md`(어젯밤, 별개 세션)의 "손 못 댐" 목록에 **"§3.4
POI(소상공인시장진흥공단 API 연동)"**이 있었는데, 이게 정확히 이 문서 §1에서 방금 완료한
작업과 동일 항목이다. 즉:
- **T1/T2/T3 라이딩 검증 트랙 기준으로도 §3.4는 이제 완료됨** — 그 트랙 다음 세션에서 이
  항목을 다시 설계/구현하지 말 것.
- 두 트랙(`loop/RELEASE_ROADMAP.md`의 13번대, `loop/BACKLOG.md`/HANDOFF 체인의 §3.x)이
  **같은 `verify/ride-0711` 브랜치를 공유**하고 있다는 것도 이번에 확인됨 — `git log
  --oneline`으로 보면 어젯밤 T3 브랜치 머지 커밋들(exit-landmark/arrival-geofence/
  osm-road-style)과 오늘 13번대 커밋들이 한 줄로 섞여 있다. 별개 브랜치가 아니다.
- 마찬가지로 §3.6(백그라운드 서비스+오버레이)도 이 문서의 13-5와 동일 항목 — 로드맵 13-5
  행에 교차 참조 남겨둠. 착수 시 어느 쪽에서 시작하든 하나로 취급할 것.

---

## 3. 브랜치 상태 (양쪽 트랙 공통)

- **`verify/ride-0711`**, origin에 **아직 push 안 됨**, origin/main 대비 **108커밋** 앞섬.
- 이 브랜치엔 아래가 전부 섞여 쌓여있음:
  - **아직 실제 라이딩으로 검증 안 된 것**(T1/T2/T3 트랙): U턴 valhalla 패치, 국도(index 2)
    costing 버그 수정, continue-straight/sharp-curve/audibility-v2 음성, nav-reroute-ui,
    exit-landmark 음성, arrival-exit-geofence, osm-road-style(도로 표시 스타일), corner
    50m 음성 문구 변경.
  - **완료된 것**(이 로드맵 트랙): 1~12번 전부, 13-1.
- 즉 다음 라이딩 1회로 위 미검증 항목들을 전부 한 번에 확인하는 게 여전히 최우선 — 이건
  이 세션에서 새로 생긴 일이 아니라 어젯밤부터 이어지던 대기 상태다.

---

## 4. 다음 세션 우선순위 (두 트랙 합쳐서)

1. **실제 라이딩 검증 1회** — §3의 미검증 목록 전부. 가장 오래 밀려있던 항목, 코드 작업으로는
   해결 안 되고 사용자가 직접 타봐야 함.
2. **POI 기능 육안 확인** — `adb install build/app/outputs/flutter-apk/app-debug.apk`(이미
   최신 상태로 빌드돼 있음, 재빌드 시 `--dart-define-from-file=env.json` 잊지 말 것) 후
   검색바/카테고리칩/지도 핀 확인. 라이딩 전에 주차장에서 짧게 확인 가능.
3. **CORNER-VOICE-50M** — 스펙 불명확으로 보류 중(`MORNING_REPORT_0711_night2.md` 참조).
   사용자에게 원본 의도("50m 즉시 곧 좌/우회전"이 approach 문구를 바꾸란 건지 `_fast` 트리거
   타이밍을 앞당기란 건지, "0m 삭제"가 음성 지점인지 카드 UI 텍스트인지) 재확인 필요.
4. **13-2(설정: 약관/오픈소스 라이선스 화면)** — 이 로드맵 트랙의 다음 항목, 완전 독립적이고
   스코프 작음.
5. **백그라운드 내비게이션**(13-5 = §3.6) — 두 트랙 다 "가장 무거움, 단독 세션 권장"으로
   합의돼 있음. 네이티브 Android 작업이라 별도 세션 잡을 것.
6. **구형 브랜치/스태시 정리** — `feat/tts-audibility`(구버전), `backup-osm-20260531`, 원격
   흡수 완료 브랜치들, `stash@{0}`. 삭제 전 사용자 확인 필요, 계속 미착수 상태로 밀려있음.
7. **push 여부 판단** — 108커밋이 로컬에만 있음. 서버 소실 시 전부 날아감(12번 인프라
   작업에서 이미 한 번 비슷한 리스크가 실제로 있었음). 사용자와 push 시점 상의 권장.

---

## 5. 환경 (불변, 기존 핸드오프 반복)

서버 `/data/projects/yurunavi`. 헤드리스라 `flutter run` 불가 →
`flutter build apk --debug [--dart-define-from-file=env.json]` → 노트북으로 옮겨 `adb
install`. `JAVA_HOME`이 기본 JDK17이라 실패할 수 있음 —
`JAVA_HOME=/home/limera/.local/jdk/jdk-21.0.7+6`로 override 필요(CLAUDE.md "JDK21 required"
캡션이 이 문제). Valhalla 8002(`valhalla-fork:patch3-uturn`), tileserver-gl, navi 8003 전부
`docker compose`로 관리 중(12번에서 완료).
