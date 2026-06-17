# RECON-location — 위치 업데이트 빈도 진단

작성: 2026-06-17

---

## §A 패키지

`pubspec.yaml:20`
```
geolocator: ^14.0.2
```
`location` 패키지는 미사용. geolocator 단일.

---

## §B LocationSettings 전수 (file:line)

### 1. nav_screen.dart — 내비게이션 주행 화면 (핵심)

`lib/features/navigation/presentation/nav_screen.dart:232-243`
```dart
_locationSub = Geolocator.getPositionStream(
  locationSettings: AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    intervalDuration: const Duration(milliseconds: 1000),  // 1Hz 요청
    distanceFilter: 0,                                      // 거리 필터 없음
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: "유루나비 주행 중",
      notificationText: "경로 안내를 위해 위치를 수신하고 있습니다",
      enableWakeLock: true,
    ),
  ),
).listen(_onPosition);
```

- `AndroidSettings`를 명시적으로 사용 → iOS/기타는 미고려 (현재 Android 전용)
- `distanceFilter: 0` → 이동 거리와 무관하게 모든 fix 수신
- `intervalDuration: 1000ms` = **OS에 1Hz 요청**. 단, Android OS는 보장하지 않음.

### 2. main_map_screen.dart — 지도 화면 (비주행)

`lib/features/map/presentation/main_map_screen.dart:193-197`
```dart
Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,   // 10m 미만 이동 시 업데이트 없음
    // intervalDuration: 미지정 → OS 기본값
  ),
)
```

- `intervalDuration` 미지정 → Android 기본값(보통 수 초)
- `distanceFilter: 10m` → 정차·저속 시 업데이트 없음

### 3. driving_screen.dart — (레거시/비활성?)

`lib/screens/driving_screen.dart:97-101`
```dart
Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 5,    // 5m 미만 이동 시 업데이트 없음
    // intervalDuration: 미지정
  ),
)
```

- `intervalDuration` 미지정, `distanceFilter: 5m`
- 현재 활성 주행 화면이 nav_screen인지 driving_screen인지 확인 필요
  (git log상 nav_screen이 최신 주행 화면이므로 driving_screen은 구버전 추정)

---

## §C 위치 소비 경로 (nav_screen 내)

```
GPS fix 수신 (nav_screen.dart:243)
    ↓ .listen(_onPosition)
_onPosition(pos) [nav_screen.dart:305]
    │
    ├─ currentLocationProvider 갱신 (Riverpod) [line 307]
    ├─ 지도 자동 재중앙 (line 308)
    ├─ ZUPT 링버퍼 push + 12초 초과 제거 [line 313-314]
    │
    ├─ [적응 throttle gate] [line 316-329]
    │   ├─ ≤10 km/h → 500ms(2Hz) 이내 fix → UI만 갱신 후 return (도플러 처리 생략)
    │   └─ >10 km/h → 1000ms(1Hz) 이내 fix → 동일하게 return
    │
    └─ throttle 통과 시 도플러+ZUPT 처리
        ├─ GPS speed 도플러 속도 산출 [line 333]
        ├─ _calcParkState() 호출 [line 335]
        ├─ _moving 히스테리시스 갱신 [line 337-343]
        ├─ 외삽 ticker용 fix 보관 [line 347-348]
        ├─ setState (속도·위치) [line 351-355]
        ├─ heading 기반 지도 회전 [line 364]
        ├─ 경로 이탈 감지 + 재탐색 디바운스 [line ~370]
        └─ 안내 카드 거리 갱신 [line ~371]

별도 루프: _speedTicker (200ms 주기) [line 247]
    → _tickSpeed() [line 252-303]
       └─ 직전 2 fix 선형 외삽 → setState(_speedKmh)
          가드: fix 간격 >6500ms 외삽 OFF / GPS 점프 >150m 외삽 OFF
```

---

## §D _calcParkState 함수

`lib/features/navigation/presentation/nav_screen.dart:615-628`

```dart
({bool parked, double bufRadius, double parkThresh}) _calcParkState() {
  if (_posBuffer.length < 3) return (parked: false, bufRadius: 0.0, parkThresh: 6.0);
  // 중심점(cLat, cLon) 계산
  final bufRadius = 최대 거리;
  final medAcc = 정확도 중앙값;
  final parkThresh = max(6.0, 1.2 * medAcc);
  return (parked: bufRadius < parkThresh, ...);
}
```

