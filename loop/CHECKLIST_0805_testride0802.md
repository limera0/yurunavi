# CHECKLIST — 260802 실주행 피드백 35건 처리 대장

- 작성 2026-08-05 · 분석 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md)
- 원본: [testride_result/260802_testride_result.md](testride_result/260802_testride_result.md)
- **상태 표기**: `[ ]` 미착수 · `[~]` 진행중 · `[x]` 완료 · `[!]` 마스터 확인 대기 · `[-]` 스코프 밖

**진행 요약: 3 / 37 완료** (S0·S1·S2 코드 완료 — 실기기 검증만 마스터 대기.
**S1b 신설** — 마스터 스크린샷 실측으로 백화가 두 개의 별개 결함이었음이 밝혀졌다.
다음은 S1b(조사) → S3)

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

### S1 · clamp 크래시 정지  `상태: [x]` — 코드 완료, 실기기 검증만 남음

> ⚠️ **범위 정정 (2026-08-05, 마스터 스크린샷 실측 후).**
> 이 항목의 원래 제목은 "백화·크래시 완전 정지"였고 완료 보고도 그렇게 냈다. **과했다.**
> 마스터가 실제로 눈으로 본 백화(`Screenshot_20260801_062518_Yurunavi.jpg`)는
> **이 결함이 아니다** — 픽셀 실측으로 확정했다(아래 S1b).
> S1이 고친 건 로그 56,789건·Firebase 362건의 **clamp 예외**이며 그건 실재한다.
> 그러나 **화면이 하얗게 나오는 증상 자체는 S1b로 넘어간다.**

> **완료 2026-08-05** · 커밋 `87c232e` · 지시서 [HANDOFF_0805_S1_crash_stop.md](HANDOFF_0805_S1_crash_stop.md)
> code-auditor **1차 PASS**. `flutter analyze` 이슈 0 · `flutter test` **359건 전건 통과**(신규 45건).

> 근본원인 A. `clamp` 상한 음수 → 초당 2~3회 예외 → ErrorWidget 흰 박스.
> 로그 56,789건 · Firebase 362건/6명으로 **확정**.

- [x] `lib/core/widgets/daylight_bar.dart` — 핸들 `top`을 `clampSafe`로 교체 +
      `totalH` 비유한·`<=0` 차단 + `totalH < 24`면 핸들 아이콘 생략(바만 렌더)
- [x] 같은 파일 `handleY` 계산 경로도 위 가드 뒤로 들어가 음수 `totalH` 도달 불가
- [x] **`clamp` 전수 감사 — 현재 HEAD 기준 재확인 결과 목록의 절반은 이미 안전했다**
  - [x] `route_progress_provider.dart:320` `_clampIdx` — **수정**(빈 `_pts` 시 0 반환)
  - [x] ~~`route_progress_provider.dart:374, 378`~~ — **이미 안전.** 함수 최상단 `:369`에
        `if (_cumFromStartM.isEmpty || _zones.isEmpty) return null;` 존재(2026-07-27부터).
        RECON이 낡았던 것 — 코더가 확인하고 수정 거부한 게 옳다
  - [x] ~~`routing_service.dart:935, 941`~~ — **이미 안전** (진입부 `isEmpty` 가드)
  - [x] `nav_screen.dart:563` — **수정**(빈 `_steps` 시 clamp 건너뛰기).
        매 progress 틱마다 호출되는 폭주 경로였다
  - [x] ~~`nav_screen.dart:850, 1700, 1785, 1800`~~ — **이미 안전** (`isNotEmpty` / `length < 2` 가드 안쪽)
  - [x] `main_map_screen.dart` **2곳 수정** — `:1455`(빈 `routes`),
        `:1623`(빈 `_fetchedRoutes`). **`:1623`은 원래 체크리스트에 없던 곳인데
        실제로 위험했다** — 바로 다음 줄이 `selIdx < length`를 검사하고 있었으니
        작성자도 빈 경우를 알았지만 clamp가 먼저 터졌다. (줄번호는 S0 커밋으로 밀린 값)
  - [x] `waypoint_management_sheet.dart:49` — **수정**(빈 `routes` 조기 반환)
  - [x] ~~`user_profile.dart:26`~~ — **이미 안전** (`bikes.isNotEmpty ? … : null`)
  - [x] `nav_screen.dart:3031` `nextCameraPostZoneM` — **수정**(`clampSafe`, 순수 수치라 인덱싱 없음)
