# REPORT_location_continuous.md — 위치 연속 수신 + staleness 워치독

브랜치: `feat/maplibre-migration` / 작업일 2026-06-10
대상: `lib/features/navigation/presentation/nav_screen.dart` (단일 파일)

## 한 일 (커밋)

| 커밋 | 내용 |
|---|---|
| `3bfb53e` | checkpoint: before continuous location + watchdog |
| `33d7f9a` | **fix(nav): forceLocationManager for continuous 1Hz GPS** |
| `d30e414` | **fix(nav): staleness watchdog forces speed 0 on fix loss** |

불변 영역(도플러 히스테리시스 속도 산출, 카메라/재중심, `_reroute`, TTS, bearing) **로직 무수정.** 변경은 명시된 두 가지뿐.

## 변경 상세

### 커밋 1 — forceLocationManager (`nav_screen.dart:188-194`)
```dart
locationSettings: AndroidSettings(
  accuracy: LocationAccuracy.bestForNavigation,
  intervalDuration: const Duration(milliseconds: 333), // ~3Hz 목표
  distanceFilter: 0,
  forceLocationManager: true, // fused 절전 우회 → 생 GPS 연속 수신
),
```
- 한 줄 추가. `intervalDuration`/`distanceFilter` 그대로 유지.
- 의도: fused provider의 배치/절전(5초 간격 의심)을 우회해 LocationManager 생 GPS를 ~1Hz로 연속 수신.

### 커밋 2 — staleness 워치독 (독립)
- 필드 (`nav_screen.dart:88-89`): `Timer? _staleTimer;`
- `_onPosition` 맨 끝 (매 fix 수신 시) 타이머 리셋:
  ```dart
  _staleTimer?.cancel();
  _staleTimer = Timer(const Duration(seconds: 3), () {
    if (mounted) setState(() { _speedKmh = 0.0; _moving = false; });
  });
  ```
- `dispose()`에 `_staleTimer?.cancel();` 추가.
- 동작: fix가 계속 오면 매번 리셋돼 발동 안 함. 3초간 새 fix 없으면 정차로 간주, `_speedKmh=0`·`_moving=false` 강제 → '12 고착/3분 고착' 원천 차단.
- 변수명은 0단계 확인값 사용: 속도 `_speedKmh`(`:59`), 이동상태 `_moving`(`:67`). 속도 위젯 `_Speedometer(speedKmh: _speedKmh)`(`:854`)가 즉시 반영.

## 검증 상태

- ✅ `flutter analyze` (대상 파일): 에러 0. (기존 unused_shown_name warning 1건은 본 변경과 무관)
- ✅ `flutter build apk --debug`: 성공 → `build/app/outputs/flutter-apk/app-debug.apk`
- ⏳ **폰/스쿠터 실측: 미수행 (헤드리스 서버라 폰 접근 불가).** 아래 체크리스트는 노트북에서 사용자가 수행:
  ```
  scp build/app/outputs/flutter-apk/app-debug.apk <노트북>
  adb install -r app-debug.apk
  ```

### 스쿠터 실측 체크리스트 (사용자 수행)
- [ ] ★정차 후 3초 안에 0km/h (12/3분 고착 완전 해소 — 최우선)
- [ ] ★출발 반응 빨라졌는가 (forceLocationManager로 1초면 1~2초)
- [ ] SPD 로그 간격: 5초 → ? (forceLocationManager 효과 측정)
- [ ] 정차 중 r이 0 아닌 값 뜨는가 (앵커 부활 — 1초 됐을 때)
- [ ] 주행 중 속도 정상 (회귀 없는지)
- [ ] bearing/카메라/재탐색/TTS 이전과 동일
- 로그 수집: `adb logcat -d | Select-String "SPD"` → 정차 구간 포함 연속 15줄 첨부

## 회귀 시 격리 가이드
- forceLocationManager만 문제(예: 일부 기기 GPS 끊김) → `git revert 33d7f9a` (워치독은 유지)
- 워치독만 문제(예: 주행 중 0 깜빡임) → `git revert d30e414` (연속수신은 유지)
- 두 커밋은 서로 독립 → 단독 revert로 원인 격리 가능.

## 막힌 점 / 미확인
- SPD 간격 5초→1초 전환 여부는 **실측 전까지 미확인.** forceLocationManager가 5초를 못 깨면(기기/ROM 종속) 보고 예정이나, 워치독은 그와 무관하게 고착을 차단함.
- 워치독 3초 임계는 ~1Hz 가정. 만약 fix가 여전히 5초 간격이면 정상 주행 중에도 워치독이 발동해 속도가 0으로 깜빡일 수 있음 → **이 경우 forceLocationManager가 1Hz를 확보하는 것이 전제.** 5초 고착이 안 풀리면 워치독 임계를 6초+로 올리는 후속 조정 필요(이번 턴 범위 밖).
