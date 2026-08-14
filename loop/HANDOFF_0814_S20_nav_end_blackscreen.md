GOAL: 내비게이션 종료(도착) 직후 화면이 까맣게 멈추는 버그의 정확한 트리거를 찾아 고친다 —
터치는 먹히는데 렌더링만 죽는 증상, 마스터가 뒤로가기 연타로 탈출.

- 작성 2026-08-14 · 마스터 확인(대화, 2026-08-14 저녁): 5개 문제 중 이 항목을 최우선으로 착수
- 근거: [RECON_0814_testride_issues.md](RECON_0814_testride_issues.md) §1 (로그 타임라인 전체),
  `loop/testride_result/log/ynav_2026-08-14T18-26-00.log` 라인 569~650,
  `loop/testride_result/Screenshot_20260814_182838_Yurunavi.jpg`(증상 스크린샷),
  `VERIFY_0806_S3_master_device_check.md` §2 마지막 항목(8/6부터 미해결로 남아있던
  "오버레이 잔존" — 이번 버그와 같은 뿌리일 가능성 높음)

## 확정된 사실 (RECON §1 요약, 재조사 불필요)

로그 타임라인(`ynav_2026-08-14T18-26-00.log`):
1. `18:28:10.354` — `MapLibreGLSurfaceView`(지도만) `surfaceDestroyed`. 0.5초 뒤 `YNAV_TOUR saved`
   — 도착 처리로 nav_screen에서 화면 전환되며 지도 위젯이 정상적으로 언마운트된 것으로 추정
   (이 자체는 문제 아닐 가능성 높음).
2. `18:28:28.267` — **`FlutterSurfaceView`(앱 전체, `0,0-1080,2340`)** `surfaceDestroyed`. 동시에
   `YNAV_MEMPRESSURE onTrimMemory`+`background imageCache cleared` — 진짜 backgrounded 전환.
3. `18:28:32.404~496` — `FlutterSurfaceView` 재생성(`surfaceCreated`). 4초 만에 복귀.
4. **`18:28:38`** — 마스터가 블랙스크린 스크린샷 촬영. 재생성(18:28:32)으로부터 6초 지났는데도
   화면이 까맣다.
5. `18:28:44.623` — `FlutterSurfaceView` **다시** `surfaceDestroyed`. 다시 `onTrimMemory`+
   `background` 동시 발생 (16초 만에 재발).
6. 로그 캡처 종료(18:30:04)까지 이후 `surfaceCreated` 없음.

즉 도착 후 40초 사이 앱이 백그라운드 전환을 **두 번** 겪었고, 두 번째 전환 이후 화면이 다시
그려졌다는 증거가 없다. `YNAV_CRASH` 0건 — 하드 크래시 아님, 렌더 표면만 죽은 것.

## 미확정 — 이 세션에서 찾아야 할 것

**왜 도착 직후 40초 사이 background 전환이 두 번이나 발생했는가**가 핵심 질문. 정상적인 단일
백그라운드 전환(마스터가 실수로 홈 버튼을 눌렀다 등)이라면 한 번만 발생해야 한다. 유력 후보:

