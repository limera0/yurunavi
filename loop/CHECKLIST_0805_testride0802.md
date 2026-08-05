# CHECKLIST — 260802 실주행 피드백 35건 처리 대장

- 작성 2026-08-05 · 분석 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md)
- 원본: [testride_result/260802_testride_result.md](testride_result/260802_testride_result.md)
- **상태 표기**: `[ ]` 미착수 · `[~]` 진행중 · `[x]` 완료 · `[!]` 마스터 확인 대기 · `[-]` 스코프 밖

**진행 요약: 1 / 36 완료** (S0 코드 완료 — 실기기 콜드스타트 10회 검증만 마스터 대기.
다음은 S1 → S2 → S3 순서를 지킬 것)

---

## 🔴 P0 — 출시 차단급

### S0 · 앱 시작 시 내 위치 표시 (신규, 마스터 지시)  `상태: [x]` — 코드 완료, 실기기 검증만 남음

> **완료 2026-08-05** · 커밋 `7c2cd29`(구현) + `b72d9a6`(첫 실행 예산 1초)
> code-auditor 1차 FAIL → 수정 → 2차 **PASS**. `flutter analyze` 이슈 0 ·
> `flutter test` **314건 전부 통과**(신규 10건).

> **원인 확정**: `main_map_screen.dart:62` `kInitialMapView = LatLng(36.5, 127.5)`
> — 이 좌표가 **대청호 청남대 자리**다. `:1665` `initialCameraPosition`이 첫 빌드에
> `_origin ?? _lastKnown ?? kInitialMapView`를 평가하는데 앞의 둘이 아직 null이라
> 폴백이 걸리고, MapLibre `initialCameraPosition`은 **1회만 읽혀** 이후 위치가
> 와도 카메라가 안 움직인다.

- [x] 스플래시 로고 애니메이션과 **동시에** 위치 확보 시작 — 권한 기보유 시
      (2회차 이후 전부) 애니메이션과 완전 병렬. 추가 지연 0
- [x] `getLastKnownPosition()` 즉시 → `getCurrentPosition()` 예산 대기.
      예산은 경로별로 다르다: 권한 기보유 **3초**(`kBootLocationBudget`) /
      최초 설치 **1초**(`kFirstRunBootLocationBudget`, 마스터 결정 — 그 경로는
      애니메이션이 끝난 뒤라 대기가 그대로 체감 지연이 됨)
- [x] 확보 좌표를 provider로 전달 → `initialCameraPosition`이 첫 빌드부터 실제 위치 사용
      (`bootLocationProvider` 신설 → `initState`에서 `_lastKnown` 시드)
- [x] 폴백으로 열렸을 경우, **첫 실측 fix 도착 시 카메라 자동 이동**
- [x] `kInitialMapView`는 권한거부+마지막위치없음일 때만 쓰이는 최후 폴백으로 격하
- [ ] **검증**: 콜드 스타트 10회 중 10회 내 위치에서 열림 ("내 위치" 버튼 불필요)
      — **마스터 실기기 수동 검증 대기**

> **추가 발견 (RECON §8-5에 없던 두 번째 원인).** `initialCameraPosition` 1회
> 읽힘만이 원인이 아니었다. `main_map_screen.dart`에 이미 첫 fix 시
> `_mlCtrl?.animateCamera(...)`가 **있었으나**, `_mlCtrl`은 `onMapCreated`에서야
> 세팅된다. 플랫폼뷰 생성 대기 중 fix가 먼저 도착하면 널세이프 호출이 조용히
> 버려지는 **동시에 `isFirstFix`가 소진**되어 재시도가 영영 없었다.
> → `FallbackRecenterState` 신설로 해결: "폴백 좌표로 열렸는가"와 "실측 fix로
> 보정됐는가"를 분리하고, 컨트롤러 미준비 시 목표를 **항상 보류**했다가
> `onMapCreated`에서 적용한다. (1차 감사에서 이 분리가 불완전해 FAIL —
> 부트 좌표가 있는 정상 경로에서 첫 fix가 여전히 버려지는 게 잡혔다.)

> **잔여 리스크 (감사자 표시: 미검증 추론).** 보류 저장은 `_mlCtrl == null`
> 구간에서만 일어나므로 "사용자 수동 팬을 잡아채지 않는다"가 성립한다는 논증은,
> MapLibre 네이티브 뷰가 `onMapCreated` 직전 수 ms 창에서 제스처를 받는지까지는
> Dart 소스만으로 확인 불가. 창이 극히 좁고 이번 변경이 만든 문제가 아니라
> `maplibre_gl` 플러그인 배관에서 상속된 것이라 조치 없이 기록만 남긴다.