- [x] `lib/core/utils/safe_clamp.dart` 신설 — `clampSafe`(상한<하한이면 하한 반환).
      **단, 리스트 인덱싱이 뒤따르는 자리엔 쓰지 않았다** — 안 던지는 대신 `RangeError`로
      증상만 바뀌므로 그런 자리는 전부 조기 반환으로 처리
- [x] 릴리스 빌드 `ErrorWidget.builder` 커스텀 — 투명 `SizedBox.shrink()`.
      **`kReleaseMode`일 때만** — 디버그는 기본 빨간 박스 유지
- [x] `DaylightBar` 최소높이 보장 — 가용높이 `<72` shrink / `72~118` 축약형(시간 라벨 생략) /
      `>=118` 전체. **72는 라벨 없는 고정 크롬 실측치**(10+18+8+8+18+10).
      지시서는 60을 제시했으나 그 값이면 `RenderFlex overflow`가 남아 코더가 72로 올렸다 —
      감사에서 산수 검증됨
- [x] `lib/widgets/daylight_bar.dart` re-export shim — 참조 0건 확인 후 **삭제**
- [x] **(추가) 크래시 로그 폭주 차단** — `crash_reporting.dart`에 동일 시그니처 억제
      (최초 1회 + 60초 1회, `suppressed=N` 병기, 맵 상한 50 LRU).
      초당 2~3회의 디스크 append + Crashlytics 업로드가 발열·배터리의 직접 원인이었다
      (RECON §2-3). `FileLogger`가 `debugPrint`를 후킹하므로 이 억제로 디스크·네트워크가 함께 멎는다
- [x] **검증(주)**: 위젯 테스트 — 높이 `[0,10,24,60,71,72,90,117,118,120,285,300,800]`px
      × progress `[0.0,0.5,1.0]` 전 케이스 `tester.takeException() == null`.
      285px = 플립7 커버화면 근사 → **기기 없이 커버**. 71/72·117/118은 분기 임계값 양옆 경계값
- [x] **검증(회귀)**: `route_progress_empty_route_test.dart` — 빈 `_pts` + 비어있지 않은
      `maneuvers`(재탐색 중 경로 일시 소멸) 케이스가 수정 전 코드에서 실제로 던졌음을 감사자가 역추적 확인
- [ ] **검증(보조)**: A34에서 `adb shell wm size 720x748`로 커버화면 흉내 → 실렌더 확인
      (끝나면 `wm size reset` 필수) — **마스터 실기기 수동 검증 대기**
- [ ] **검증(조합)**: 세로/가로 × 코스시트 × 일반/PIP/분할화면 `Invalid argument(s): 0.0` **0건**
      — **마스터 실기기 수동 검증 대기**

> **로그 타임라인 추가 발견 (2026-08-05).** RECON §2-4는 트리거를 "코스시트 열림이
> 유력"까지만 짚었는데, 로그를 맞춰보니 그보다 나쁘다.
> `08:05:18` 앱 시작 → **`08:06:43` 크래시 시작**(85초) → `08:09:36` 내비 시작.
> **크래시가 내비보다 3분 먼저, 홈 화면에서 시작했다.** 그리고 `_startNavigation`은
> **코스 시트를 닫지 않고** 내비를 그 위에 push한다(`_showCourseSheet=false`는
> 내비 pop 후 `_clearDestination()`에서야 실행). 즉 홈 화면이 시트 열린 지오메트리
> 그대로 밑에 살아남아 **주행 3시간 51분 내내 계속 던졌다.**
> 홈 구간 크래시 간격은 정확히 **1.000초** — GPS 1Hz 틱마다 리빌드 1회 = 예외 1회.
> (S1 수정으로 던지지는 않게 됐지만, **내비 중 홈 화면이 시트 열린 채 살아있는 구조
> 자체는 그대로다.** 불필요한 리빌드·메모리 점유원이므로 S1b/S3에서 함께 볼 것.)

> **잔여 (스코프 밖으로 판단, 조치 없음).** `tour_summary_detail_screen.dart:199`
> `.clamp(squareMapHeight, screenWidth * 3.0)`은 `screenWidth < 33.3` 논리픽셀에서만
> 역전된다 — 실기기 도달 불가로 보고 건드리지 않았다.

