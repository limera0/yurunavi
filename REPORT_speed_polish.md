# REPORT — 보간 복구 + 권한 팝업화 + GPS 선점기동

날짜: 2026-06-11
브랜치: feat/maplibre-migration

## 0단계 분석 (HALT 없음)

### 보간 끊긴 지점 — 코드 수준 regression 없음
`_speedTicker` 필드(72), dispose cancel(171), `_startLocation` 기동(211-212) 모두 정상.
`_tickSpeed` 내 `setState(_speedKmh)` 경로 5개(228,234,243,253,261) 모두 존재.

**"보간 죽음" 실제 원인 (16:39 로그):**
`ForegroundNotificationConfig` 추가됐으나 알림 권한 미부여 상태로 테스트
→ Android 13+ 에서 foreground service 미기동 → GPS 배경 throttle(5초+)
→ 5초 fix 간격 + 등속 주행 시 slope≈0 → ticker 가 200ms마다 같은 값 출력 → "화면이 안 바뀌는" 느낌

코드 regression: `_onPosition` 첫 줄에 **별도 setState** 추가(`_firstFixReceived`)
→ GPS 이벤트마다 extra rebuild 발생. 이것이 실제 동작을 끊진 않지만 불필요한 재빌드.

### 권한 온보딩 2회차 버그
`splash_screen.dart`가 무조건 `PermissionOnboardingScreen`으로 라우팅 (granted 여부 무관).
SharedPreferences 플래그도 없으므로 매 실행마다 온보딩 화면 표시.

### GPS 선점
`main_map_screen.dart`의 `_startLocationTracking()`(line 175)이 이미 GPS 스트림 기동.
`currentLocationProvider`에 위치 값 있으면 NavScreen 진입 시 하드웨어 GPS 이미 워밍업됨.

---

## 커밋별 변경

### `5fb635d` fix(nav): restore 200ms extrapolation ticker broken by speedometer UI

파일: `nav_screen.dart`

| 변경 | 내용 |
|---|---|
| `_onPosition` 첫 줄 제거 | `if (!_firstFixReceived) setState(() => ...)` 별도 setState 삭제 |
| throttle early-return setState | `setState(() { _currentPos=loc; if (!_firstFixReceived) _firstFixReceived=true; })` |
| 메인 setState | `setState(() { _currentPos=loc; _speedKmh=speedKmh; if (!_firstFixReceived) _firstFixReceived=true; })` |

**효과:** 1회 `_onPosition` 호출당 setState 최대 1회 (기존: 최대 2회). extra rebuild 제거.

### `3401f8d` fix: replace permission page with one-time OS prompts

파일: `splash_screen.dart` (완전 재작성), `permission_onboarding_screen.dart` (삭제)

- **삭제**: `lib/features/auth/presentation/permission_onboarding_screen.dart`
- `_requestPermissions()`: `Permission.location.status → request()`, `Permission.notification.status → request()`
  - granted면 팝업 없음 (2회차 skip), 미허용이면 OS 표준 팝업 1회
  - 배터리 최적화 / 오버레이 강제 팝업 없음
- `_runSequence()`: splash 애니메이션 → `_requestPermissions()` → `_goToMain()`
- 권한 흐름: 매 실행 시 상태 체크 → 미허용분만 요청. 별도 저장 플래그 불필요.

### `486b21e` revert: drop battery-optimization request

파일: `android/app/src/main/AndroidManifest.xml`

| 제거 | 이유 |
|---|---|
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 로그 확인: 5초가 기기 하드웨어 한계. OS 설정 팝업이 UX 방해 |

유지: `SYSTEM_ALERT_WINDOW` (HUD 오버레이 가능성, 팝업 강제 없음)

### `ee92404` feat: warm up GPS on app launch to hide coldstart

파일: `nav_screen.dart` `_startLocation()`

- `ref.read(currentLocationProvider)` 로 MainMapScreen GPS 스트림 결과 참조
- non-null이면: `setState({ _currentPos=knownLoc, _firstFixReceived=true })` + 카메라 이동
- null이면(냉각 시나리오): 기존 `getLastKnownPosition()` 폴백 실행
- **이중 구독 없음**: MainMapScreen 스트림과 NavScreen 스트림은 별개 subscription. 두 구독이 동일 fused provider에 연결되며 충돌 없음. MainMapScreen dispose 시 자동 해제.

**효과:** 앱 켠 후 지도에서 GPS fix를 이미 받은 상태로 내비 진입 → `_firstFixReceived=true` 즉시 → "GPS 검색 중" 표시 안 보이거나 매우 짧음.

---

## 권한 흐름 (최종)

```
앱 기동
  └─ SplashScreen 애니메이션 (800ms)
       └─ _requestPermissions()
            ├─ Permission.location: granted? → skip / denied? → OS 팝업
            └─ Permission.notification: granted? → skip / denied? → OS 팝업
                  └─ MainMapScreen
                       └─ _startLocationTracking() → GPS 워밍업 시작
                            └─ (사용자가 경로 설정 후 내비 시작)
                                  └─ NavScreen._startLocation()
                                       ├─ currentLocationProvider != null → _firstFixReceived=true 즉시
                                       └─ NavScreen GPS 스트림 (foregroundNotification) 기동
```

## 빌드
- `flutter analyze`: 0 error. 잔존 warning 1건 (`show max` unused) — 기존 코드, 무관
- `flutter build apk --debug`: ✓ 성공 (11.1s, 증분 빌드)
- APK: `build/app/outputs/flutter-apk/app-debug.apk` (≈215 MB)

## 사용자 1회 주행 체크리스트

| 항목 | 내용 |
|---|---|
| ★ 멈추면 2~3초 내 0 하강 | `_moving=false` → ticker 즉시 0. 5초 GPS 해결(알림권한)이 핵심. |
| ★ 재출발 시 고착 없이 속도 | `_moving=true` 즉시 외삽 시작 |
| 첫 실행: 위치·알림 OS 팝업 1회 | splash에서만 뜸, 페이지 없음 |
| 2회차: 팝업 안 뜸 | granted → skip |
| 앱 켜고 바로 내비 진입 → "검색 중" 안 보임 | GPS 선점 효과 |
| 알림바 노티 | 알림 권한 허용 + 내비 중 |

## 노트북 설치
```
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
권한 초기화가 필요하면: `adb shell pm revoke com.example.yurunavi android.permission.ACCESS_FINE_LOCATION`