### S1 · 백화·크래시 완전 정지  `상태: [ ]`

> 근본원인 A. `clamp` 상한 음수 → 초당 2~3회 예외 → ErrorWidget 흰 박스.
> 로그 56,789건 · Firebase 362건/6명으로 **확정**.

- [ ] `lib/core/widgets/daylight_bar.dart:109` — `handleY.clamp(0.0, totalH - 24)` 방어
      (상한이 하한보다 작으면 클램프 자체를 건너뛰거나, 게이지 높이가 부족하면 렌더 생략)
- [ ] 같은 파일 `:95` `handleY` 계산도 음수 `totalH` 대응 확인
- [ ] **`clamp` 전수 감사 — 빈 리스트 시 상한 -1이 되는 12곳**
  - [ ] `route_progress_provider.dart:320, 374, 378`
  - [ ] `routing_service.dart:935, 941`
  - [ ] `nav_screen.dart:563, 850, 1700, 1785, 1800`
  - [ ] `main_map_screen.dart:1362, 1530, 1556`
  - [ ] `waypoint_management_sheet.dart:49`
  - [ ] `user_profile.dart:26`
  - [ ] `nav_screen.dart:3031` — `nextCameraPostZoneM` 음수 가능성
- [ ] 릴리스 빌드 `ErrorWidget.builder` 커스텀 — 흰 박스 대신 무해한 폴백
- [ ] `DaylightBar`에 최소높이 보장 (부족하면 축약형 렌더)
- [ ] `lib/widgets/daylight_bar.dart` re-export shim 정리 여부 판단
- [ ] **검증(주)**: 위젯 테스트 — 높이 `[0,10,24,90,118,120,285,300,800]`px 전 케이스
      `tester.takeException() == null` (285px = 플립7 커버화면 근사 → **기기 없이 커버**)
- [ ] **검증(보조)**: A34에서 `adb shell wm size 720x748`로 커버화면 흉내 → 실렌더 확인
      (끝나면 `wm size reset` 필수)
- [ ] **검증(조합)**: 세로/가로 × 코스시트 × 일반/PIP/분할화면 `Invalid argument(s): 0.0` **0건**

### S2 · 네트워크 폭주 차단  `상태: [ ]`

> 근본원인 B. 초당 ~10회 POI 요청, 69,875건 전부 429. 데이터·배터리 주범.

- [ ] `main_map_screen.dart:634` — **디바운스 부재** 해소 (nav_screen과 동일 정책으로 통일)
- [ ] `nav_screen.dart:1412` — `sameTypes == false`일 때 디바운스 우회되는 경로 차단
- [ ] **429 서킷브레이커 + 지수 백오프** 신설 (`poi_service.dart`) — 현재 코드베이스에
      429 처리가 **한 줄도 없음**
- [ ] **실패 응답을 캐시에 넣지 않기** — `poi_service.dart:70-72, 118-121`이 `[]` 반환 →
      호출부가 정상 결과로 `put()` (`nav_screen.dart:1486`, `main_map_screen.dart:696`)
- [ ] `fetchPois*`가 상태코드/예외를 호출부에 전달하도록 반환 타입 변경
- [ ] **bbox 그리드 스냅** — 현재 `center ± 0.02°`라 1m만 움직여도 캐시 미스
      (`PoiRegionCache.tryGet` 포함관계 조건, `poi_service.dart:433`)
- [ ] **in-flight 요청 취소** — `_ambientFetchGen`은 응답만 버리고 HTTP는 안 끊음.
      `http.Client` 재사용 + abort
- [ ] 타일 캐시 정책 점검 (1.65GB 배분 실측)
- [ ] **검증**: 가상GPS 1시간 주행 → POI 요청 < 60건, 429 = 0

### S3 · 라이프사이클 정상화  `상태: [ ]`

> 근본원인 C. `inactive`가 알림창·캡쳐·엣지패널에서도 발화 → PIP 오진입 → 안내 중단.

- [ ] `nav_screen.dart:460` — `AppLifecycleState.inactive` 분기 제거,
      **`onUserLeaveHint`(`nav_pip_hint` 채널, 이미 구현됨) 전용**으로 전환