> **크래시 억제 로직 자체엔 단위테스트가 없다** (감사자 지적, 비차단).
> `crash_reporting.dart`는 Firebase 초기화와 얽혀 있어 테스트 하네스 비용이 크다.
> 나중에 억제 정책만 순수 클래스로 떼면 붙일 수 있다.

### S1b · 렌더링 자원 고갈 — 껍데기만 그려지고 내용물 소실  `상태: [ ]` — **조사 먼저**

> **신설 2026-08-05.** 근거: `testride_result/Screenshot_20260801_062518_Yurunavi.jpg` 픽셀 실측.
> 마스터 보고 4건("속도계 하얗게" / "일출일몰 바 하얗게" / "내 위치 화살표 없음" /
> "재탐색하며 코스 엉킴")이 한 장에 다 찍혀 있다.

> **S1(clamp 예외)이 아님이 확정됐다.** Flutter 릴리스 `ErrorWidget`은 그 자리를
> `0xF0C0C0C0` = **회색 (196,196,196)**으로 덮는다(SDK `rendering/error.dart:115` 실측).
> 그런데 스크린샷 실측값은 **일출일몰 바 내부 (253,253,253) · 속도계 원 내부 (255,255,255)** —
> **순백이다.** 위젯이 오류로 갈린 게 아니다.

> **관측된 현상**: 컨테이너·장식은 완벽히 그려지는데 **자식 내용물만 전부 소실**된다.
> - 속도계 — 주황 테두리 원은 정상, 안의 숫자만 없음
> - 일출일몰 바 — 흰 알약 + 그림자 정상, 반투명이라 뒤 도로가 비쳐 보임.
>   그런데 해/달 아이콘·시간 라벨은 물론 **게이지 막대(단순 색칠 Container)까지** 없음
> - 내 위치 — **파란 원만 남고 방향 화살표 스프라이트 소실**(지도 엔진 쪽에서도 동시 발생)
> - 반면 상단 안내카드 텍스트·지도 도로 라벨은 **정상 렌더** → 전면 실패가 아닌 부분 실패
> - **로그에 아무 흔적도 안 남는다** — 예외가 아니기 때문(`YNAV_CRASH`는 전부 clamp 건)

> **마스터 지시 — 이 항목의 목표 수준.**
> 마스터는 테스트 중 **다른 앱을 전혀 안 켰다.** 앱을 잔뜩 띄워둔 일반 사용자,
> 저사양 폰, 플립처럼 백그라운드 메모리 점유가 큰 폰에서는 **훨씬 심하게 터진다고 봐야 한다.**
> → **목표: 기기 사양·메모리 압박 상태와 무관하게 안정적으로 구동.**
> 재현이 안 된다고 덮지 말 것 — 재현 환경을 만드는 것부터가 이 항목의 일이다.

- [ ] **1단계 · 재현 조건 확보** (이게 안 되면 나머지 전부 무의미)
  - [ ] 메모리 압박 인위 조성 — `adb shell am send-trim-memory <pid> RUNNING_CRITICAL` 등
  - [ ] 가상GPS 장시간 주행 재생 (memory `project_vgps_testing` — 3-provider 모킹 필수)
  - [ ] 계측: `dumpsys gfxinfo` · `dumpsys meminfo` · logcat의 Vulkan/Impeller/atlas/OOM
  - [ ] 발현까지 걸린 시간·주행거리 기록 (마스터 관측: 내비 실행 후 **10분쯤**)
- [ ] **2단계 · 렌더러 변수 격리** — Flutter 3.44 + 안드로이드 기본 = Impeller.
      매니페스트에 명시 설정 없음. Impeller on/off 동일 시나리오 A/B
- [ ] **3단계 · 메모리 압박 대응 부재 확인** — 앱에 `didHaveMemoryPressure()` 대응이
      있는지, 이미지·타일 캐시가 압박 시 줄어드는지
- [ ] **4단계 · 방어 설계** (원인과 무관하게 효과 있는 것부터) — 저사양/압박 감지 시
      품질 다운시프트. S5의 Thermal Governor, S2의 타일 캐시 1.65GB와 같은 계열
- [ ] **S1 수정 후 재측정** — clamp 예외 56,789건이 스택트레이스·Crashlytics 업로드로
      메모리를 계속 먹고 있었다. 그게 멎었으니 **S1b 빈도가 줄었을 수 있다.**
      먼저 재측정하고 남은 만큼만 대응할 것
