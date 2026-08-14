GOAL: HANDOFF_0814_S20_nav_end_blackscreen.md의 "왜 도착 직후 40초 사이 background
전환이 두 번이나 발생했는가"를 실기기+가상GPS로 조사하고, 확정된 원인에 한해서만 고친다.

# RECON — S20 내비 종료 후 블랙스크린 조사 (오버레이 가설 반증 + 진단 로깅 추가)

- 작성 2026-08-14 · 브랜치 `verify/ride-0711` · 헤드리스 서버 + M32 실기기(가상GPS)
- 근거: `HANDOFF_0814_S20_nav_end_blackscreen.md`, `RECON_0814_testride_issues.md` §1,
  `testride_result/log/ynav_2026-08-14T18-26-00.log`,
  `testride_result/Screenshot_20260814_182838_Yurunavi.jpg`

## 결론 요약

1. **HANDOFF의 1번 후보(오버레이 show/hide 경합)는 반증됨.** 8/14 실주행 로그를 초 단위로
   재대조한 결과, `nav_screen`은 도착 10초 뒤 auto-exit 타이머로 이미 pop되어
   `didChangeAppLifecycleState` 옵저버까지 `dispose()`에서 제거된 **18초 뒤**에야 첫 번째
   진짜 background 전환이 발생했다. 즉 오버레이 show/hide를 호출하는 코드 자체가 그 시점엔
   이미 화면에서 사라진 상태라, `nav_screen`의 라이프사이클 로직이 이중 전환의 원인일 수
   없다. `FloatingOverlayService.kt`/`nav_screen.dart`는 이번 세션에서 건드리지 않았다.
2. **블랙스크린은 진짜 콘텐츠 렌더 실패다.** 문제의 스크린샷을 픽셀 단위로 보면 상태바(배터리
   `48%` 등)와 하단 내비게이션 바는 정상 렌더되고, 오직 앱 콘텐츠 영역만 완전히 검다 —
   화면이 꺼지거나 잠긴 게 아니라 Flutter 렌더 표면(그 시점엔 `nav_screen`이 이미 pop된
   뒤라 `main_map_screen`)이 화면을 못 그린 것이다.
3. **유력 원인은 기존에 미해결로 남아있던 "S1b 렌더링 자원 고갈"류의 재발/악화.**
   (`project_render_resource_exhaustion` 메모리 참고) 이 기기는 `Using the Impeller
   rendering backend (Vulkan)`으로 확인됨. `YNAV_CRASH` 0건, `atlas`/`Impeller`/`Vulkan`/
   `OOM` 관련 네이티브 에러 로그도 0건 — 이미 알려진 "조용한 GPU 자원 할당 실패" 패턴과
   일치한다.
4. **가상GPS로 재현 시도 — 실패(음성 증거).** 아래 §재현 시도 참고. 단순 pause/resume
   반복만으로는 재현되지 않았다 — 실제 메모리 압박(다른 앱 실사용) 또는 장시간 누적
   가동(이번 필드 세션은 17:10부터 78분 연속 가동)이 필요조건일 가능성이 높다.
5. **조치: 코드 동작 변경 없이 진단 로깅만 추가.** 원인을 확정하지 못한 채로 오버레이를
   더 자주 hide시키거나 resume마다 지도를 강제로 재생성하는 식의 땜질은 HANDOFF의
   지시(§코딩 지시사항)에 반하므로 하지 않았다. 대신 `MemoryPressureObserver`(전역
   옵저버, `nav_screen`과 무관하게 앱 전체 생애주기 동안 유지됨)에
   `YNAV_LIFECYCLE state=$state`를 추가해, 다음 실주행에서 정확한 pause/resume 횟수·순서·
   시각을 놓치지 않고 잡는다. `nav_screen` 로컬 옵저버에 추가하라는 HANDOFF의 원안 위치는
   위 1번 이유로 의도적으로 바꿨다 — 그 위치는 정확히 이 버그가 필요로 하는 순간에는 이미
   해제되어 있다.

## 로그 재대조 (분 단위 아님, 초 단위로 재확인)

`ynav_2026-08-14T18-26-00.log` 기준:

| 시각 | 이벤트 |
|---|---|
| 18:27:59.139 | `YNAV_ARR` — 도착 판정 |
| 18:28:09 경(추정) | `_canExit` 게이트 열림, 10초 자동종료 타이머 시작(도착과 거의 동시 —
  가상GPS 재현에서도 게이트가 즉시 열리는 패턴 확인) |
| **18:28:10.354** | `MapLibreGLSurfaceView` `surfaceDestroyed` — **`nav_screen`이 pop되며
  지도 위젯이 언마운트된 시점으로 추정** (auto-exit 타이머 만료와 시간이 일치) |
| 18:28:10.920 | `YNAV_TOUR saved` — `_exitNav()`가 `_finalizeAndPersistTour()`를 호출한
  결과. `nav_screen.dispose()`도 이 시점에 실행되며 `WidgetsBinding.instance
  .removeObserver(this)`가 함께 호출된다 — **이 순간부터 `nav_screen`의
  `didChangeAppLifecycleState`는 더 이상 어떤 이벤트도 받지 못한다.** |
| **18:28:28.267** | `FlutterSurfaceView`(앱 전체) `surfaceDestroyed` + `YNAV_MEMPRESSURE
  onTrimMemory`+`background` 동시 발생 — **첫 번째 진짜 background 전환.
  10.354로부터 17.9초 뒤, 즉 `nav_screen`이 이미 사라진 지 한참 뒤다.** |
| 18:28:32.4 | `FlutterSurfaceView` `surfaceCreated`(재생성) |
| **18:28:38** | 마스터가 블랙스크린 스크린샷 촬영 — 재생성으로부터 6초 지났는데 콘텐츠
  영역이 검다 |