- [ ] `hidden` 분기 유지 여부 판단 (화면 꺼짐 케이스 보완 목적이었음)
- [ ] `NavForegroundService.kt:68` — `START_NOT_STICKY` → `START_REDELIVER_INTENT`
- [ ] **wakelock 3중 정리**: geolocator `enableWakeLock` + `WakelockPlus` + FGS
- [ ] 알림 2개(geolocator FGS + NavForegroundService) 일원화
- [ ] PIP/백그라운드 중 지도 API 호출 가드
      (`MissingPluginException` — `source#setGeoJson` 431건, `camera#move` 136건)
- [ ] PIP 복구를 **우측 작은 아이콘 터치**로 (마스터 요구: 화면 터치 아님)
- [ ] **검증**: 알림창 내림·스크린샷·엣지패널 → PIP 진입 안 함 / 홈 버튼 → PIP 진입 /
      홈 상태 30분 유지 후 안내·히스토리 정상

---

## 🟠 P1 — 주행 품질

### S4a · 안내 거리 재조정 (JSON만, 리스크 0)  `상태: [ ]`

> `assets/config/guidance_profile.json` 값 수정만으로 해결. 코드 변경 없음.

- [ ] 모든 안내 **50m 앞당김**: 500→550, 300→350, 100→150, 50→100
- [ ] **0m(해당 지점) 안내 삭제** — 전역 `imminent_m: 10` 제거 또는 상향
- [ ] 원형교차로 티어 축소 — 현재 진입만 4회(300/100/30/10)
- [ ] `turn_left`/`turn_right` `imminent_m: 50` → 100 검토

### S4b · 안내 중재기 신설  `상태: [ ]`

> **구조적 결함**: `voice_engine.dart`의 독립 엔진 4개가 서로를 모른 채 각자 발화.
> 로그 실측 — 한 로터리에서 92초간 **9회 발화**.

- [ ] `GuidanceArbiter` 신설 — 4개 엔진(`VoiceEngine:47`, `StructureVoiceEngine:182`,
      `CurveVoiceEngine:255`, `RearCameraVoiceEngine:329`) 출력 통합
- [ ] 이벤트 **우선순위** 정의 (안전 우선 — memory: `feedback_safety_priority`)
- [ ] **최소 발화 간격** 도입 (권고 4초) — 초과분은 큐잉이 아니라 **폐기**
- [ ] **상호 억제** — 로터리 안내 중 급커브 안내 억제 등
- [ ] `_profileEventKey()` (`voice_engine.dart:41`) — `roundabout_enter`/`roundabout_exit`
      **분리** (현재 한 키로 병합되어 진출만 못 끔)
- [ ] **원형교차로 진출 안내 전부 삭제** (마스터: "진입만 안내하면 됨")
- [ ] 통과 후 안내 지속 문제 — 30m 이상 벗어나면 pending 큐 폐기
- [ ] **검증**: 한 교차로당 3회 이하 / 간격 4초 이상 / `roundabout_exit_*` 0건

### S4c · TTS 숫자 한글화  `상태: [ ]`

> 로그 전수 확인 — 앱이 1100 같은 이상값을 낸 적 **없음**. 기기 TTS 엔진 문제.
> 결정론적 해법은 숫자를 아예 안 넘기는 것.

- [ ] 발화 전 거리 **50m 단위 스냅** (현재 `dist=43`, `dist=9` 등 비정형 값 발화됨 —
      `voice_engine.dart:94` `_immediatePoint = entryD` 경로)
- [ ] `{dist}`를 **한글 수사로 프리렌더** (`300 → 삼백`)
- [ ] `1000m → "일 킬로미터"` 단위 정규화
- [ ] **검증**: 실기기 발화 청취 + `YNAV_TTS` `dist=` 값이 전부 50 배수

### S5 · 정차 모드 + 전력  `상태: [ ]`

> `YNAV_REROUTE` 분당 최대 151건. `distanceFilter: 0` + 정지 GPS 지터가 원인.

- [ ] **정차 모드** 신설 — 속도 < N km/h가 T초 지속 시 재탐색·POI·카메라추종 정지
- [ ] `map_providers.dart:77` `distanceFilter: 0` → 속도 연동 가변
- [ ] `accuracy: bestForNavigation` 정차 시 다운시프트
- [ ] `map_providers.dart:71` `ref.keepAlive()` 재검토 — 홈/설정 화면에서도 1Hz 상시 구동
- [ ] 재탐색 origin 오프셋 **40m → 50m** (`nav_screen.dart:842`, `:1643`)
- [ ] (선택) Thermal Governor — Android `PowerManager` 열 상태 연동 FPS/GPS 다운시프트
- [ ] **검증**: 정차 10분간 `YNAV_REROUTE` 0건 / 배터리 소모 측정

