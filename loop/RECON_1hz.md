# RECON-1hz — 1Hz 요청이 5초 간격으로 전달되는 원인 규명

작성: 2026-06-17

---

## 결론 요약

**5초 간격의 원인: geolocator_android 싱글턴 스트림 캐시**

`GeolocatorAndroid.getPositionStream()` 은 `_positionStream` 를 인스턴스 변수로 캐시한다.
`main_map_screen` 이 먼저 스트림을 만들면, `nav_screen` 의 `AndroidSettings(intervalDuration: 1000ms)` 는
**완전히 무시되고** 기존 5초 스트림을 돌려받는다.

---

## 증거 추적 (file:line)

### 1. geolocator_android 싱글턴 캐시

```
~/.pub-cache/.../geolocator_android-5.0.2/lib/src/geolocator_android.dart:35
  Stream<Position>? _positionStream;

:166–205  getPositionStream() {
    if (_positionStream != null) {          // ← 이미 있으면 settings 무시하고 반환
      return _positionStream!;
    }
    var originalStream = _eventChannel.receiveBroadcastStream(
      locationSettings?.toJson(),           // ← 첫 호출의 settings만 Android로 전달
    );
    ...
    _positionStream = positionStream...;    // ← 캐시에 저장
    return _positionStream!;
  }
```

`_positionStream` 은 마지막 구독자가 취소할 때 `onCancel` 에서만 `null` 로 리셋된다 (:208–211).
두 화면이 동시에 구독 중이면 스트림은 교체되지 않는다.

### 2. main_map_screen 가 먼저 스트림을 생성 (5초 기본값)

```
lib/features/map/presentation/main_map_screen.dart:135
  initState() → _startLocationTracking()   // 앱 진입 시 즉시 실행

:193–197  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,             // intervalDuration 없음
    ),
  )
```

`LocationSettings.toJson()` 은 `{accuracy, distanceFilter}` 만 직렬화한다.
`timeInterval` 키가 없으면 Android 측에서 기본값 **5000 ms** 를 적용한다.

근거: `android_settings.dart` 주석: _"If this value is `null` an interval duration of 5000ms is applied."_

### 3. nav_screen 의 AndroidSettings 가 무시됨

```
lib/features/navigation/presentation/nav_screen.dart:232–243
  _locationSub = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      intervalDuration: const Duration(milliseconds: 1000),   // ← 무시됨
      distanceFilter: 0,
      foregroundNotificationConfig: ForegroundNotificationConfig(...),
    ),
  ).listen(_onPosition);
```

호출 시점: `_startNavigation()` → `Navigator.push(NavScreen)` → `initState()` → `_startLocation()`

이때 `main_map_screen` 은 dispose 되지 않는다(`Navigator.push` 는 이전 라우트를 스택에 유지).
`_positionStream != null` 이므로 `receiveBroadcastStream()` 이 재호출되지 않고,
Android 에 새 `LocationRequest` 가 전달되지 않는다.

### 4. _onPosition 콜백 간격 5초 확인 경로

```
nav_screen.dart:305  _onPosition(Position pos) { ... }
```

이 콜백은 5초 스트림에서 이벤트를 받는다 → 실측 fixrate.txt 의 ~5000ms 일치.

---

## 스트림 동시 활성 여부

| 화면 | 스트림 생성 시점 | dispose 시점 | NavScreen 진입 시 상태 |
|------|--------------|------------|----------------------|
| main_map_screen | `initState()` | 라우트 pop 시 | **살아 있음** (push → keep-alive) |
| nav_screen | `_startLocation()` | `dispose()` | 캐시된 5초 스트림 공유 |

---

## 수정 방향 (RECON 범위, 코드 변경 없음)

### 옵션 A (즉효, 단기): main_map_screen에서 NavScreen 진입 직전 구독 해제

```dart
// main_map_screen.dart _startNavigation()
_locationSub?.cancel();   // ← 삽입
_locationSub = null;
Navigator.of(context).push(MaterialPageRoute(builder: (_) => NavScreen(...))).then((_) {
  if (mounted) {
    _clearDestination();
    _startLocationTracking();  // ← 복귀 시 재구독
  }
});
```

효과: nav_screen 진입 시 `_positionStream == null` → `AndroidSettings(1000ms)` 로 새 스트림 생성.
`main_map_screen.dispose()` 의 `_locationSub?.cancel()` 이 null 을 취소하므로 문제 없음.

주의: pop 후 main_map_screen 이 GPS 스트림을 재시작해야 한다.

### 옵션 B (근본): LOC-UNIFY — 단일 위치 소스 Provider

SPEC_location.md 에서 설계 중. `getPositionStream` 호출처를 1곳으로 통합하면
이 캐시 충돌은 구조적으로 제거된다.
선행조건: INSTR-fixrate 라이딩 결과 → 워밍업 `LocationSettings` 값 확정.

**권장: 옵션 A 로 즉시 수정 후 → 옵션 B 로 통합 (순서 유지)**

---

## §미확정 없음 — 수용기준

- [x] 5초를 만드는 정확한 file:line 특정 → `geolocator_android.dart:169–171` (캐시 반환)
- [x] 첫 스트림 settings: `main_map_screen.dart:193–197` (distanceFilter:10, timeInterval:null → 5000ms)
- [x] AndroidSettings 무시 경로: `nav_screen.dart:232–243` (캐시 히트로 버려짐)
- [x] 동시 활성 확인: main_map_screen dispose 없이 스택에 잔류
- [x] 수정 방향 제시