- 호출 위치 1: `line 269` — `_tickSpeed()` 내 (fix 1500ms 미수신 시 빠른 정차 표시)
- 호출 위치 2: `line 335` — `_onPosition()` 내 도플러 처리 후 정차 판정
- `_posBuffer`: 최근 12초 GPS fix 기록 (`line 314`)
- 판정 조건: fix 3개 이상 & `bufRadius < max(6m, 1.2 × 정확도 중앙값)`

---

## §E "5초 갱신" 진단

BACKLOG가 언급한 "5초 갱신" 체감의 원인 후보:

| 후보 | 근거 | 가능성 |
|------|------|--------|
| Android OS 전력 관리 | intervalDuration은 **요청**이지 보장이 아님. Doze/배터리 절약 모드에서 OS가 임의로 5초 이상으로 늘림 | ★★★ 유력 |
| 적응 throttle 오인식 | `_speedKmh` 계산 지연으로 10km/h 판정이 늦어지면 UI 갱신이 500ms~1Hz 사이를 오감 | ★★ 가능 |
| driving_screen 잔존 | 만약 구 화면이 아직 살아있으면 `distanceFilter:5m`+intervalDuration 미지정이 5초 체감 유발 | ★ 낮음 |
| ZUPT 링버퍼 주석 | `nav_screen.dart:74` 주석 "1Hz·5초 fix 양쪽 호환" — 이는 코드 설명이지 설정값이 아님 | (근거 아님) |

**코드에 "5초" 타이머 설정값은 존재하지 않는다.** 현재 GPS 요청은 1Hz(1000ms)가 맞다.

---

## §F 1Hz로 "확실히" 올리려면

현재 nav_screen은 이미 `intervalDuration: 1000ms` (1Hz 요청)이다.  
OS 보장을 위한 추가 조치:

1. **`foregroundServiceType` 명시** — Android 매니페스트에 `location` 타입 포그라운드 서비스 추가 (이미 ForegroundNotificationConfig 있음, 매니페스트 확인 필요)
2. **`enableWakeLock: true` 확인** — `nav_screen.dart:240` 이미 설정됨
3. **Doze 모드 예외** — 앱을 배터리 최적화 제외 목록에 넣도록 사용자 안내 또는 코드로 요청
4. **main_map_screen `intervalDuration` 추가** — 비주행 화면에서도 OS 기본값 대신 명시
   - `main_map_screen.dart:193`: `intervalDuration: const Duration(seconds: 1)` 추가

적응 throttle을 고속에서도 2Hz로 올리려면:  
`nav_screen.dart:317`: `final intervalMs = 500;` (고정 500ms)

---

## §G 요약 표

| 항목 | 파일 | 줄 | 현재값 | 비고 |
|------|------|-----|--------|------|
| GPS 스트림 주기 | nav_screen.dart | 235 | `intervalDuration: 1000ms` | 1Hz 요청 (OS 보장 아님) |
| GPS 거리 필터 | nav_screen.dart | 236 | `distanceFilter: 0` | 모든 fix 수신 |
| GPS 정확도 | nav_screen.dart | 234 | `bestForNavigation` | 최고 정확도 |
| Wake lock | nav_screen.dart | 240 | `enableWakeLock: true` | 포그라운드 고정 |
| UI 갱신 적응 | nav_screen.dart | 317 | `≤10km/h→500ms, 나머지→1000ms` | throttle 로직 |
| 속도 외삽 ticker | nav_screen.dart | 247 | 200ms | fix 사이 보간 |
| ZUPT 버퍼 윈도우 | nav_screen.dart | 314 | 12초 초과 제거 | 정차 판정 데이터 |
| 정차 판정 | nav_screen.dart | 615-628 | `bufRadius < max(6m, 1.2×acc)` | _calcParkState |
| 지도화면 GPS 주기 | main_map_screen.dart | 193 | intervalDuration 미지정 | OS 기본값(수 초) |
| 레거시 화면 | driving_screen.dart | 97 | distanceFilter: 5m, 주기 미지정 | 비활성 추정 |