### S6 · 로터리 안내 재설계  `상태: [ ]` — **원인 확정, 조사 단계 불필요**

> **2026-08-05 자체 Valhalla 서버 직접 프로브로 재현 완료.**
> 검단회전교차로 **6개 진입/진출 조합 전부 `roundabout_exit_count=2`**.
> 프로브 4지점이 서로 다른 way에 스냅됨을 `/locate`로 확인(같은 진입로에서 세 방향으로
> 나가는데 셋 다 "2번째 출구" → 최소 2개는 명백히 오답).
> **공개 업스트림 Valhalla(FOSSGIS)도 동일** → **우리 포크 결함 아님. 앱 파싱 버그도 아님.**
> → **`roundabout_exit_count`를 신뢰하면 안 된다.**

- [ ] **출구 번호 발화 폐기** — `voice_engine.dart:125-144`의 `{exit}` 주입 경로 제거
- [ ] **진입/진출 방위차로 방향 직접 계산** (좌/직/우) — 앱에 이미 있는 shape·bearing
      활용 (`native_engine.dart`, `PoiService.bearing`)
- [ ] `default_ko.json:64-68` `{exit}` 사용 템플릿 4종 교체
      → "회전교차로에서 우측 방향입니다" 형태
- [ ] 근거: memory `feedback_accurate_maneuver_wording` — **틀린 출구 번호를 말하느니
      안 말하는 게 낫다.** 라이더에게 필요한 건 번호가 아니라 방향
- [ ] (우선순위 하향) "원형교차로인데 우회전이라고 안내함" — Valhalla가 type 26 대신
      9/10을 내는 별개 증상(`mini_roundabout` 가설). 위 수정 시 방향은 어차피 맞음
- [ ] **검증**: 검단 6개 조합에서 앱 계산 방향이 실제 방위차와 일치 (프로브 스크립트 재사용)

### S7 · 터널 추측항법  `상태: [ ]`

- [ ] 터널 zone(`StructureType.tunnel`) 진입 + GPS 상실 동시 감지
- [ ] 직전 1분 평균속도 **× 1.05**로 경로 shape 따라 위치 시간적분 전진 (마스터 제안)
- [ ] 터널 출구 도달 또는 GPS 복귀 시 스냅 복원
- [ ] 추측항법 중 재탐색 금지 가드
- [ ] **검증**: 가상GPS로 터널 구간 GPS 드롭 시나리오 재생

### S8 · UI 잔여  `상태: [ ]`

- [ ] **시스템바 색상** — 홈: 상단/하단 모두 투명 / 내비: 상단 투명, 하단 검정
      (`main.dart:47`, `nav_screen.dart:362`, `dispose():488` 3곳 동기화)
- [ ] **주유소 경유지 마커 미표시** — `nav_screen.dart:1512` `_initDestLayer()`가
      `_destLayerReady` 가드로 1회만 실행 + 불변 `widget.waypoints`를 읽음.
      주행 중 추가분은 `_liveWaypoints`(`:378`)로 들어가 영영 안 그려짐 → **원인 확정**
- [ ] 하단 카드 — 전체 거리 → **남은 거리**
- [ ] 하단 카드 — 현위치(시/군/구)를 목적지와 **3초 간격 교대 표시**

---

## 🟡 P2 — 데이터·라우팅

### S9 · 자동차전용도로 하드 배제  `상태: [ ]`

> **오토바이 법적 절대 원칙** (memory: `project_motorcycle_legal_constraints`).
> 현재는 소프트 패널티라 대안 없으면 뚫고 지나간다.

- [ ] `routing_service.dart:157, 178` — `use_highways: 0.0` + `highway_classes {'0':100}`
      **패널티 → 하드 배제**로 전환
- [ ] **`motorroad=yes` 태그 배제** — 38번 지방도 사례의 핵심.
      `use_highways`/`highway_classes`가 이 태그를 **전혀 보지 않음**.
      ⚠️ **`native/`(Rust) 아님 — Valhalla 포크(C++) 코스팅 수정 필요**
- [ ] 나무위키 자동차전용도로 목록으로 **검증 좌표셋** 구성
- [ ] **검증**: 검증셋 전 구간에 대해 경로가 진입하지 않음

