# RECON — 출발 정확성 (Startup Accuracy)

## A. 초기 경로계산 시점

### A.1 `_kInitialMapView` in nav_screen.dart

`nav_screen.dart:28`
```dart
const LatLng _kInitialMapView = LatLng(37.5665, 126.9780);
```
Seoul/광화문 좌표. 상단 주석: "Camera-framing default only — never treated as the rider's location."

초기 카메라 위치는 `nav_screen.dart:832-835`:
```dart
initialCameraPosition: ml.CameraPosition(
  target: _toMl(_currentPos ?? _kInitialMapView),
  zoom: 15,
),
```
`_currentPos`가 null(GPS fix 없음)이면 서울 좌표로 카메라가 시작된다. flutter_map 오버레이도 동일 fallback 사용(`nav_screen.dart:850`).

### A.2 `kInitialMapView` in main_map_screen.dart

`main_map_screen.dart:35`
```dart
const LatLng kInitialMapView = LatLng(36.5, 127.5); // 한국 지리 중심 (서울 아님)
```
초기 줌 레벨: `main_map_screen.dart:117` — `double _currentZoom = 16.0;`
카메라 타겟: `main_map_screen.dart:795`
```dart
target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),
```
우선순위: 실GPS → 캐시위치 → 36.5/127.5.

### A.3 fetchRoutes 최초 호출 시점 및 origin

`fetchRoutes`는 `main_map_screen.dart:544`의 `_fetchAndStoreAllRoutes(origin, dest)` 에서만 호출된다.

이 함수는 3개 경로로 진입:

1. `_applyDestination` (`main_map_screen.dart:497-538`):
   - `final origin = _origin;` (line 498)
   - 가드: `if (origin == null) return;` (line 499)
   - `_origin`이 null이면 즉시 반환 → fetchRoutes 호출 없음

2. `_onMapTap` (`main_map_screen.dart:411-421`):
   - `final origin = _origin;` (line 412)
   - 가드: `if (origin == null)` → SnackBar "GPS 위치를 기다리는 중입니다…" 표시 후 return (line 413-420)

3. `_onRouteCardSelect` (`main_map_screen.dart:699-703`):
   - `final origin = _origin;` (line 699)
   - 가드: `if (origin == null || dest == null) return;` (line 701)

`_origin`이 설정되는 유일한 경로는 GPS 스트림 콜백 (`main_map_screen.dart:202`):
```dart
setState(() => _origin = loc);
```
`_lastKnown`(캐시 위치, line 185)는 `_origin`에 절대 대입되지 않는다.

**결론**: fetchRoutes는 항상 실제 GPS fix(`_origin`) 이후에 호출된다. Seoul fallback이나 캐시 위치는 fetchRoutes의 origin으로 사용되지 않는다. GPS fix 이전에 fetchRoutes를 호출하는 경로가 코드상 존재하지 않는다.

---

## B. 첫 GPS Fix 딜레이

### B.1 `_onPosition` 최초 호출 흐름 (nav_screen.dart:295)

`initState`(line 153)에서 `_initTts()`, `_applyRouteGuidance()` 실행 후 `_startLocation()`(line 162) 호출.

`_startLocation()`은 async이며 권한 체크 완료 전까지 실제로는 실행되지 않는다.

**GPS fix 이전 상태 처리** (`nav_screen.dart:199-220`):
```dart
// 1순위: currentLocationProvider (MainMapScreen이 이미 fix를 받은 경우)
final knownLoc = ref.read(currentLocationProvider);
if (knownLoc != null && mounted) {
  setState(() {
    _currentPos = knownLoc;
    _firstFixReceived = true;   // line 203 — "GPS 검색 중" UI 생략
  });
  ...
}

// 2순위: getLastKnownPosition() (캐시; _firstFixReceived는 NOT set)
if (knownLoc == null) {
  final last = await Geolocator.getLastKnownPosition();
  if (last != null && mounted && _currentPos == null) {
    setState(() => _currentPos = loc);  // line 214 — firstFixReceived 미설정
    ...
  }
}
```

NavScreen은 항상 MainMapScreen에서 GPS fix 후 라우팅을 마친 다음 진입하므로, `currentLocationProvider`에 이미 위치가 있어 1순위 경로로 `_firstFixReceived = true`가 즉시 설정되는 것이 정상 경로다.

`_onPosition`이 호출될 때마다 `_firstFixReceived = true`로 설정(`nav_screen.dart:315, 344`).

### B.2 `getPositionStream` 설정 (nav_screen.dart:222-233)

```dart
_locationSub = Geolocator.getPositionStream(
  locationSettings: AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    intervalDuration: const Duration(milliseconds: 1000), // 1Hz
    distanceFilter: 0,  // 모든 fix 수신
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: "유루나비 주행 중",
      ...
      enableWakeLock: true,
    ),
  ),
).listen(_onPosition);
```

### B.3 GPS fix 이전 표시 내용

- 속도계 위젯: `_firstFixReceived == false`이면 "GPS / 검색 중" blink 표시 (`nav_screen.dart:1173-1193`)
- `_cardRemainingM = 0.0` 초기값 (`nav_screen.dart:111`) — GPS tick 이전에는 카드 잔여거리 표시 없음
- `_announceStep(0)` 는 `step.dist`(정적 계획 거리)를 사용 → GPS 없이도 발화 가능

캐시 위치로 `_currentPos`가 설정된 경우 (`getLastKnownPosition`, line 211-218): `_firstFixReceived`가 false로 유지되므로 "GPS 검색 중" 표시가 계속되지만, 카메라는 캐시 위치로 이동한다.

---

## C. _announceStep off-by-one

### C.1 `_announceStep`이 사용하는 인덱스 (`nav_screen.dart:515-524`)