1. **오버레이 show/hide 경합**: [nav_screen.dart:504-516](lib/features/navigation/presentation/nav_screen.dart#L504-L516)
   `didChangeAppLifecycleState`가 paused/hidden마다 `NavFloatingOverlay.show()`, resumed마다
   `.hide()`를 호출. 도착 직후 `_arrivalBannerVisible`/`_showExitConfirm` 상태 전환
   ([nav_screen.dart:621-639](lib/features/navigation/presentation/nav_screen.dart#L621-L639))이나
   Navigator 전환이 윈도우 포커스를 순간적으로 흔들면, 매 흔들림마다 오버레이 show/hide가
   다시 발동해 사이클을 만들 수 있다.
2. **FloatingOverlayService의 상태 추적 취약점**: [FloatingOverlayService.kt:49-50](android/app/src/main/kotlin/com/westinx/yurunavi/FloatingOverlayService.kt#L49-L50)
   `overlayView` 참조를 1개만 들고 있고, show(`ACTION_SHOW`)/hide(`ACTION_HIDE`)가 별도
   Intent로 비동기 처리됨([FloatingOverlayService.kt:54-77](android/app/src/main/kotlin/com/westinx/yurunavi/FloatingOverlayService.kt#L54-L77)).
   hide 처리 중(`stopSelf` 대기)에 show가 다시 들어오면 `overlayView`가 덮어써지면서 이전 뷰가
   `windowManager`에서 못 지워진 채 남을 수 있는 구조 — 이게 곧바로 "화면 전체가 까맣다"로
   이어지진 않지만(오버레이는 72dp뿐), 같은 타이밍대의 윈도우 포커스 흔들림과 얽혔을 가능성.
3. **arrival 배너/종료 확인 다이얼로그 자체의 Navigator 동작**: 도착 시 `_showExitConfirm=true`로
   전환되는 하단 카드(재탐색/종료 버튼)가 뭔가를 `push`/`pop`하거나 시스템 다이얼로그를 띄우는지
   확인 필요 — nav_screen.dart에서 `_showExitConfirm` 관련 위젯 트리와 도착 후 실제 화면 전환
   흐름(다음 화면이 뭔지: 홈? 투어 요약? 제자리?)을 추적할 것.

## 조사·수정 순서 제안

1. `nav_screen.dart`에서 도착(`_arrived=true`) 이후 실제로 어떤 화면 전환이 일어나는지 전체
   흐름을 먼저 그릴 것 — "종료" 버튼 탭 시 정확히 뭘 하는지(`Navigator.pop`? 여러 단계?).
   현재 이 조사는 안 되어 있음.
2. `didChangeAppLifecycleState`에 임시로 상세 로그(`YNAV_LIFECYCLE state=$state`)를 추가해
   실제로 pause/resume이 몇 번, 어떤 순서로 오는지 직접 재현/확인 — 에뮬레이터든 실기기든 도착
   직후 흐름을 인위적으로 만들어볼 것 (헤드리스라 실기기 없으면 최소한 코드 경로상 논리적으로
   이 상태 전이가 가능한지 추적).
3. 원인이 오버레이 show/hide 경합으로 확인되면: `FloatingOverlayService`를 상태 머신으로
   경화(매 show 전에 기존 뷰 무조건 제거 후 재생성, 또는 in-flight 요청 직렬화)하고,
   `didChangeAppLifecycleState`에 짧은 디바운스(예: 300~500ms 내 재전이는 무시)를 추가.
4. 원인이 다른 곳(Navigator 전환 자체)이면 그 경로를 고칠 것 — 추측으로 오버레이만 고치고
   끝내지 말 것.
5. **재현 확인 불가(헤드리스 서버, 실기기 없음)** — 코드 수정 후 반드시
   `loop/VERIFY_0806_S3_master_device_check.md` 또는 새 VERIFY 파일에 "도착 직후 화면 안
   까매지는지" 항목을 추가해 다음 실주행 때 마스터가 직접 확인하게 할 것. 하네스로 재현
   가능한 부분(로그 패턴 재생 등)이 있으면 우선 그걸로 검증.

## 코딩 지시사항

- flutter-coder에게 위임. Kotlin(`FloatingOverlayService.kt`) 쪽 변경이 필요하면 같은 세션에서
  함께 처리(별도 rust-coder 불필요, 이건 Rust 엔진과 무관).
- 이 버그는 8/6 §S3b부터 이어지는 사안이라 **회귀 방지가 최우선** — §1(라이프사이클 오검출
  방어)·§2(정상 백그라운드 전환)의 기존 통과 테스트를 절대 다시 깨지 않을 것
  (`VERIFY_0806...md` §1~2 참고, 특히 "inactive에는 절대 반응하지 않는다" 주석
  [nav_screen.dart:501-502](lib/features/navigation/presentation/nav_screen.dart#L501-L502)의
  의도를 건드리지 말 것).
- 원인 불명확한 채로 "일단 오버레이를 더 자주 hide 시키는" 식의 땜질 금지 — 위 조사 순서대로
  실제 트리거를 먼저 특정할 것.

## 검증 체크리스트

- [ ] `flutter analyze` / 기존 유닛 테스트 통과
- [ ] 가상GPS 하네스로 §1/§2 기존 시나리오(알림창 내리기, 스크린샷, 엣지패널, 홈버튼→복귀) 재실행
      — 전부 여전히 [O]
- [ ] 새로 추가한 로그(`YNAV_LIFECYCLE` 등)가 남는지 확인
- [ ] code-auditor 리뷰 PASS
- [ ] `VERIFY_*.md`에 "도착 직후 블랙스크린 재발 여부" 항목 추가 — 다음 실주행에서 마스터가 확인