### S10 · 지방도 좌회전 오안내 억제  `상태: [ ]`

- [ ] Valhalla 응답에 `road_class` 포함 여부 **계약 확인** (curl)
- [ ] `ManeuverStep`에 진입/진출 도로 등급 추가 (`routing_service.dart:46` 근처)
- [ ] **등급 유지·상승 회전은 안내 억제, 하락할 때만 안내** (마스터 요구 그대로)
- [ ] memory `feedback_accurate_maneuver_wording` 준수 — 실제 회전이 아닌 이벤트에
      "회전" 표현 금지

### S11 · 고급휘발유 미표시  `상태: [ ]`

- [ ] **S2 완료 후 재현되는지 먼저 확인** — 429 폭주 + 실패 캐싱(§S2)이 원인이면
      이미 해결됐을 수 있음
- [ ] 재현 시: `gas_station_service.dart:14` `premiumPrice` 서버 응답 실측
- [ ] `nav_screen.dart:2685` B034 표시 경로 점검
- [ ] 참고: `MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md` (기존 수정 이력)

### S12 · 도로 색상  `상태: [ ]`

- [ ] `assets/images/osm_liberty_yurunavi.json` — 국도만 노란색, 지방도 흰색
- [ ] OSMAND·네이버지도 대조

### S13 · Valhalla CI 실패  `상태: [ ]` — 우선순위 최하

- [ ] 포크의 "Clear S3 cache" 워크플로 비활성화 (앱과 무관, 업스트림 잔재)

### ~~Google API 결제 확인~~  `상태: [x] 종결`

- [x] **7월 5일 발생분, LLM-Wiki 작업으로 확인됨. 유루나비와 무관 — 스코프 제외.**

---

## 🟢 P3 — 기능개선 (출시 후 가능, 별도 트랙)

- [ ] 검색바 탭 시 최근 검색지/목적지 리스트 표시
- [ ] 통합 검색 (주소 + 상호)
- [ ] 점포명 검색 결과 지도 위치 기준 **가까운 순** 정렬
- [ ] **이어서 안내하기** — 중간 종료/비정상 종료 후 내비 재개
      (⚠️ `TourRecoveryService`는 히스토리 복구만 함 — 안내 재개는 **미구현**)
- [ ] 투어 히스토리 **병합(merge)** 기능
- [ ] 경로 색상 네이버급 초록 + 진행방향 화살표
- [ ] 오프라인 지도 다운로드 (도 단위, WiFi 전용 옵션)
- [ ] 지도 정보밀도 OSMAND급 (건물 내부 정보 등)
- [ ] 코스 공유 (QR, 2인 이상 투어 동기화)
- [ ] OSMAND / Organic Maps 벤치마킹 조사

### `[-]` 스코프 밖 — 하지 말 것

- [-] **MapLibre GL Native 이관** — **이미 되어 있음** (`maplibre_gl: ^0.26.1`).
      Gemini 권고의 전제가 틀림. 상세: RECON §0
- [-] **Kotlin/Swift 전면 리팩터** — 이번 결함 중 언어·아키텍처가 원인인 건 **없음**
- [-] **모듈화 + Rust/C++ 이관 검토** — P0~P2 완료 후 **재측정하고 나서** 판단.
      지금 착수하면 실측 없는 최적화가 됨

---

## ✅ 마스터 회신 완료 (2026-08-05) — 블로커 없음

- [x] **1. 플립7 로그** — 동행한 **반장의 폰**이며 확보 가능성 낮음.
      **그 폰은 사건 이후 유루나비 사용 중단 (사용자 이탈 1명)** → S1 우선순위 근거 강화.
      **→ S1 검증을 로그 의존에서 분리**, 위젯 테스트(높이 285px 포함)로 결정론적 대체.
      로그는 더 이상 블로커 아님
- [x] **2. Google 결제** — 7월 5일 발생분, LLM-Wiki. **무시. 종결**
- [x] **3. 로터리** — "거의 모든 로터리에서 발생" → 이 정보로 서버 직접 프로브 →
      **원인 확정(§S6). 앱 버그 아님, 포크 결함도 아님**
- [x] **4. P1 순서** — **S4a 먼저** 승인됨
- [x] **5. (신규) 앱 실행 시 청남대 표시** — `kInitialMapView = LatLng(36.5, 127.5)`가
      청남대 좌표. **원인 확정 → S0 신설**
