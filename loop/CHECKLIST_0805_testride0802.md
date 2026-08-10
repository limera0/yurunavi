# CHECKLIST — 260802 실주행 피드백 35건 처리 대장

- 작성 2026-08-05 · 분석 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md)
- 원본: [testride_result/260802_testride_result.md](testride_result/260802_testride_result.md)
- **상태 표기**: `[ ]` 미착수 · `[~]` 진행중 · `[x]` 완료 · `[!]` 마스터 확인 대기 · `[-]` 스코프 밖

**진행 요약: 11 / 38 완료** (S0·S1·S2·S3·S4a·S4b·S4c·S5·S6·S7·S8 코드 완료 — 실기기
검증만 마스터 대기. S3의 알림 일원화(§2-5)·PIP 복구 UX(§2-7) 2건은 **2026-08-06 밤 S3b
구현 완료** — 알림 A(geolocator FGS off) 반영, PIP 폐기 + 플로팅 오버레이
(SYSTEM_ALERT_WINDOW) 자체 구현 완료.
**S1b 신설** — 마스터 스크린샷 실측으로 백화가 두 개의 별개 결함이었음이 밝혀졌다(아직 미착수).
**S14 신설** — 일출일몰 바 야간 결함(마스터 추가 제보, 원인 확정, 아직 미착수).
**O0(관광지 데이터 파이프라인) 2026-08-06 저녁 코드 완료** — §O 참고, 38건 카운트와 별도 트랙.
**S5·S6·S7·S8(정차모드·로터리방향·터널추측항법·UI잔여) 2026-08-07 코드 완료** — P1(주행
품질) 트랙 전부 완료. 다음 큐: S10·S11·S13 (S9는 Valhalla 포크 별도 승인 필요, S12는
마스터 스크린샷 대기로 제외))

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

### S1b · 렌더링 자원 고갈 — 껍데기만 그려지고 내용물 소실  `상태: [x]` — **코드 완료(6청크 전부 PASS), 실기기 검증 대기**

> **2026-08-10 정정**: 아래 원본 4단계 계획은 2026-08-05 작성 당시 것이라 낡았다.
> 실제로는 2026-08-06 저녁 **한 세션에서 조사축 전환(§12) + 구현 6청크가 전부 끝났다**.
> 이 절 자체가 최근까지 `[ ]` 그대로였던 건 **문서 갱신 누락**이었다 — 코드는 이미 완료돼
> 있었다(git log로 확인, 체크리스트에 반영 안 됐을 뿐). 지시서
> [HANDOFF_0806_memory_hardening.md](HANDOFF_0806_memory_hardening.md) · 결과
> [MORNING_REPORT_0806_memory_hardening.md](MORNING_REPORT_0806_memory_hardening.md) ·
> 근거 [RECON_0805_render_resource.md](RECON_0805_render_resource.md) §12.
>
> **완료된 6청크** (전부 code-auditor PASS, `flutter analyze` 0 · `flutter test` 383/383):
>
> | 커밋 | 청크 | 내용 |
> |---|---|---|
> | `c761759` | 1 (B-1) | 네이티브 로그 캡처 — logcat 펌프(자기 pid) → 진단로그 `YNAV_NATIVE` |
> | `20618f2` | 2 (A-1/A-3) | `ui.Picture.dispose()` 3곳 + `imageCache` 상한 1000장/100MB→40장/20MB |
> | `cd26bed` | 3 (A-2/A-4) | `MemoryPressureObserver` 신설 — OS 메모리 경고·백그라운드 진입 시 캐시 드롭 |
> | `e3c78f6` | 4 (A-5) | `_locLayerReady`/`_destLayerReady` 리셋 이식(`main_map_screen.dart` 기존 패턴) — 지도 재생성 시 퍽·핀 소실 결함 수정, S8 마커 결함 원인 중 하나이기도 했음 |
> | `cc7a245` | 5 (A-6) | 죽은 의존성 `flutter_map` 제거 |
> | `b906e44` | 6 (B-2) | GPU 메모리 60초 주기 스냅샷 → 진단로그 `YNAV_GPUMEM` |
> | (미커밋, 의도적) | 6 (C-1) | Impeller off 판별용 release APK — `outputs/yurunavi_impeller_off_diag_20260806.apk`. **해결책 아님, 원인 판별 1회용** |
>
> **남은 건 전부 마스터의 실주행 확인 4건뿐** (코드 작업 없음):
> 1. 진단로그에 `YNAV_NATIVE`/`YNAV_MEMPRESSURE`/`YNAV_GPUMEM` 줄이 실제로 남는지
> 2. 백화 재발 여부 — 재발 시 그 순간 로그에 `Could not create valid atlas`류 `YNAV_NATIVE`
>    줄이 있는지 (있으면 §12-4 가설 (b) GPU 자원 할당 실패 확정)
> 3. (선택) `outputs/yurunavi_impeller_off_diag_20260806.apk`로 별도 1회 주행 — 백화
>    안 생기면 Impeller가 원인임이 확정
> 4. 청크4 회귀 확인 — 내비 화면에서 위치 퍽·목적지 핀이 평소처럼 잘 보이는지
>
> **이 절의 원래 4단계 계획**(아래)은 **위 6청크로 대체돼 사실상 소화됐다** — 항목별
> 대응은 각 체크박스 뒤에 표시. 재작업 금지, 참고용으로만 남긴다.

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

- [x] **1단계 · 재현 조건 확보** — **M32(공기계) 인위 재현은 포기, 대체 완료.**
      `am send-trim-memory`는 4회 전부 OS 거부(포그라운드 서비스는 trim 대상 아님).
      가상GPS 17회 왕복 재현 실패 → 마스터 지시로 **정적 감사 + 레퍼런스 앱(OsmAnd/
      Organic Maps) 소스 비교 + Flutter 이슈 트래커 조사**로 축 전환(§12). 실기기
      로그 계측은 청크1(`YNAV_NATIVE`)로 대체 — 다음 실주행에서 자동 수집됨
- [ ] **2단계 · 렌더러 변수 격리** — 판별용 APK만 준비 완료(`outputs/…impeller_off…apk`,
      청크6 C-1), **아직 실주행 안 함**. 위 "남은 확인 4건"의 3번
- [x] **3단계 · 메모리 압박 대응 부재 확인** — **확정**(§12-3 3자 비교표):
      `didHaveMemoryPressure`/`onTrimMemory`/GPU 예산/백그라운드 캐시드롭 전부 0건이었고
      OsmAnd·Organic Maps는 셋 다 구현하고 있었음. → 청크3으로 해소