| **18:28:44.623** | `FlutterSurfaceView` **두 번째** `surfaceDestroyed` + 다시 MEMPRESSURE
  동시 발생 (16.4초 만에 재발) |
| 18:30:04 | 로그 캡처 종료까지 이후 `surfaceCreated` 없음 |

**결론:** 18:28:10 이후 `nav_screen`은 화면에도, 옵저버 목록에도 없다. 그 뒤에 일어난
background 전환 2회와 렌더 실패는 100% `nav_screen` 바깥(정상 흐름이면 `main_map_screen`)
에서 벌어진 일이다.

## 재현 시도 (M32 실기기, 가상GPS 200km/h)

마스터 지시대로 가상GPS 속도를 200km/h로 설정해 조사 소요 시간을 최소화했다.

**준비 과정에서 발견한 것**:
- M32에 깔려있던 건 `release=true` 빌드 — `kDebugMode` 게이트가 걸린 E2E 하네스가
  전혀 동작하지 않아 처음 두 번의 테스트가 통째로 낭비됨(내비가 아예 시작되지 않음).
  `flutter build apk --debug`(JDK21: `/home/limera/.local/jdk/jdk-21.0.7+6`)로 새로
  빌드해 설치. **마스터 승인 하에 기존 release 앱을 제거**(서명 불일치로 덮어설치 불가) —
  기기의 투어 기록 등 앱 데이터가 삭제됐다. 다음 실주행 전 release 빌드로 재설치 권장.
- 재설치 후 위치/알림/오버레이 권한이 초기화돼 `pm grant`+`appops set`으로 재부여 필요.
- 테스트 세션 간 `force-stop`만 쓰면 진행 중이던 투어가 "고아 투어"로 남아 다음 실행이
  스플래시의 "이어서 안내할까요?" 다이얼로그에 막혀버림(이 다이얼로그는 사람 탭 없이는
  못 넘어간다) — `pm clear`로 완전 초기화해야 재현 스크립트가 매번 깨끗하게 시작된다.

**실제 재현 시나리오**: 목적지까지 5.9km 경로(고덕 지산로 방면)를 200km/h로 주행 →
도착 → auto-exit(10초 게이트) 정상 완료(스크린샷으로 확인, `main_map_screen` 정상 렌더) →
**HOME 키로 3초 배경 전환 → 재개(2회, 첫 dwell 3초·둘째 dwell 12초 — 실측 로그의 17.9초/
16.4초 간격과 유사)** → 매번 스크린샷.

**결과: 재현 안 됨.** 두 배경 전환 모두 `OpenGLRenderer eglCreateWindowSurface` +
`acquireNextBufferLocked`로 정상적으로 GPU 표면이 재생성되고 지도가 즉시 다시 그려졌다
(스크린샷 7장 전부 정상 렌더 확인, `s20_repro2/shots/` — 세션 스크래치패드, 커밋 안 됨).

**해석**: 단순 홈버튼 배경 전환만으로는 재현되지 않는다. 이번 테스트는 앱 가동 3분·
기기 여유 메모리 상태에서 진행됐다. 반면 8/14 실주행은 17:10부터 78분 연속 가동 중이었고,
과거 `HANDOFF_0805_S1b_render_resource.md`/`loop/repro_s1b/bgpressure_monitor_0806.sh`의
재현 방법론은 크롬/유튜브 등 **실제 배경 앱 사용으로 만든 진짜 메모리 압박**을 몇십 분
지속시키는 것이었다(그마저도 그때 확정 재현엔 성공 못 함). 즉 이 결함은 "짧은 pause/resume
자체"가 아니라 "장시간 가동 후 메모리 압박이 겹친 순간의 GPU 재할당 실패"일 가능성이 높다
— 기존 미해결 진단과 정합적이다.

## 이번 세션에서 한 것 / 안 한 것

- **한 것**: `lib/core/memory/memory_pressure_observer.dart`에 `YNAV_LIFECYCLE
  state=$state` 로깅 추가(전역 옵저버, 모든 상태 전이 기록). code-auditor PASS,
  `flutter analyze` 클린, `flutter test` 714건 전부 통과.
- **안 한 것**: `FloatingOverlayService.kt`/`nav_screen.dart`의 라이프사이클·오버레이
  로직은 원인이 아님을 확인했으므로 손대지 않음. resume마다 지도/화면을 강제
  재생성하는 식의 대응도 검증 없이 넣지 않음 — 매 정상 배경↔전경 전환(주행 중 잠깐
  메시지 확인 등, 극히 흔함)마다 깜빡임/재로드 비용을 치르게 하는 트레이드오프라 마스터
  판단 없이는 넣을 수 없다.

## 다음 세션 제안

1. 이번에 추가한 `YNAV_LIFECYCLE`이 다음 실주행 로그에 남으므로, 재발 시 정확한
   pause/resume 횟수·시각과 그 순간의 `YNAV_GPUMEM`(60초 주기)을 대조하면 "장시간 가동 +
   메모리 압박" 가설을 실측으로 확정/반증할 수 있다.
2. 확정되면 8/6에 이미 준비해둔 `outputs/yurunavi_impeller_off_diag_20260806.apk`
   (Impeller 끈 판별용 빌드, 채택 후보 아님)로 Impeller 자체가 원인인지 최종 판별 —
   이 선택은 마스터 승인 필요(`project_render_resource_exhaustion` 메모리 참고).
3. 장시간(30분+) 실제 배경 앱 사용을 곁들인 가상GPS 재현을 한 번 더 시도해볼 가치는
   있으나, 세션 하나로는 예산이 부족했다 — 별도 세션으로 분리 권장.