- [ ] **검증**: 백그라운드에 앱 다수 띄운 상태 + 저사양 기기에서 1시간 주행 —
      속도계·게이지·위치 화살표가 끝까지 정상 렌더

> **"재탐색하며 코스 엉킴"은 아직 미확정.** 이 스크린샷의 초록 스파이크는 상단 카드가
> **유턴 아이콘**을 띄우고 있어 실제 유턴 경로일 수 있다. 렌더링 문제인지 라우팅
> 문제인지 **구분 전까지 어느 쪽으로도 단정하지 마라.**

### S2 · 네트워크 폭주 차단  `상태: [x]` — 코드 완료, 실기기 검증만 남음

> 근본원인 B. 초당 ~10회 POI 요청, 69,875건 전부 429. 데이터·배터리 주범.
>
> **2026-08-05 작업 중 정정**: RECON이 지목한 `onCameraIdle` 디바운스 부재는
> 부차적 원인이었다. 진짜 주범은 `main_map_screen._maybeFetchSearchPrefetch`·
> `nav_screen._maybeFetchAmbientPois`가 디바운스 타임스탬프를 **await 이후
> 성공 경로에서만** 커밋해, 응답이 1 디바운스 주기 안에 안 돌아오면 디바운스가
> 영원히 무장되지 않고 1Hz로 무한 재시도되던 결함. `loop/HANDOFF_0805_S2_network_flood.md`
> §0 참고.

- [x] `main_map_screen.dart:634`(현 `:742`) — **디바운스 부재** 해소 (nav_screen과
      동일 정책 15초/200m로 통일, 공용 `PoiFetchThrottle`)
- [x] `nav_screen.dart:1412` — `sameTypes == false`일 때 디바운스 우회되는 경로 차단
      (`typeChangeMinInterval` 3초 하한 적용, 홈 ambient도 동일 규칙)
- [x] **429 서킷브레이커 + 지수 백오프** 신설 (`poi_service.dart`) — 1→2→4→8→16→32→60초
      상한, `Retry-After` 헤더 우선 존중(최대 300초), 서킷 오픈 시 HTTP 요청 자체를
      만들지 않음
- [x] **실패 응답을 캐시에 넣지 않기** — `fetchPois`/`fetchPoisInBounds`가 실패 시
      `PoiFetchException`을 던지므로 호출부가 `put()`을 아예 안 탄다(try 블록 안에서만
      fetch+put, catch는 조용히 스킵 — 기존 POI 유지)
- [x] `fetchPois*`가 상태코드/예외를 호출부에 전달하도록 반환 타입 변경 —
      `PoiFetchException { statusCode, circuitOpen, message }` 신설, 모든 호출부
      (`main_map_screen` ambient/search-prefetch/검색시트, `nav_screen` ambient) 수정
- [x] **bbox 그리드 스냅** — `PoiService.snapBoundsOutward()` 신설(1-2-5 nice 스텝,
      span/4). 네트워크·캐시 put/get은 스냅 bbox, 표시는 실제 뷰포트로 필터링한
      candidates만 사용(화면 밖 POI 방지)
- [x] **in-flight 요청 취소** — 태그별(`ambient-home`/`ambient-nav`/`search-prefetch`/
      `search-sheet`) `http.Client`를 두고 새 요청 시작 전 이전 client `close()`.
      화면 쪽엔 `_ambientFetchInFlight`/`_searchPrefetchInFlight` 플래그로 재진입 자체를 차단
- [ ] 타일 캐시 정책 점검 (1.65GB 배분 실측) — **조사만 수행, 코드 변경 안 함.**
      `map_cache_provider.dart`는 `maplibre_gl` 전환 후 `unused_import` 하나뿐인 죽은
      코드로 확인됐으나, 삭제 여부는 판단이 애매해 이번 세션에선 보류(보고서 참고).
      1.65GB 실측 배분은 실기기 계측 항목이라 범위 밖.
- [ ] **검증**: 가상GPS 1시간 주행 → POI 요청 < 60건, 429 = 0 — **마스터 실기기 검증 대기**