- [x] **4단계 · 방어 설계** — **완료**. 6청크 전부(위 표) code-auditor PASS
- [x] **S1 수정 후 재측정** — M32 17회 왕복 재현 시도(§10)로 겸함. 구 트리거(PIP
      오검출)는 S3에서 완전 해소 확인, 그 외 렌더 소실은 표본 부족으로 미확정 상태였다가
      정적 감사(§12)로 원인 후보를 좁힘
- [ ] **검증**: 마스터 실주행 1회 — 백화 재발 여부 + 진단로그 3종 태그 확인 (위 "남은
      확인 4건" 1·2번). **다음 세션이 할 일이 아니라 마스터의 실주행 결과 대기.**

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

### S3 · 라이프사이클 정상화  `상태: [x]` — 코드 완료 (S3 기본 + S3b 알림 A·플로팅 오버레이 전환 2026-08-06 밤)

> 근본원인 C. `inactive`가 알림창·캡쳐·엣지패널에서도 발화 → PIP 오진입 → 안내 중단.
> **완료 2026-08-05** · 청크1 `a5beab1` · 청크2 `18da084` · 청크3 `386a2f3`
> 각 청크 code-auditor **PASS**. `flutter analyze` 이슈 0 · `flutter test` **375건 전건 통과**(청크1 신규 1건, 청크3 신규 1건 포함).

- [x] `nav_screen.dart:460` — `AppLifecycleState.inactive` 분기 제거,
      **`onUserLeaveHint`(`nav_pip_hint` 채널, 이미 구현됨) 전용**으로 전환 (청크1, `a5beab1`)
- [x] `hidden` 분기 유지 여부 판단 — **함께 제거** (지시서 §2-2 판단: `onUserLeaveHint`+Auto-PIP 이중 안전망 충분) (청크1)
- [x] `NavForegroundService.kt:68` — `START_NOT_STICKY` → `START_REDELIVER_INTENT` (청크1)
- [x] **wakelock 정리**: 실측 결과 **2중이 옳음**(RECON의 "3중"은 오기 — `NavForegroundService`에
      `PowerManager.WakeLock` 획득 코드 없음). geolocator `enableWakeLock: true` → `false`로
      제거. `WakelockPlus`(화면) + FGS(프로세스)만 유지 (청크2, `18da084`)
- [x] 알림 2개(geolocator FGS + NavForegroundService) 일원화 — **마스터 결정 A 구현 완료 (2026-08-06 밤, S3b 청크1 `2ffd233`)**.
      `map_providers.dart`의 `foregroundNotificationConfig` 삭제 → "주행 안내" 알림 1개만 남음.
      백그라운드 위치 스트림은 `NavForegroundService`(`foregroundServiceType=location`)가 유지.
      **실기기 백그라운드 위치 fix 유실 여부 검증은 마스터 몫**(홈 화면 5분 방치 후 안내 진행 여부).
- [x] PIP/백그라운드 중 지도 API 호출 가드 — `_canCallMap()` 게이트(`mounted && _mlCtrl != null
      && !_isInPip && !_isDisposing`) + `_isDisposing` 플래그(dispose 첫 문장) 도입.
      `nav_screen.dart`의 지도 호출 19+개소 전수 게이트, 신규 test 포함 (청크3, `386a2f3`)
- [x] PIP 복구 UX — **플로팅 오버레이 전환 구현 완료 (2026-08-06 밤, S3b 청크1~3 `2ffd233`+`7e68a72`+`77b2ce8`)**.
      시스템 PIP 전량 폐기(dart `android_pip` 제거, `AndroidManifest`의 `supportsPictureInPicture` 삭제,
      `MainActivity.onUserLeaveHint`·`nav_pip_hint` 채널 삭제, `_buildPipCompactView` 삭제).
      대신 자체 구현 `FloatingOverlayService.kt`(`WindowManager.addView(TYPE_APPLICATION_OVERLAY)`)
      + Dart `NavFloatingOverlay` 서비스 신설. `flutter_overlay_window` 패키지는 `FOREGROUND_SERVICE_SPECIAL_USE`
      권한 요구로 반려. 아이콘 1탭 → `FLAG_ACTIVITY_NEW_TASK|SINGLE_TOP|CLEAR_TOP` intent로 앱 즉시 복귀.
      권한(`SYSTEM_ALERT_WINDOW`)은 이미 매니페스트에 존재. 첫 실행 시 안내 다이얼로그로 사용자에게
      `ACTION_MANAGE_OVERLAY_PERMISSION` 유도. 라이프사이클 회귀 테스트 7건 추가(`nav_lifecycle_test.dart`, +7 → 382/382 통과).
      **실기기 검증(홈→카카오톡→플로팅 아이콘 표시 및 1탭 복귀·30분 방치)은 마스터 몫**.
- [ ] **검증**: 알림창 내림·스크린샷·엣지패널 → PIP 진입 안 함 / 홈 버튼 → PIP 진입 /
      홈 상태 30분 유지 후 안내·히스토리 정상 — **마스터 실기기 수동 검증 대기**

---

## 🟠 P1 — 주행 품질

### S4a · 안내 거리 재조정 (JSON만, 리스크 0)  `상태: [x]` — 완료 2026-08-06

> **완료 2026-08-06** · `flutter test` 28건 전건 통과. 코드 변경 없음.
>
> **imminent_m 비활성화 구현 방식**: 키 자체를 제거하면 `guidance_profile.dart:51`의
> `(json['imminent_m'] as num)` 캐스트가 null을 받아 예외 → catch → fallback 프로파일로
> 조용히 되돌아가는 문제가 있다. 대신 `"imminent_m": 99999`로 설정.
> `filtered.where((p) => p < entryD)` 조건에서 99999는 실내비 거리(최대 수km)에서
> 절대 통과하지 못해 발화 안 됨 — 빈 filtered에서 즉발 폴백도 정상 유지.

- [x] 모든 안내 **50m 앞당김**: 500→550, 300→350, 100→150, 50→100
- [x] **0m(해당 지점) 안내 삭제** — 전역 `imminent_m: 10` → `99999`(실효 비활성화)
- [x] 원형교차로 티어 축소 — 4단계(300/100/30/10) → **2단계 (350/150)** (마스터 결정)
- [x] `turn_left`/`turn_right` `imminent_m: 50` → **70** (마스터 결정)
- [ ] **검증**: 실기기 안내 청취 — 교차로 550m/350m 발화, 0m 추가 발화 없음,
      로터리 350m/150m 2회만 발화 — **마스터 실기기 수동 검증 대기**

### S4b · 안내 중재기 신설  `상태: [x]` — 완료 2026-08-06

> **완료 2026-08-06** · 커밋 `461dc43` · code-auditor **PASS**
> `flutter analyze` 이슈 0 · `flutter test` **395건 전건 통과**(신규 13건)
>
> 우선순위(마스터 결정): 후면단속 > 회전안내 > 구조물 > 급커브
> 최소 발화 간격 4초(마스터 결정). 후면단속은 간격 무시.
> `roundabout_exit` 비활성화 방법: JSON `enabled: false` + `_profileEventKey()` 키 분리
> (코드에서 하드차단보다 JSON 제어가 마스터 결정).

- [x] `GuidanceArbiter` 신설 (`guidance_arbiter.dart`) — 4개 엔진 출력 통합
- [x] 이벤트 **우선순위** 정의 — 후면단속 > 회전안내 > 구조물 > 급커브
- [x] **최소 발화 간격** 4초 — 초과분 폐기(큐잉 없음), 후면단속은 간격 무시
- [x] **상호 억제** — 우선순위 + 4초 gap으로 자연히 처리
      (로터리 안내 후 4초 내 급커브 안내 → 폐기)
- [x] `_profileEventKey()` — `roundabout_enter`/`roundabout_exit` 독립 키로 분리
- [x] **원형교차로 진출 안내 전부 삭제** — `guidance_profile.json`에
      `"roundabout_exit": { "enabled": false }` 추가
- [x] 통과 후 안내 지속 문제 — `VoiceEngine._prevD` 도입, 동일 step에서
      `d > _prevD + 30` 시 `_pendingPoints` 폐기
- [ ] **검증**: 한 교차로당 3회 이하 / 간격 4초 이상 / `roundabout_exit_*` 0건
      — **마스터 실기기 수동 검증 대기**

### S4c · TTS 숫자 한글화  `상태: [x]` — 완료 2026-08-06

> **완료 2026-08-06** · 커밋 `80d6ee0` · code-auditor **PASS**
> `flutter test` **402건 전건 통과**(신규 7건)

- [x] 발화 전 거리 **50m 단위 스냅** — `_distToKorean()`이 `(distM/50).round()*50` 로 처리.
      `_immediatePoint` 경로(예: 43m, 9m)도 모두 오십으로 정규화됨
- [x] `{dist}`를 **한글 수사로 프리렌더** — `_distToKorean()` 신설, 3엔진 전부 교체.
      `300 → 삼백`, `150 → 백오십`, `550 → 오백오십` 등
- [x] `1000m → "일 킬로"` → 템플릿 `{dist}미터 앞`과 조합해 **"일 킬로미터 앞"** 출력
- [ ] **검증**: 실기기 발화 청취 — 거리가 모두 한글 수사로 읽힘, 이상 발음 없음
      — **마스터 실기기 수동 검증 대기**

### S5 · 정차 모드 + 전력  `상태: [x]` — 코드 완료 2026-08-07, 실기기 검증만 남음

> `YNAV_REROUTE` 분당 최대 151건. `distanceFilter: 0` + 정지 GPS 지터가 원인.

> **완료 2026-08-07** · 커밋 `fd667f1` · 지시서 [HANDOFF_0807_S5_stationary_mode.md](HANDOFF_0807_S5_stationary_mode.md)
> code-auditor **1차 PASS**(수정 없이). `flutter analyze` 이슈 0 · `flutter test` **419건 전건 통과**(신규 17건).
> 착수 전 마스터 확인(2026-08-07): 이번 세션 S5만 진행(모듈당 1세션 하드룰). 정차 판정
> 임계값 **5km/h 미만 · 10초 지속**(마스터 결정). S9는 Valhalla 포크 별도 승인 필요해
> 이번 스코프 전체 제외, S12는 마스터 스크린샷 대기로 보류.

- [x] **정차 모드** 신설 — `StationaryDetector`(순수 클래스, 주입 가능 clock, 신규
      `lib/features/navigation/providers/stationary_detector.dart`). 속도 **5km/h 미만이
      10초 지속** 시 진입, 속도 회복(≥5km/h) **즉시** 해제(지연 없음 — safety-first).
      진입 시 재탐색 디바운스 타이머 등록(`_triggerReroute()`)·카메라추종(`_recenter`)·
      앰비언트 POI 페치(`_maybeFetchAmbientPois`) 정지. `_ensureLocationMarker`(파란 점)는
      계속 갱신
- [x] `map_providers.dart` `distanceFilter: 0` → 정차 시 `15`로 가변 (`stationaryModeProvider`를
      `locationStreamProvider`가 watch, 전이 시 Geolocator 스트림 재구독)
- [x] `accuracy: bestForNavigation` → 정차 시 `LocationAccuracy.high`로 다운시프트.
      **참고(감사 확인)**: geolocator_android 문서상 `high`와 `bestForNavigation`은 Android에서
      동일한 `PRIORITY_HIGH_ACCURACY`로 매핑됨 — 실측 배터리 절감은 주로 `distanceFilter` 쪽에서
      나올 가능성이 큼(결함 아님, 실기기 검증 시 참고)
- [x] `map_providers.dart:72` `ref.keepAlive()` — **재검토 결론: 유지**(제거 시 S0 "내 위치
      상시 표시" 회귀 위험). 다운시프트(위 항목)로 홈/설정 화면 배터리 절감은 같은 공유
      스트림을 통해 확보
- [x] 재탐색 origin 오프셋 **40m → 50m** (`nav_screen.dart:846`(`_reroute`), `:1702`(`_openCourseSheet`)
      — 체크리스트 원문의 842/1643은 이후 커밋으로 밀린 낡은 값, 두 곳 모두 확인 후 반영)
- [-] (선택) Thermal Governor — 옵션 항목, 이번 세션 스코프 밖(백로그 유지)

> **스코프 판단 1건 — `_addGasStationWaypoint`의 재탐색은 게이트 제외.** HANDOFF는 이
> 호출부도 "동일 가드"를 적용하되 판단은 코더에게 맡겼다. 코드 확인 결과 이건 사용자가
> 주유소 카드를 **명시적으로 탭**해야만 발화하는 1회성 트리거이며, `YNAV_REROUTE` 151건/분의
> 원인인 GPS 지터 자동 재탐색(`_triggerReroute()`)과는 다른 경로다. 게이트를 걸면 정차 중
> 사용자가 요청한 경유지 추가·재탐색이 조용히 무시되는 역효과만 생긴다 — 게이트 없이 유지가
> 맞다고 판단(code-auditor 확인 완료, 사용자 탭에서만 호출됨을 콜사이트 추적으로 검증).

> **스트림 재구독 리스크 — 감사로 실증 확인.** `stationaryModeProvider` 전이 시
> `locationStreamProvider`가 재구독되며 기존 Geolocator 스트림 구독이 끊긴다. geolocator의
> 플랫폼 구현이 스트림을 필드에 캐시해 두고 `onCancel`에서만 비우는 구조라, disposal이
> rebuild보다 먼저 실행되지 않으면 새 설정이 적용 안 된 낡은 스트림이 재사용될 위험이 있었다.
> Riverpod 소스(`ProviderElement._performRebuild()`)로 dispose-먼저 순서를 확인했고,
> `location_stream_stationary_test.dart`가 실제 플랫폼 채널을 모킹해 정차↔주행 전이 시
> `distanceFilter`/`accuracy` 값이 매번 새로 전달됨을 직접 검증(감사자가 트리비얼하지 않음을
> 확인).

- [ ] **검증**: 정차 10분간 `YNAV_REROUTE` 0건 / 배터리 소모 측정 / 정차→재출발 시 안내
      정상 재개 — **마스터 실기기 수동 검증 대기**

### S6 · 로터리 안내 재설계  `상태: [x]` — 완료 2026-08-07

> **완료 2026-08-07** · 커밋 `be54f5b` · 지시서 [HANDOFF_0807_S6_roundabout_direction.md](HANDOFF_0807_S6_roundabout_direction.md)
> code-auditor **1차 PASS**(수정 없이). `flutter analyze` 이슈 0 · `flutter test` **456건 전건 통과**.
> 착수 전 로컬 Valhalla(`localhost:8002`) 검단회전교차로 5개 조합 직접 프로브로 알고리즘
> 실현 가능성 확인 완료(6번째 S→N은 로터리를 안 거치는 경로가 나와 제외). 체크리스트 원문의
> "{exit} 템플릿 4종"은 재확인 결과 실제 도달 가능한 건 2종뿐이었음(`roundabout_exit` 계열은
> S4b로 이미 비활성화돼 도달 불가).

> **2026-08-05 자체 Valhalla 서버 직접 프로브로 재현 완료.**
> 검단회전교차로 **6개 진입/진출 조합 전부 `roundabout_exit_count=2`**.
> 프로브 4지점이 서로 다른 way에 스냅됨을 `/locate`로 확인(같은 진입로에서 세 방향으로
> 나가는데 셋 다 "2번째 출구" → 최소 2개는 명백히 오답).
> **공개 업스트림 Valhalla(FOSSGIS)도 동일** → **우리 포크 결함 아님. 앱 파싱 버그도 아님.**
> → **`roundabout_exit_count`를 신뢰하면 안 된다.**

- [x] **출구 번호 발화 폐기** — `voice_engine.dart`의 `{exit}` 주입 경로 2곳 제거
      (`roundabout_enter` 블록의 exit-count 주입 + 이미 S4b로 비활성화돼 있던
      `roundabout_exit && isImminent` 죽은 코드 블록 통째 삭제)
- [x] **진입/진출 방위차로 방향 직접 계산** (좌/직/우) — `PoiService.signedBearingDiff`
      신설(부호 있는 -180~180) + `RoutingService.classifyRoundaboutDirection`
      (기존 `CurveDirection`과 동일 부호 관례, `RoundaboutDirection{left,straight,right}`
      + `labelKo`). 진입(type26)-진출(type27) 페어링 실패 시 안전 폴백(방향 없는
      일반 문구)으로 빠짐
- [x] `default_ko.json` `{exit}` 사용 템플릿 **2종**(실제 도달 가능한 것만, 원문 "4종"은
      정정됨) 교체 → "회전교차로에서 {direction} 방향입니다" 형태
- [x] 근거: memory `feedback_accurate_maneuver_wording` — **틀린 출구 번호를 말하느니
      안 말하는 게 낫다.** 라이더에게 필요한 건 번호가 아니라 방향
- [ ] (우선순위 하향, 이번 세션 제외) "원형교차로인데 우회전이라고 안내함" — Valhalla가
      type 26 대신 9/10을 내는 별개 증상(`mini_roundabout` 가설)
- [ ] **검증**: 검단 5개 조합(실측 bearing 표는 지시서·테스트 fixture에 기록)의 좌/직/우
      판정이 **실제 도로 형상과 일치하는지** — 위성지도 육안 대조 또는 실기기 필요,
      헤드리스 서버라 이 세션에서 완결 불가. **마스터 확인 대기**

> **감사 부수 발견(스코프 밖, 조치 없음)**. `nav_screen.dart`의 화면 카드 텍스트
> (`_svgAssetForType`/`_maneuverText`, type 26)는 여전히 `roundaboutExitCount`를
> "회전교차로 N번째 출구"로 화면에 표시한다 — 이번 S6는 지시서상 **TTS(발화)만** 스코프였다.
> 신뢰 불가로 확정된 값을 화면에는 여전히 보여준다는 뜻이라 후속 조치 검토 필요.

### S7 · 터널 추측항법  `상태: [x]` — 완료 2026-08-07

> **완료 2026-08-07** · 커밋 `d7f88f3` · 지시서 [HANDOFF_0807_S7_tunnel_dead_reckoning.md](HANDOFF_0807_S7_tunnel_dead_reckoning.md)
> code-auditor **1차 PASS**(수정 없이). `flutter analyze` 이슈 0 · `flutter test` **456건 전건 통과**.
> `route_progress_provider.dart`(경로 shape·구조물 zone·진행거리를 다 아는 provider)에
> 배치(NavStateNotifier는 경로를 모르는 순수 GPS 계층이라 관심사 분리 유지).

- [x] 터널 zone(`StructureType.tunnel`) 진입 + GPS 상실 동시 감지 — `NavigationState.stale`
      필드 신설(기존 `_kStaleMs=8000` 재사용) + `_tunnelZoneContaining(_snapIdx)`가
      tunnel 타입 zone 범위 안일 때만 진입(다른 구조물 타입·무조건 stale은 진입 안 함)
- [x] 직전 1분 평균속도 **× 1.05**로 경로 shape 따라 위치 시간적분 전진 (마스터 제안) —
      60초 롤링 속도버퍼(실측 fix만 반영, 추정 tick 자기오염 없음) + 500ms 타이머로
      `_traveledM` 전진, 신규 `_pointAtCumulativeM`(누적거리→좌표 역변환)로 위치 산출
- [x] 터널 출구 도달 또는 GPS 복귀 시 스냅 복원 — 도달 시 그 지점에서 정지(더 추정 안 함),
      실측 fix 복귀 시 정상 `_advance()`로 복귀. **알려진 리스크(×1.05 낙관 편향으로 실측
      fix가 추정보다 뒤처질 수 있음)** 대응: 추측항법 직후 첫 실측 fix에 한해 스냅 탐색창을
      뒤로도 1회 확장(`_pendingBackwardSnap`), 그 다음 fix부터 정상 전진전용 복귀 —
      감사에서 "한 번만 작동하고 정상 복귀"까지 직접 확인됨
- [x] 추측항법 중 재탐색 금지 가드 — `nav_screen.dart` `_triggerReroute()`에 S5의
      `isStationaryProvider` 게이트 옆 `deadReckoning` 게이트 추가(정확히 그 한 줄만 추가,
      감사로 확인)
- [ ] **검증**: 가상GPS로 터널 구간 GPS 드롭 시나리오 재생 — memory `project_vgps_testing`
      하네스 필요, **마스터 실기기/가상GPS 검증 대기**

### S8 · UI 잔여  `상태: [x]` — 완료 2026-08-07

> **완료 2026-08-07** · 커밋 `fc638f2` · 지시서 [HANDOFF_0807_S8_ui_remainder.md](HANDOFF_0807_S8_ui_remainder.md)
> code-auditor **1차 FAIL → 정밀 수정 1건 → 커밋**(재감사 없이 반영 — 감사 지적 그대로
> 한 줄 수정). `flutter analyze` 이슈 0 · `flutter test` **629건 전건 통과**.
> **마스터 확인(2026-08-07) — 시스템바 항목 원문 정정**: "홈은 투명"이 아니라 "2026-07-30
> 라운드2가 결정한 `#F5F1EC` 통일이 일부 화면에서 반영 안 됨"이 실제 지적이었다(체크리스트
> 원문은 오전사). 원인은 이 세션에서 특정: `app_theme.dart`의 `AppBarTheme`에
> `systemOverlayStyle` 미설정 → `AppBar`를 쓰는 5개 화면(히스토리·설정·프로필·즐겨찾기
> 카테고리·약관)이 라운드2가 건 전역 색을 자체적으로 덮어씀.

- [x] **시스템바 색상 통일** — `app_theme.dart`의 `AppBarTheme`에 `systemOverlayStyle:
      kSystemBarColor` 조합 추가(AppBar 5개 화면이 라운드2 통일을 덮어쓰던 근본원인 수정).
      `main.dart`/`nav_screen.dart`의 기존 설정은 이미 정확해 변경 없음
- [x] **주유소 경유지 마커 미표시** — `_initDestLayer()`가 `widget.waypoints` 대신
      `_liveWaypoints`를 순회하도록 수정 + `_addGasStationWaypoint()`에서 삽입 직후
      즉시 `addSymbol` 호출. **감사에서 동시성 결함 발견·수정**: `_liveWaypoints`를
      직접 순회하며 매 반복 `await`하는데 그 사이 `_addGasStationWaypoint()`가 같은
      리스트를 변경하면(예: 플로팅 오버레이 복귀로 `_onStyleLoaded` 재실행 중)
      `ConcurrentModificationError` 위험 — `List<LatLng>.of(...)` 스냅샷 순회로 수정
- [x] 하단 카드 — 전체 거리 → **남은 거리**(`progressSub`의 `distToDestM` 실시간 반영)
- [x] 하단 카드 — 현위치(시/군/구, `GeocodingService.reverseGeocodeCoarse` 신설,
      기기 내장 geocoder + 300m/60s 스로틀)를 목적지와 **3초 간격 교대 표시**
- [x] **상단 카드 — 남은 거리 10.0km 이상 줄바꿈 해결.** 마스터 1순위(flexible 확장)로
      해결 — `nav_top_card.dart`로 위젯 분리, `ConstrainedBox(minWidth 62%) +
      IntrinsicWidth + Flexible`(내부 `Expanded`는 `IntrinsicWidth` 안에서 동작 안 해
      `Flexible`로 교체). 5개 화면폭 × 8개 거리문자열 × 4개 도로명 길이 조합 위젯
      테스트로 overflow 0건 확인
- [ ] **검증(실기기)**: 5개 AppBar 화면 육안 확인 / 실제 남은거리 감소 확인 / 3초 교대
      표시 육안 확인 / 88.8km급 목적지 줄바꿈 없음 / 주유소 추가 시 마커 즉시 표시 —
      **마스터 실기기 수동 검증 대기**

> **감사 부수 발견(스코프 밖, 조치 없음)**. S6 감사에서도 나온 얘기와 별개로,
> `nav_screen.dart`의 화면 카드(`_maneuverText`)는 여전히 신뢰 불가로 확정된
> `roundaboutExitCount`를 그대로 표시한다 — S6/S8 어느 쪽 스코프도 아니었다.

### S14 · 일출일몰 바 야간 모드 결함  `상태: [ ]` — **원인 확정, 조사 불필요**

> **신설 2026-08-05** (마스터 추가 제보 — 최초 35건 목록에서 누락됐던 건).
> 증상 두 가지: ① **밤에 게이지 핸들이 시간에 따라 제대로 안 움직인다**
> ② 야간임이 시각적으로 구분되지 않는다(배경/그래프 색 반전 요구).

#### ①-a 원인 확정 — `daylight_service.dart:170` `nextBmnt` 계산 오류

`DaylightService.cycleState()` 밤 분기가 **자정~일출 구간에서 끝점을 하루 뒤로 잡는다.**

```dart
final eent = now.isBefore(today.bmnt)
    ? today.eent.subtract(const Duration(hours: 24))   // ✔ 어제 일몰 — 맞다
    : today.eent;
final nextBmnt = today.bmnt.add(const Duration(hours: 24)); // ✘ 항상 +24h
```

`now`가 **오늘 일출 이전**(자정~새벽)이면 그 밤은 *어제 일몰 → **오늘** 일출*로 끝나는데,
`nextBmnt`가 조건 없이 `+24h`라 **내일 일출**을 끝점으로 잡는다. 분모가 10시간이어야 할
자리에 34시간이 들어간다.

**마스터 스크린샷(05:21, 일몰 19:35, 일출 05:39)으로 산수 검증 — 정확히 일치한다:**

| | 현재 코드 | 올바른 값 |
|---|---|---|
| 구간 시작(eent) | 어제 19:35 ✔ | 어제 19:35 |
| 구간 끝(nextBmnt) | **내일 05:39 ✘** | 오늘 05:39 |
| total | **2,044분(34h04)** | 604분(10h04) |
| elapsed | 586분(9h46) | 586분 |
| **progress** | **0.287** | **0.970** |

→ 일출 18분 전인데 핸들이 **상단 29%**에 있다. 스크린샷 실측 핸들 위치(≈30%)와 일치.
**가설 아님. 확정.**

#### ①-b 파생 증상 — 자정에 핸들이 위로 되돌아간다

같은 버그의 두 번째 얼굴이다. **일몰~자정 구간은 계산이 맞고**(분모 604분),
자정을 넘는 순간 분기가 바뀌며 분모가 2,044분으로 튄다:

| 시각 | progress |
|---|---|
| 23:59 | 43.7% |
| 00:01 | **13.0%** ← 갑자기 위로 점프 |

이후 새벽 내내 **정상 속도의 약 1/3.4로 기어간다** — 마스터가 "움직이지 않는다"고
느낀 실체가 이것이다(아주 안 움직이는 게 아니라 3배 느리게 움직인다).

- [ ] `daylight_service.dart:168-170` — `now.isBefore(today.bmnt)`일 때
      **끝점을 `today.bmnt`로** 잡도록 수정 (시작점 분기는 이미 옳다)
- [ ] (권고) `±24h` 근사 대신 `calculate(date: 전일/익일)`로 **실제 전일 일몰·익일 일출**을
      쓰면 정확도가 오른다. 로컬 계산이라 비용 거의 없음
- [ ] **테스트가 0건이다** — `test/`에 `DaylightService` 테스트가 하나도 없어서 이 결함이
      살아남았다. 최소 4케이스: 낮 중간 / 일몰 직후 / **자정 직전·직후 연속성** /
      **일출 직전(이번 케이스)**

#### ② 야간 색상 반전 (마스터 요구)

현재 야간에도 **흰 알약 배경에 짙은 남색 바**다(스크린샷 그대로). 낮과 거의 같아 보인다.
원인: `daylight_bar.dart:55` `containerBg`가 야간에 `cs.surface`인데 **라이트 테마의
`surface`는 흰색**이라, 사실상 낮과 동일한 배경이 나온다.

- [ ] **배경/그래프 반전** — 야간: 배경 **짙은 남색**(현 바 색 `0xFF1A237E` 계열),
      바 **밝은 색**(`0xFFFFF9C4` 계열/흰색). 낮은 현행 유지(흰 배경 + 연노랑 바)
- [ ] ⚠️ **라벨·아이콘 색도 함께 반전해야 한다** — 배경만 어둡게 하면
      `sunriseColor`(`cs.onSurfaceVariant`)·`sunsetColor`(`cs.tertiary`) 라벨이 묻는다.
      대비비(WCAG AA 4.5:1) 확인할 것
- [ ] ⚠️ `containerBg`를 `cs.surface`에 의존하지 말 것 — 테마 밝기와 무관하게
      **주야 상태로만** 결정돼야 한다(현 버그의 원인)
- [ ] 로드맵 11번(하드코딩 스타일 → 토큰) 고려 — `daylight_bar.dart`의
      `0xFF1A237E`/`0xFFFFF59D`/`0xFFFFF9C4`/`0xFFFFB300`을 `AppColors` 토큰으로
      (현재 `AppColors.sunrise`/`sunset`만 존재)
- [ ] **검증**: 낮/일몰직후/자정전후/일출직전 4시점 골든 또는 위젯 테스트 +
      실기기 야간 육안 확인

> **참고**: S1에서 이 위젯의 `clamp` 크래시를 고치며 렌더 경로는 이미 정리됐다.
> 이번 건은 **계산부(`daylight_service.dart`)와 색상 결정 로직**이라 S1과 겹치지 않는다.

---

## 🟡 P2 — 데이터·라우팅

### S9 · 자동차전용도로 하드 배제  `상태: [x]` (2026-08-10, 커밋 `6f4858f` + Valhalla 포크 `de28c1ae7`)

> **오토바이 법적 절대 원칙** (memory: `project_motorcycle_legal_constraints`). 완료.
>
> 지시서: [HANDOFF_0810_S9_motorroad_hard_exclusion.md](HANDOFF_0810_S9_motorroad_hard_exclusion.md).
> **지시서 §2가 제안한 exclude_polygons/그래프 오버레이 파이프라인은 최종적으로 쓰지
> 않았다** — 착수 중 소스를 직접 추적해 더 작은 근본 수정을 발견함(아래 참고).

- [x] **트랙 A(motorway/trunk)**: `motorcyclecost.cc` `Allowed()`/`AllowedReverse()`에
      `RoadClass::kMotorway`/`kTrunk` 직접 체크 추가 — JSON costing과 무관하게 항상
      하드 배제. 기존 3코스 회귀 확인(용인남부→팔당댐 67.4/57.9/51.7km, 패치 전과
      일치).
- [x] **트랙 B(motorroad=yes)**: 나무위키 목록이 197건(1,984.5km)으로 지시서의
      "100건+" 게이트에 걸려 exclude_polygons 검토 → Valhalla
      `max_exclude_polygons_length`(10km 제한)에 바로 막힘을 확인 → 그래프 오버레이
      파이프라인(옵션 C) 착수 결정 → **착수 중 소스 추적으로 전제 자체가 틀렸음을
      발견**: `motorroad=yes`는 그래프 스키마 변경이 필요한 게 아니라, `admins.sqlite`가
      애초에 생성된 적이 없어(설정은 있었으나 파일 부재) 국가별 access override
      테이블이 통째로 죽어있던 게 근본 원인. `admins.sqlite` 생성 +
      `adminconstants.h`에 South Korea 항목 추가(모터사이클 접근권 제외, 비트마스크
      233 SQL로 직접 검증)로 해결. 부수효과로 일본 타일 우측통행 오류도 같이 고쳐짐.
- [x] **검증**: 격리 컨테이너 회귀 통과, 프로덕션 스왑 후 동일 OD 재확인 일치.
      나무위키 197건 좌표 기반 대량 회귀 curl은 **미실행**(아래 알려진 제약 참고).
- ⚠️ **알려진 제약**: 초장거리 단일 요청(서울↔부산 등 500km+ 직선)은 motorway/trunk
      셧컷 제거로 Valhalla 탐색이 실패할 수 있음(실제 무경로 아님 — 경유점 분할 시
      정상 산출 확인, 585km). `max_distance` 500km→800km로 완화했으나 근본 해결은
      아님. 품질 판단은 실주행에서(마스터 결정).
- ⚠️ motorroad=yes 배제는 SQL 레벨(정확한 access 비트마스크가 테이블에 반영됨)로
      검증했고, 실제 도로 좌표 기반 end-to-end 예시는 확보하지 못함(Overpass API가
      이 환경에서 접속 불가) — 나무위키 197건 목록 기반 curl 회귀는 후속 과제.

### S10 · 회전 안내 등급 기반 억제  `상태: [x]` (커밋 35d29e1)

- [x] Valhalla 응답에 `road_class` 포함 여부 **계약 확인** (curl) — `/route`
      maneuvers엔 없음, `/trace_attributes`의 `edge.road_class`로 확인
      (기존 trace_attributes 호출에 속성 1개만 추가, 신규 HTTP 호출 없음)
- [x] `ManeuverStep`에 필드 직접 추가 **대신** 진입/진출 도로 등급을
      `route_progress_provider`의 별도 맵(`exitStructureByManeuverIdx`와
      동일 패턴)으로 계산·캐싱 — trace_attributes 비동기 도착 타이밍 문제로
      불변 클래스에 필드 추가보다 기존 패턴 재사용이 적합하다고 판단
      (HANDOFF 참조)
- [x] **등급 유지·상승 회전은 안내 억제, 하락할 때만 안내** — 마스터 확인:
      모든 회전 방향(좌/우/직진 갈림) 적용. turn_left/turn_right/
      sharp_turn_*/keep*에만 적용, ramp/exit/roundabout/uturn/merge/
      destination/continue는 등급 무관 항상 정상 안내. road_class 판정
      불가 시 fail-open(정상 안내)
- [x] memory `feedback_accurate_maneuver_wording` 준수 — 갈림길 차선유지
      (keep/keep_left/keep_right = Valhalla type 22/23/24)가 억제 대상
      이벤트군에 정확히 포함됨
- [ ] **음성만 억제, 화면 상단 턴 카드는 미반영** — 의도적 스코프 제한
      (HANDOFF "알려진 리스크" 참조). 카드까지 반영하려면 별도 작업 필요
- [ ] **실기기 검증 대기** — 국도→지방도 갈림길(안내 나와야 함) vs 지방도
      내 등급 유지 갈림길(안내 없어야 함) 실주행 확인

### S11 · 고급휘발유 미표시  `상태: [ ]`

- [ ] **S2 완료 후 재현되는지 먼저 확인** — 429 폭주 + 실패 캐싱(§S2)이 원인이면
      이미 해결됐을 수 있음
- [ ] 재현 시: `gas_station_service.dart:14` `premiumPrice` 서버 응답 실측
- [ ] `nav_screen.dart:2685` B034 표시 경로 점검
- [ ] 참고: `MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md` (기존 수정 이력)

### S12 · 도로 색상  `상태: [x]` (커밋 45580bd)

- [x] `assets/images/osm_liberty_yurunavi.json` — trunk+primary(국도)=#F8D49A,
      secondary(지방도)=#FDF0B4, tertiary+minor/service/track(나머지)=#FFFFFF.
      본선+케이싱+터널+교량+ramp(highway-link) 전부 적용. 고속도로(motorway)
      기존 색상·굵기 미변경. 색상값은 `loop/testride_result/road_color.jpg`
      픽셀 샘플링 + 로컬 tileserver-gl 렌더 미리보기로 검증.
- [ ] OSMAND·네이버지도 대조 — **실기기·육안 확인은 마스터 몫으로 남김**

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

### P3 실행 계획 — 우선순위·스코프 확정 (마스터 결정 2026-08-10)

> **착수 시점**: P0~P2 잔여 4건(S1b·S11·S13·S14) 완료 후 — S9 완료(2026-08-10). 그
> 전까지는 계획만 확정.
> **스코프**: 위 8개 항목 중 4개 트랙 선정(검색 3종은 한 세션으로 묶음) — 오프라인(O)
> 트랙은 이미 별도 계획됨(아래 §O), 코스 공유는 정적 공유로 범위 축소.

우선순위 순서와 근거:

1. **S15 · 이어서 안내하기 + 투어 히스토리 병합** — 마스터가 명시 요청한 기능이자
   S1b(렌더링 자원고갈)·S3(라이프사이클) 등 기존 안정성 작업의 UX적 짝(중단 시나리오
   대응). 스코프가 가장 크고(자동 재개 트리거) 기술 리스크도 가장 커서 먼저 확보해
   여유 있게 반복하는 편이 낫다고 판단
2. **S16 · 검색 UX 3종** — 최근검색 리스트 + 통합검색(주소+상호) + 점포명 거리순 정렬,
   한 세션으로 진행. 매일 접점(홈 진입 시 검색바)이라 체감 가치가 크고 독립적·저위험
3. **S17 · 코스 공유 (QR, 정적)** — 완성 경로를 QR/링크로 내보내기만, 실시간 동기화는
   제외(마스터 확정). 자체완결적, 서버 인프라 불필요
4. **S18 · 경로 색상·화살표 (지도 스타일)** — 네이버급 초록 경로 + 진행방향 화살표.
   S12(도로 색상)와 동일 패턴, 스타일 JSON/렌더러 레벨 소품이라 낮은 리스크지만
   가치도 상대적으로 작아 후순위
5. **S19 · 지도 정보밀도 (OSMAND급) — RECON 선행** — 건물 내부 정보 등 요구 수준의
   데이터가 한국 OSM에 실제로 존재하는지 불확실(`indoor=*` 태그 커버리지 미조사).
   구현 세션 전에 데이터 가용성부터 확인하고 스코프를 재확정할 것

#### S15 상세 — 이어서 안내하기 + 투어 히스토리 병합  `상태: [ ]`

- [ ] **재개 트리거: 앱 (재)시작 시 자동 제안** (마스터 확정, 수동재개 아님) — 알림/팝업으로
      "이어서 안내할까요?" 제시
- [ ] ⚠️ **오탐 방지 임계치 미확정** — 고아 트랙이 오래됐으면(예: 1시간+) 제안하지 않는
      기준 필요 — **구현 착수 전 마스터 확인**
- [ ] ⚠️ **재개 방식 미확정: 원경로 유지 vs 재탐색** — 제안(가안): 현재위치 → 원래
      목적지로 **재탐색**(원본 경로 geometry를 그대로 잇지 않음). 이유: 중단 중 위치
      이동 가능성, 기존 `routing_service` 재사용으로 단순화(memory
      `feedback_prefer_simple_reuse` 방침) — **구현 착수 전 마스터 확인**
- [ ] `TourRecoveryService`(`tour_recovery_service.dart:12-21`) 확장 — 현재 고아 트랙 →
      히스토리 복구만 함, 재개 판정 로직 추가 필요
- [ ] 히스토리 **병합** — 중단 전/재개 후 두 구간을 히스토리 목록에 하나의 투어로 표시
- [ ] S1b(렌더링 자원고갈) 재현 시나리오를 재개 QA에도 그대로 활용 (동일 중단 상황)

#### S16 상세 — 검색 UX 3종  `상태: [ ]`

- [ ] 검색바 탭 → 최근 검색지/목적지 리스트 표시
- [ ] 통합 검색 — 주소(V-World 프록시) + 상호(POI) 한 입력창에서 병합 노출
- [ ] 점포명 검색 결과, 지도 위치(현재 뷰포트 중심 또는 GPS) 기준 가까운 순 정렬

#### S17 상세 — 코스 공유 (QR, 정적)  `상태: [ ]`

- [ ] 스코프: **정적 공유만** — 완성 경로 QR/딥링크 내보내기, 상대 앱에서 불러오기.
      실시간 위치 동기화(그룹 라이드 트래킹)는 **제외**(마스터 확정, 서버 인프라 필요해
      스코프 밖)
- [ ] 경로 직렬화 포맷 설계 (waypoints → 딥링크 URL 인코딩)
- [ ] QR 생성 — 기존 의존성 확인 후 신규 패키지 여부 결정
- [ ] 앱 딥링크 수신 핸들러 (공유받은 경로 로드)

#### S18 상세 — 경로 색상·화살표  `상태: [ ]`

- [ ] 경로 색상 — 네이버급 초록 톤 확정 (브랜드 스킨 A/B/C와 충돌 없는지 확인,
      memory `project_brand_identity` 참고)
- [ ] 진행방향 화살표 — MapLibre 심볼 레이어 `symbol-placement: line` 검토

#### S19 상세 — 지도 정보밀도 (RECON 선행)  `상태: [ ]`

- [ ] **RECON 먼저**: 한국 OSM `indoor=*`/건물 내부 태그 커버리지 실측 — 사실상 데이터
      없으면 "건물 내부 정보"는 스코프 제외 권고, POI/라벨 밀도 상향으로 재정의
- [ ] RECON 결과로 마스터 재확인 후 구현 스코프 확정

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

- [x] **O0 · 관광지 데이터 파이프라인** — 코드 완료 (2026-08-06 저녁)
  > 작업지시서: [HANDOFF_0806_O0_tourism_data.md](HANDOFF_0806_O0_tourism_data.md).
  > 착수 전 4문항(범위/PoiType 분리/data.go.kr 키/TourAPI) 마스터 확인 완료 후 진행.
  > 커밋 `694e9a2`(데이터 파이프라인) + `44b932b`(PoiType 신규 + 크래시 위험 격리).
  > code-auditor **PASS**(2026-08-06) — `cargo test` 170건, `flutter test` 382건 전건 통과.
  > **실행 결과**: `tourist_spot` 28,067 · `viewpoint` 2,330 (RECON §9-1 실측치와 자릿수 일치,
  > OSM 29,582 + data.go.kr 병합 201 + data.go.kr 단독 614). `/data/poi/tourism.db`(7MB)로
  > `poi.db`와 물리적 분리 확인.
  > **감사 중 스코프 밖 크래시 위험 발견·즉시 수정**: `poiIcons`/`poiIconBgColors`에 신규
  > 2종 엔트리가 없어 스타일 로드 시 `poiIcons[type]!`이 즉시 throw하는 문제를
  > flutter-coder가 발견·보고 후 STOP → 오케스트레이터가 아이콘 추가 + 나머지 5개 호출부
  > `PoiService.serverSupportedTypes` 격리로 직접 해소.
  > **다음 단계(스코프 밖, 후속 청크)**: 서버 `/poi/nearby`에 `tourism.db` 연동(§2-4) +
  > 지도 화면 실제 표시 배선 — 이게 끝나야 사용자가 실제로 관광지/전망대를 본다.
  - [x] OSM 추출 — `korea_patched.osm.pbf`(267MB)에서 `osmium`. 실측:
        `national_park` 25 · `viewpoint` 2,330 · `attraction` 1,938 · `museum` 2,274 ·
        `historic` 6,755 · `nature_reserve` 54 · 이름있는 `peak` 16,382 → **합계 약 3만건**
        (RECON 예상보다 다소 많음 — 자릿수는 일치, `peak`가 예상과 달리 대부분 이름 있었음)
  - [x] `data.go.kr` **전국관광지정보표준데이터**(15021141) 보강 — 표준데이터 그리드
        다운로드 API(로그인/키 불필요, `columList.json`+`standard.json` 페이지네이션,
        총 852건) 실측으로 확인, 좌표 근접 매칭(80m)으로 OSM과 병합
  - [x] **TourAPI 제외** — 마스터 확인, 이번 범위에서 완전히 배제
  - [x] **라이선스 분리** — `tourism.db` 별도 파일로 실제 분리 배포, `poi.db` 무변경 확인
  - [x] `PoiType` 신규 — `touristSpot`/`viewpoint` 2종 분리, 아이콘·minZoomLevel·
        `displayPriority` 전부 반영
- [x] **O1 · 스타일 에셋 로컬화** — 글리프(한글 CJK)·스프라이트가 서버(`tiles.westinx.com`)
      대신 기기 내장 폰트로 로컬 렌더링되도록 전환 완료(2026-08-06, 3청크 전부
      code-auditor PASS·커밋됨).
  - [x] 청크1 · iOS `Info.plist`에 `MLNIdeographicFontFamilyName`=`Apple SD Gothic Neo`
        추가(`6281b41`)
  - [x] 청크2 · `maplibre_gl` 플러그인 포크(`github.com/limera0/flutter-maplibre-gl-yurunavi-fork`,
        브랜치 `yurunavi-fork`) — Android 네이티브·Dart에 `localIdeographFontFamily` 옵션
        노출, `pubspec.yaml` git 의존성 전환, `flutter build apk --debug` 성공 확인(`cb63868`)
  - [x] 청크3 · 설정 화면 "지도 한글 폰트 선택" UI — **Android 전용으로 범위 축소**
        (`ea9631f`). 착수 중 `MLNRendererConfiguration.localFontFamilyName`이 **readonly**임을
        실제 maplibre-native 소스로 확인 — iOS는 런타임에 폰트를 바꿔도 지도에 반영할
        방법이 없어(Info.plist는 빌드 타임에만 고정) 폰트 선택 UI 자체가 무의미함을
        마스터 확인 후 제외 결정. Android는 `fonts.xml` 파싱 + `Paint.hasGlyph()` 필터링
        (실패 시 "시스템 기본" 폴백), 기본값 `sans-serif`, 선택값은 지도 3화면(4개
        `MapLibreMap` 생성 지점)에 `ref.read`(1회성, 런타임 미반영 제약 반영)로 전달
  - [ ] **남은 것 — 실기기 검증(헤드리스 서버라 이 세션에서 불가)**: iOS 실기기/시뮬레이터
        한글 라벨 `Apple SD Gothic Neo` 렌더 확인 · Android(갤럭시 우선) `sans-serif` 별칭이
        One UI 기본 폰트로 렌더되는지 · 설정에서 폰트 변경 → 지도 화면 재진입 시 반영 확인
- [ ] **O2 · 타일 오프라인** — 서버에서 **전국 + 17개 시도 mbtiles 사전 생성** →
      `installOfflineMapTiles` 사이드로드 + 선택 UI + WiFi 백그라운드.
      ⚠️ `setOfflineTileCountLimit` 안 올리면 조용히 끊김.
      **2026-08-06 결정**: 시도 bbox 겹침(경기 안 서울) 처리는 **지금은 보류, 전국
      통짜(382MB) 1개만 우선 제공**. 시도 단위 분할은 이후 별도 결정
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