```dart
void _announceStep(int idx) {
  if (idx < 0 || idx >= _steps.length) return;
  if (idx == _lastAnnouncedIdx) return; // 중복 방지
  _lastAnnouncedIdx = idx;
  final step = _steps[idx];            // <-- _steps[idx] 직접 참조
  final text = step.dist.isNotEmpty
      ? '${step.dist} 앞 ${step.label}'
      : step.label;
  _tts?.speak(text);
}
```

`_steps[idx]` — 전달된 인덱스의 step 그대로 사용. `_stepIdx+1`(upcoming)이 아니다.

호출 경로:
- `_initTts` (`nav_screen.dart:512`): `_announceStep(0)` → step 0(출발 maneuver) 발화
- `_updateStepByDistance` (`nav_screen.dart:433`): `setState(() => _stepIdx++)` 후 `_announceStep(_stepIdx)` → 진입한 새 step 발화

### C.2 출발 step(type==1) 특별 처리 여부

없음. `_announceStep`에는 type 분기가 없다.

출발 maneuver (`_TurnStep.fromManeuver`, line 1230-1237): `dist = _formatDist(m.distanceKm)` — Valhalla가 출발 레그에 부여한 거리. `_formatDist` (`nav_screen.dart:1285-1289`): km > 0이면 "Xm" 또는 "X.Xkm" 반환.

결과: 출발 maneuver의 `distanceKm > 0`이면 `_announceStep(0)`은 "Xm 앞 출발"을 발화한다. "출발합니다" 혹은 "안내를 시작합니다" 같은 별도 분기가 없다.

### C.3 `remaining` 변수 및 400m lookahead (`nav_screen.dart:411, 421`)

```dart
// line 411
final remaining = (stepEnd - traveled).clamp(0.0, double.maxFinite);

// line 421-427 — 400m 예비 발화
if (remaining < 400 && !_preAnnounced && _stepIdx + 1 < _steps.length) {
  _preAnnounced = true;
  final next = _steps[_stepIdx + 1];          // 다음 step(upcoming)
  final distStr = '${remaining.toStringAsFixed(0)}미터 앞';  // 실시간 잔여거리
  _tts?.speak('$distStr ${next.label}');
}
```

`remaining` = 현 step 종점까지 실시간 GPS 잔여거리(m). 400m lookahead는 `_steps[_stepIdx + 1]`(다음 step)을 `remaining`(실측)과 함께 발화 — 정상.

### C.4 `_announceStep`의 거리: 정적 vs 실측

`_announceStep`은 `step.dist`를 사용한다 (`nav_screen.dart:520-521`):
```dart
final text = step.dist.isNotEmpty
    ? '${step.dist} 앞 ${step.label}'
    : step.label;
```

`step.dist` = `_formatDist(m.distanceKm)` = Valhalla 경로 계획 시 부여된 **정적** 거리 (`_TurnStep.fromManeuver`, line 1234).

step 진입 시(`_stepIdx++` 후) `_announceStep` 호출 시점에서 사용자는 이미 이전 step 종점에 도달(50m 이내)한 상태이므로 `step.dist`(해당 step의 전체 계획 거리)가 실제 잔여거리와 일치한다고 볼 수 있다. 그러나 "Xm 앞 출발" 경우에는 의미상 어색하다.

UI 카드는 다르다 (`nav_screen.dart:965-969`): `_cardRemainingM > 0`이면 실시간 거리 `_TurnStep._formatDist(_cardRemainingM / 1000.0)` 표시, 아니면 `step.dist` 폴백. 카드가 보여주는 step은 `upcoming` = `_steps[_stepIdx + 1]`이다 (`nav_screen.dart:798`).

---

## 판정

**N** — 두 가지 모두 "GPS fix 이전 경로계산"에서 비롯된 것이 아니다.

**Slide 1 (Seoul fallback)**:
Seoul 좌표(`_kInitialMapView = LatLng(37.5665, 126.9780)`)는 NavScreen MapLibre 지도의 `initialCameraPosition` fallback으로만 사용된다(`nav_screen.dart:833`). fetchRoutes는 이 좌표와 무관하다. 경로 계산에 Seoul 좌표가 origin으로 쓰이는 경로는 코드에 없다. 실제 문제는 경로 계산이 아니라 NavScreen 첫 build 시 `_currentPos`가 아직 async로 설정되기 전에 카메라가 서울을 잠시 가리키는 UI 타이밍 문제다. (단, MainMapScreen에서 이미 GPS fix가 있었다면 `currentLocationProvider`를 통해 즉시 `_currentPos`가 설정되므로 이 flicker가 거의 발생하지 않는 정상 경로가 존재한다.)

**Slide 3 (wrong distance)**:
`_announceStep`이 `step.dist`(Valhalla 계획 거리, 정적)를 사용하는 것은 맞지만, 이 계획 거리는 실제 GPS 위치(`_origin`)로 계산된 것이다. GPS fix 이전 계산값이 아니다. 문제는 출발 step(type 1)에 대한 특별 분기가 없어 "Xm 앞 출발" 형태의 어색한 발화가 나온다는 점이며, 이것은 GPS 타이밍 문제가 아니라 `_announceStep` 로직 자체의 설계 문제(출발 maneuver 처리 미흡)다.

**근본 원인 정리**:
- Seoul 카메라 flicker → NavScreen `_startLocation()` async 완료 전 첫 build 타이밍 (실제 GPS는 있음)
- 출발 발화 "Xm 앞 출발" → `_announceStep`에 type==1 분기 없음
- 400m/50m 거리 발화 → 정상 (실측 `remaining` 사용, `_steps[_stepIdx+1]` 정확히 지정)