> **감사 결과 (2026-08-05).** code-auditor **1차 PASS**. `flutter analyze` 이슈 0 ·
> `flutter test` **373건 전건 통과**(신규 14건). 감사자가 §0의 핵심 결함(스로틀이
> 성공 경로에서만 커밋)이 세 경로 전부에서 실제로 고쳐졌음을, `markStarted` ~
> `inFlight = true` 사이에 `await`가 하나도 없음까지 코드 경로로 추적해 확인했다.
> in-flight 플래그는 전 early-return/예외 경로가 `try…finally` 안에 있어 영구 정지
> 위험 없음.

> **감사 지적 1건 → 즉시 조치 완료** (커밋 `71380de`). 서킷 전이 로그는 상태 전이에만
> 찍혔으나 `_getJson`의 실패 상세 로그(`YNAV_POI fetch failed …`)가 **매 실패 시도마다**
> 나가고 있었다 — 지시서 §2-4 "매 요청마다 로그 금지" 미준수. `_failureLogged`
> 플래그로 연속 실패 구간당 1회로 억제하고 200 성공 시 해제. `_consecutiveFailures`와
> 별도 플래그인 이유는 401 등 **서킷을 트립시키지 않는 실패**도 함께 억제하기 위함.
> S1에서 확인했듯 로그 append 자체가 발열·배터리의 직접 원인이었다.

> **잔여 (감사자 표시: 비차단).** ① 태그별 `http.Client`는 다음 같은 태그 요청이
> 올 때까지 열려 있다 — 최대 4개, 싱글톤 수명 동안 반복 호출되는 태그들이라 실질
> 누수 아님(설계 의도대로). ② `snapBoundsOutward`의 "원본 포함" 보장이 비트 단위로는
> 성립하지 않는다(~1e-13° 경계). 표시 경로가 항상 실제 뷰포트로 재필터링하므로 화면
> 밖 POI가 그려질 수는 없고, 실제 POI 좌표 해상도보다 수십 자릿수 아래라 무해.
> ③ `snapDestination`은 호출부가 없는 죽은 코드 — 그대로 뒀다.

> **⚠️ Git 히스토리 주의.** 이 S2 코드 변경의 일부(`nav_screen.dart`,
> `poi_service.dart` 스냅 보정, 테스트 13종)가 커밋 **`bd57885 "docs: S1 범위 정정 +
> S1b 신설"`**에 들어가 있다. 동시 실행 중이던 다른 세션이 `git add -A`류로 이미
> 스테이징돼 있던 파일을 함께 커밋한 사고다(CLAUDE.md 하드룰 위반). **내용 손실·오염은
> 없음**을 `git diff`로 확인했고, 히스토리 재작성은 위험 조작이라 하지 않았다.
> `git log`로 S2 변경분을 추적할 땐 `49643df` + `bd57885` + `71380de` 세 개를 봐야 한다.

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
- [ ] 지도 정보밀도 OSMAND급 (건물 내부 정보 등)
- [ ] 코스 공유 (QR, 2인 이상 투어 동기화)
- [x] **OSMAND / Organic Maps 벤치마킹 조사** — 완료 2026-08-05,
      [RECON_0805_offline_first_architecture.md](RECON_0805_offline_first_architecture.md)

### O · 오프라인 우선 전환 (마스터 제안 2026-08-05) — **승인 완료, 착수는 S3 뒤**

> 기존 P3 "오프라인 지도 다운로드(도 단위, WiFi 전용)"를 마스터 제안(POI도 온디바이스,
> Rust 검토)까지 포함해 확장한 트랙. 상세·근거·용량 실측:
> [RECON_0805_offline_first_architecture.md](RECON_0805_offline_first_architecture.md)
>
> **실측 규모**: 타일 `korea.mbtiles` **382MB**(z0-14 남한 전역) · POI `poi.db`
> **154MB / 696,255행**(R-tree 인덱스 이미 있음, 식당이 65%) → 전국 통짜 ≈ **536MB**
>
> **핵심 발견**: `maplibre_gl 0.26.1`(현 의존성)에 오프라인 API가 통째로 있다 —
> `downloadOfflineRegion` · `installOfflineMapTiles`(mbtiles 사이드로드) ·
> `setOfflineTileCountLimit` · `setOffline(true)` 등. 앱에서 **현재 0곳 사용**.
> 타일 오프라인은 신규 개발이 아니라 통합 작업이다.
>
> **착수 시점 권고: S3 완료 후.** 오프라인은 출시 차단 항목이 아니다.

