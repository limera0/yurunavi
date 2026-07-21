# RECON: GPS 주기 + 속도 재설계 재료

날짜: 2026-06-10  
브랜치: feat/maplibre-migration  
커밋 기준: 29acec3 (debug log revert)

---

## ★ 1순위 — 6~8초 주기 원인

### 현재 LocationSettings (nav_screen.dart lines 192-197)

```dart
_locationSub = Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    // intervalDuration: 없음 ← 원인
  ),
).listen(_onPosition);
```

`LocationSettings`(플랫폼 공통)를 사용하고 `AndroidSettings`(Android 전용)를 사용하지 않는다. Android FusedLocationProviderClient는 `intervalDuration`을 직접 받지 않으므로 기본값이 적용된다.

### 기본값 확인

```
// geolocator_android-5.0.2/lib/src/types/android_settings.dart:46
/// If this value is `null` an interval duration of 5000ms is applied.
final Duration? intervalDuration;
```

**`intervalDuration = null` → Android 기본 5000ms(5초) 적용.** FusedLocationProvider의 배터리 절약 휴리스틱까지 더해지면 실제 전달 주기 6~8초가 됨.

`distanceFilter: 0`은 "이동 거리 기준 필터링 없음"이지, 시간 주기를 당기지는 않는다.

---

## ★ 3Hz로 당기는 변경점

### 필요 변경

`LocationSettings` → `AndroidSettings`, `intervalDuration` 명시:

```dart
// import 불필요 — geolocator 14.0.2가 이미 re-export
// geolocator.dart:8-10: export 'package:geolocator_android/geolocator_android.dart'
//   show ..., AndroidSettings, ...

_locationSub = Geolocator.getPositionStream(
  locationSettings: AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    intervalDuration: const Duration(milliseconds: 333), // ~3Hz
  ),
).listen(_onPosition);
```

`geolocator: ^14.0.2` 이미 pubspec.yaml에 있으므로 dependency 추가 불필요.

**`const` 제거 필수**: `LocationSettings`는 const였지만 `AndroidSettings`는 const 불가 (foregroundNotificationConfig 등 non-const 필드).

---

## 2순위 — 속도 재설계 재료

### 현재 속도 계산 블록 (fix#3 후, lines 218-232)

```dart
// ① raw 도플러
final rawKmh = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed * 3.6;
// ② speedAccuracy 게이팅
final speedUnreliable = pos.speedAccuracy.isNaN || pos.speedAccuracy > 1.0;
// ③ clamped dead zone
final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0 || speedUnreliable) ? 0.0 : rawKmh;
// ④ 이동평균 3샘플
_speedBuffer.add(clamped);
if (_speedBuffer.length > _kBufSize) _speedBuffer.removeAt(0);
final avg = _speedBuffer.reduce((a, b) => a + b) / _speedBuffer.length;
// ⑤ 화면 바인딩
setState(() { _speedKmh = avg < 2.0 ? 0.0 : avg; });
```

`_speedKmh`는 화면 Text 위젯(속도계 표시) + `_recenter`의 `_zoomForSpeed` + bearing 회전 조건(`_speedKmh > 2.0`)에 바인딩.

### 현재 throttle

```dart
// 적응 갱신: ≤10 km/h → 2Hz(500ms), 나머지 → 1Hz(1000ms)
if (elapsedMs < intervalMs) { setState(() => _currentPos = loc); return; }
```

throttle early return이 speed 계산 전체를 건너뜀. 3Hz GPS로 전환하면 속도 계산이 실제로 2~3Hz로 동작하게 되므로 throttle 로직도 재검토 필요(또는 제거 후 매틱 갱신).

---

### 신규 필드 필요 목록

