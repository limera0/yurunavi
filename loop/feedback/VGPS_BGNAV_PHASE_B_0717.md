# 2026-07-17 실기기 검증 — 백그라운드 내비게이션 Phase B(PiP 미니창)

`HANDOFF_0717_launch_priorities.md` 3순위 착수분 후속. Phase A(포그라운드 서비스, 커밋
`d4b50e1`/`b883ee5`)에 이어 "다른 앱 사용 중에도 다음 안내를 볼 수 있게" 하는 PiP 미니창.
승인된 계획은 `/home/limera/.claude/plans/generic-beaming-wadler.md` Phase B.

## 기술 선택

Android 시스템 Picture-in-Picture API(`android_pip` 패키지, 2.0.2) 사용 — 유튜브가 실제로
쓰는 것과 동일한 OS 레벨 PiP다. `SYSTEM_ALERT_WINDOW` 기반 플로팅 버블(`flutter_overlay_window`
등)은 검토했으나 (1) Google이 공식적으로 PiP/Bubbles로의 대체를 권고 중이고 (2) Play스토어에서
제한된 권한으로 더 엄격히 심사되며 (3) 후보 패키지가 15개월간 업데이트 없어 장기 유지보수
리스크가 있어 기각(사용자와 AskUserQuestion으로 확정).

## 버그 발견 및 수정 — PiP 진입 타이밍

최초 구현은 Flutter `didChangeAppLifecycleState(AppLifecycleState.paused)`에서
`enterPipMode()`를 호출했다. **실기기 검증 결과 PiP가 전혀 뜨지 않음**을 확인(HOME 키
직후 `dumpsys activity activities`의 `mLastReportedPictureInPictureMode`가 계속
`false`) — Flutter의 `paused`는 Android `onStop()`에 대응해 액티비티가 이미 화면에서
사라진 뒤라 너무 늦다. Android 공식 문서가 권장하는 `onUserLeaveHint()`(`onPause()`
이전, 액티비티가 아직 보이는 시점)로 교체:

- `MainActivity.kt`에 `onUserLeaveHint()` 오버라이드 → 신규 `nav_pip_hint` 채널로 Dart에
  전달.
- `nav_screen.dart`에서 `WidgetsBindingObserver`/`didChangeAppLifecycleState` 제거,
  이 채널 핸들러가 `_maybeEnterPip()` 호출(게이트: 목적지 있음 + 수동모드 아님 +
  코스시트 아님).

## 검증 절차 및 결과

`flutter build apk --debug` → `adb install -r`(커밋 `1e99528` 포함) → E2E 하네스로 내비
시작(`--es e2e_dest_lat/lon`) → `adb shell input keyevent KEYCODE_HOME`.

- **수정 전**: PiP 미진입 확인(위 버그).
- **수정 후**: `dumpsys activity activities`에 `mode=pinned`,
  `mLastReportedMultiWindowMode=true mLastReportedPictureInPictureMode=true` 확인.
  스크린샷상 PiP 창에 다음 턴 아이콘(좌회전 화살표)+"좌회전"+"94m" 정확히 렌더링
  (온스크린 카드와 동일 데이터 소스 재사용 확인).
- **복귀**: `am start`로 포그라운드 복귀 시 전체 UI(턴카드/속도계/경로) 정상 렌더,
  크래시 없음.
- **Phase A 공존**: PiP 진입~복귀 전 구간에서 `NavForegroundService`
  (`isForeground=true foregroundId=1001`) 계속 유지 — 두 기능이 서로 간섭 안 함.
- **종료**: 내비 종료 버튼 탭 → 서비스/알림 모두 정상 제거, `AndroidRuntime`/`FATAL`
  로그 없음.
- `flutter analyze` 0 issues, `flutter test` 217/217 통과.

## 다음

Phase C(문서 갱신)만 남음 — 코드 작업은 A/B 모두 완료. iOS는 별도 과제로 분류(이번
스코프에서 계획 단계부터 제외, 근거는 계획 문서 Context 섹션 참조).
