# REPORT — 콜드스타트 로딩표시 + 권한 온보딩 플로우

날짜: 2026-06-11
브랜치: feat/maplibre-migration

## 0단계 확인 결과 (HALT 미발생)
- `_Speedometer` 위젯: 정의 line 1041–1068, StatelessWidget, 파라미터 `speedKmh: double` 1개. 사용 line 919.
- `_firstFixReceived` 플래그: 기존 없음 → 신설
- 진입부: `splash_screen.dart` `_runSequence()` → `_requestPermission()`(geolocator 위치만) → `_goToMain()`
- Manifest: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS` 이미 보유 / `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `SYSTEM_ALERT_WINDOW` 누락
- `permission_handler`: pubspec에 없음 → 추가 / `shared_preferences`: 있음

## 불변 영역 (수정 안 함)
속도 보간 ticker(`_tickSpeed`), `_onPosition` 판정 로직, 카메라/재탐색/TTS/bearing — 전부 그대로.

## 커밋별 변경

### `ac8491d` feat(nav): show 'searching GPS' until first fix (coldstart)
파일: `lib/features/navigation/presentation/nav_screen.dart`

| 항목 | 내용 |
|---|---|
| 필드 추가 | `bool _firstFixReceived = false;` (line 68 이후) |
| `_onPosition` 변경 | 진입 직전 `if (!_firstFixReceived) setState(() => _firstFixReceived = true);` |
| `_Speedometer` 호출부 | `speedKmh: _speedKmh` → `speedKmh: _speedKmh, firstFixReceived: _firstFixReceived` |
| 클래스 변경 | `StatelessWidget` → `StatefulWidget` + blink AnimationController (700ms, 0.25~1.0 opacity, repeat reverse) |
| `firstFixReceived==false` 시 | `FadeTransition`으로 점멸하는 "GPS" + "검색 중" 2줄 표시 (Circle 컨테이너/레이아웃 불변) |
| `didUpdateWidget` | 첫 fix 수신 시 blink controller 정지 |

### `8564405` chore: add permission_handler
파일: `pubspec.yaml`
- `permission_handler: ^11.4.0` 추가, `flutter pub get` 실행

### `d3e22ef` chore(android): declare foreground-service & notification permissions
파일: `android/app/src/main/AndroidManifest.xml`

추가 2줄:
```xml
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```
(기존 FOREGROUND_SERVICE / FOREGROUND_SERVICE_LOCATION / POST_NOTIFICATIONS 유지)

### `485b3bd` feat: first-run permission onboarding (location/notification/battery)
신규 파일: `lib/features/auth/presentation/permission_onboarding_screen.dart`
수정 파일: `lib/features/auth/presentation/splash_screen.dart`

**온보딩 화면 항목 (permission_onboarding_screen.dart):**
| 항목 | 권한 | 필수 | 동작 |
|---|---|---|---|
| 위치 | `Permission.location` | ✓ | `request()` / 영구거부 시 설정 열기 다이얼로그 |
| 알림 | `Permission.notification` | — | `request()` (포그라운드 서비스 노티 허용) |
| 배터리 최적화 제외 | `Permission.ignoreBatteryOptimizations` | — | `request()` (Android only) |
| 다른 앱 위에 표시 | `Permission.systemAlertWindow` | — | `request()` (Android only) |

**동작 로직:**
- `initState` → 전 항목 상태 체크 → 전부 granted면 즉시 자동 통과 → `MainMapScreen`
- 항목별 "허용" 버튼으로 개별 요청 / 요청 후 UI 즉시 갱신(체크 아이콘)
- 하단 "시작하기" / "위치 권한 없이 계속" 버튼으로 부분 거부 시도 진행 가능
- 기존 `splash_screen.dart`: `_requestPermission()` + `_goToMain()` 제거 → `_goToOnboarding()` 한 줄로 교체

## Manifest Diff (최종)
```xml
<!-- 기존 (유지) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- 신규 추가 -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

## 빌드
- `flutter analyze` (전체): 0 error. 잔존 warning 1건 (`show … max` unused) — 기존 코드, 무관.
- `flutter build apk --debug`: ✓ 성공 (23.4s)
- APK: `build/app/outputs/flutter-apk/app-debug.apk` (≈215 MB)

## 사용자 1회 확인 체크리스트 (집에서 30초)
- [ ] 앱 재설치(adb uninstall + install) 후 첫 실행 → 권한 온보딩 화면 표시되는가
- [ ] 알림 허용 후 내비 시작 → 알림바에 "유루나비 주행 중" 노티 표시 (커밋4 효과, 이전 턴 포그라운드 서비스 효과 검증)
- [ ] 배터리 최적화 제외 허용 → 주행 시 SPD 로그 fix 간격 1초로 개선되는지 (5초 절전 심판)
- [ ] 내비 시작 후 GPS fix 수신 전 "GPS / 검색 중" 점멸 표시되다 첫 fix 수신 시 속도 숫자로 전환되는가

## 노트북 설치
헤드리스 서버라 `flutter run` 불가. APK를 노트북으로 옮겨:
```
adb uninstall com.example.yurunavi  # 권한 온보딩 1회 조건 초기화
adb install build/app/outputs/flutter-apk/app-debug.apk
```