| 필드 | 타입 | 용도 | 현재 유무 |
|---|---|---|---|
| `_lastPos` | `LatLng?` | 이전 GPS 좌표 (델타 거리 계산) | **없음 — 신규** |
| `_lastPosAt` | `DateTime?` | 이전 이벤트 timestamp (dt 계산) | **없음 — 신규** |
| `_lastSpeedAt` | `DateTime?` | 적응 throttle | 있음 (재사용 or 폐기) |
| `_speedBuffer` | `List<double>` | 이동평균 | 있음 (유지) |

`pos.timestamp`: `DateTime`, required 필드 — 이벤트 자체의 타임스탬프. `DateTime.now()` 대신 `pos.timestamp`로 dt를 계산하면 수신 지연에 의한 오차 제거 가능.

---

### `Geolocator.distanceBetween` 가용성

```dart
// geolocator-14.0.2/lib/geolocator.dart:249
static double distanceBetween(double startLatitude, double startLongitude,
    double endLatitude, double endLongitude)
```

- haversine 구면 거리, 반환 단위 **미터**
- nav_screen에서 현재 미사용 (이탈 판정은 자체 `_segmentDistM` 사용)
- `import 'package:geolocator/geolocator.dart'`가 line 15에 이미 있으므로 즉시 호출 가능

---

### 정지 판정 설계 재료

GPS `accuracy` 필드 = 수평 정확도 반경(m). 두 연속 좌표 간 거리가 이 반경 이내면 "실제 이동 없음"으로 판단 가능.

```
dist = Geolocator.distanceBetween(_lastPos, currentPos)  // 미터
정지 조건: dist < pos.accuracy  (←  "오차 범위 내 흔들림")
```

실측 acc 5~7m → 5m 이내 이동은 정지 판정. 걷기(4~5 km/h, 3Hz 간격에서 0.44m/333ms)는 통과.

---

### 정지 판정 삽입 위치

현재 속도 계산 블록의 `clamped` 라인을 대체하는 형태로 삽입:

```dart
// 기존 clamped 라인 교체
final dist = _lastPos == null
    ? 0.0
    : Geolocator.distanceBetween(
        _lastPos!.latitude, _lastPos!.longitude,
        loc.latitude, loc.longitude);
final dtSec = _lastPosAt == null
    ? 0.0
    : pos.timestamp.difference(_lastPosAt!).inMilliseconds / 1000.0;
final deltaKmh = (dtSec > 0) ? (dist / dtSec) * 3.6 : 0.0;
final isStationary = dist < pos.accuracy;   // 정확도 반경 내 흔들림 → 정지
final clamped = (isStationary || pos.accuracy > 20.0) ? 0.0 : deltaKmh;

_lastPos = loc;          // 매 이벤트 갱신 (throttle 바깥으로 이동 필요)
_lastPosAt = pos.timestamp;
```

⚠️ `_lastPos`/`_lastPosAt` 갱신은 throttle early return **이전**에 해야 함. 안 그러면 긴 dt와 짧은 dist → 이상 저속 계산.

---

## 재설계 요약 (다음 실행 턴 입력용)

| 항목 | 변경 |
|---|---|
| GPS 주기 | `LocationSettings` → `AndroidSettings(intervalDuration: 333ms)` |
| 속도 소스 | `pos.speed` 도플러 폐기 → `Geolocator.distanceBetween` 좌표 델타 |
| 정지 판정 | `dist < pos.accuracy` → 0 (기존 rawKmh < 2.5 dead zone 병행 또는 대체) |
| dt 소스 | `DateTime.now()` → `pos.timestamp` 차이 |
| 신규 필드 | `LatLng? _lastPos`, `DateTime? _lastPosAt` |
| throttle | 매 이벤트 `_lastPos` 갱신 (throttle 밖) + 화면 갱신만 throttle (또는 제거) |
| speedAccuracy 게이팅 | 도플러 폐기하면 불필요 — 삭제 or `_kSpeedAccuracyMaxMs` 상수도 제거 |
| `_speedBuffer` | 유지 (델타 속도도 3샘플 평균으로 튐 완화) |
| `_kBufSize` | 유지 |