**마스터 결정 (2026-08-05, RECON §8)**: ① 착수는 **S3 뒤** ② 지도는 **전국/도 단위
사용자 선택**, POI는 5종 + **관광지 추가** ③ **POI는 묻지 말고 전량 자동 백그라운드
다운로드**, 지도만 선택 ④ 전국 통짜 옵션 **제공** ⑤ Rust **2단계안 동의**(측정 후 판단)

- [ ] **O0 · 관광지 데이터 파이프라인** — ⭐ **오프라인과 독립적으로 값어치 있음.
      O2/O3 안 기다리고 먼저 해도 된다**
  - [ ] OSM 추출 — 서버에 이미 있는 `korea_patched.osm.pbf`(267MB)에서 `osmium`으로
        **4초**. 실측: `boundary=national_park` **24**(실제 23개와 일치) ·
        `tourism=viewpoint` **2,277**(전망대 — 라이더 최고가치) · `attraction` 1,676 ·
        `museum` 1,550 · `historic` 5,309 · `natural=peak` 16,548(이름 있는 것만) →
        **합계 약 2.8만건 / ~5MB**
  - [ ] `data.go.kr` **전국관광지정보표준데이터**([15021141](https://www.data.go.kr/data/15021141/standard.do))로
        한국어 공식 명칭 보강 — 관광지명·구분·위도·경도 포함, CSV, 연 1회 갱신.
        ⚠️ 지자체 지정 관광지라는 법적 정의라 범위가 좁다(전망대·고개 없음)
  - [ ] ⚠️ **TourAPI(26만건)는 신중** — 오픈API 일일 트래픽 제한.
        memory `project_poi_datasource`의 **쿼터 공유 결함 이력**을 반복하지 말 것
  - [ ] ⚠️ **라이선스 분리** — OSM은 ODbL(share-alike). 공공누리인 `poi.db`에 병합해
        배포하면 파생DB로 걸릴 수 있다 → **`tourism.db` 별도 파일로 분리 배포**
  - [ ] `PoiType` 신규 — 관광지/**전망대 분리 권고**(라이더에게 전혀 다른 가치) +
        아이콘·minZoomLevel·`displayPriority` 반영
- [ ] **O1 · 스타일 에셋 로컬화** — 글리프(한글 CJK)·스프라이트가 아직
      `tiles.westinx.com`을 가리킨다. 타일만 받아두면 폰트를 계속 네트워크로 가져감
- [ ] **O2 · 타일 오프라인** — 서버에서 **전국 + 17개 시도 mbtiles 사전 생성** →
      `installOfflineMapTiles` 사이드로드 + 선택 UI + WiFi 백그라운드.
      ⚠️ `setOfflineTileCountLimit` 안 올리면 조용히 끊김.
      ⚠️ 시도 bbox가 서로 겹친다(경기 안에 서울) — 자르는 기준 정할 것
- [ ] **O3 · POI 오프라인** — `poi.db`+`tourism.db` **전량 자동** 다운로드 →
      Dart+`sqflite` 로컬 질의 전환(기존 R-tree 그대로) + 버전 매니페스트
  - [ ] ⚠️ **unmetered(WiFi) 한정 + 저장공간 사전 확인** — 묻지 않고 160MB를 받으므로
        셀룰러로 나가면 요금 사고다. `WorkManager` `NetworkType.UNMETERED`
  - [ ] ⚠️ **다운로드 완료 전까지 서버 폴백 유지** — 설치 직후엔 로컬 DB가 없다.
        **→ S2의 429 방어장치는 계속 필요하다** (오프라인 전환이 S2를 무효화하지 않음)
  - [ ] 설정 화면에 다운로드 상태·데이터 버전·재다운로드 노출(자동이라도 보이긴 해야 함)
- [ ] **O4 · 측정 후 Rust 이관 판단** — 온디바이스 Rust는 `flutter_rust_bridge`
      의존성만 있고 `lib.rs`가 9바이트, jniLibs 0개, 3-ABI 크로스컴파일 미검증.
      POI 질의는 병목이 아니다 (RECON §5-3)
- [ ] **O5 · (별도 트랙) 오프라인 라우팅** — Valhalla 온디바이스. 큰 과제.
      ⚠️ **O0~O4를 다 해도 경로 탐색·재탐색·주소검색은 서버 필요** (RECON §6)

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
