# RECON: nav_screen 카메라 이동 불능 원인 격리

날짜: 2026-06-09  
브랜치: feat/maplibre-migration  
커밋 기준: 0f2672f (커밋 ① + 핫픽스)

---

## 1. _onPosition 카메라 이동 경로

```
_onPosition(pos)                                    // GPS 이벤트
  └─ if (!_isManualMode) _recenter(loc)             // line 184 — 항상 호출 (수동모드 아닐 때)
       └─ if (!_styleLoaded) return                 // line 516 — 가드 ①
          _programmaticCamera = true                // line 521
          cf = _mlCtrl?.animateCamera(...)          // line 522
          cf?.then(() => _programmaticCamera=false) // line 523 — 비동기 리셋
  └─ if (elapsedMs < intervalMs) → early return     // line 193-196
  └─ heading rotation (speed > 2 km/h && _styleLoaded) // line 215
       └─ _programmaticCamera = true
          bf = _mlCtrl?.animateCamera(bearingTo)
          bf?.then(() => _programmaticCamera=false)
```

**가드 ①** (`_styleLoaded`): 스타일 로드 전에는 `_recenter` 즉시 반환. GPS 이벤트가 스타일 로드보다 먼저 오면 초기 몇 번의 이벤트는 no-op. 단 `distanceFilter: 0`이므로 스타일 로드 직후 다음 GPS 이벤트에서 카메라 이동 시작. **영구 차단 아님.**

**`_mlCtrl` null 여부**: `onMapCreated: (c) => _mlCtrl = c` — MapLibre 위젯 생성 직후 할당. 스타일 로드 이후에는 항상 non-null. `_styleLoaded = true` 시점에는 반드시 `_mlCtrl != null`. 문제 없음.

---

## 2. 재중심 버튼 추적

```dart
// lines 788-794
onTap: () {
    final pos = _currentPos;
    if (pos == null) return;       // null이면 무동작
    _recenterTimer?.cancel();
    setState(() => _isManualMode = false);
    _recenter(pos);                // _styleLoaded, _mlCtrl 모두 충족 시 animateCamera 호출
},
```

`_mapCtrl` 잔존 참조: **없음** (아래 grep 결과):

```
grep -n "_mapCtrl" lib/features/navigation/presentation/nav_screen.dart
→ (출력 없음 — 구 컨트롤러 참조 완전 제거됨)
```

버튼 로직 자체는 올바름. 그러나 → **가장 유력한 원인 참조**.

---

## 3. 초기 카메라 위치

```dart
// nav_screen.dart line 565-568
initialCameraPosition: ml.CameraPosition(
    target: _toMl(_currentPos ?? _kInitialMapView),  // _currentPos = null (초기)
    zoom: 15,
),
// _kInitialMapView = LatLng(37.5665, 126.9780)  // 서울
```

`_currentPos`는 `initState` 시점에 `null` → 카메라 초기값은 서울.

**main_map_screen 대조**:
```dart
// main_map_screen.dart lines 162-172
final last = await Geolocator.getLastKnownPosition();  // ← 캐시된 마지막 위치 즉시 스냅
if (last != null) {
    _mlCtrl?.animateCamera(CameraUpdate.newLatLngZoom(_toMl(loc), ...));
}
```

**nav_screen에는 `getLastKnownPosition()` 호출이 없다.** 앱 실행 → 내비 진입 시 항상 서울에서 시작. 첫 GPS 이벤트 수신 + 스타일 로드 완료 전까지 카메라 이동 없음. (transient, 보통 1~3초)

---

## 4. 가장 유력한 원인: `_programmaticCamera` + `onCameraMove` 레이스 컨디션

### 원인 분석

nav_screen 커밋 ①은 아래 패턴으로 수동조작을 감지한다:

```dart
// MapLibreMap 위젯
onCameraMove: (_) {
    if (!_programmaticCamera) _onMapGesture();   // line 574-575
},

// _recenter / bearing rotation
_programmaticCamera = true;
final cf = _mlCtrl?.animateCamera(...);          // 애니메이션 시작
cf?.then((_) { _programmaticCamera = false; }); // 비동기 리셋
```

### Dart 이벤트 루프에서의 레이스

| 순서 | 이벤트 | `_programmaticCamera` |
|---|---|---|
| 1 | `animateCamera()` 호출 | `true` (동기 설정) |
| 2 | 애니메이션 진행 중 `onCameraMove` × N | `true` → `_onMapGesture` 차단 ✅ |
| 3 | 애니메이션 완료 → Future resolved | `true` |
| 4 | `.then()` **마이크로태스크** 실행 | `false` ← **여기서 리셋** |
| 5 | 플랫폼 채널: 최종 위치의 `onCameraMove` **이벤트** | `false` → `_onMapGesture()` 호출! ❌ |

Dart 이벤트 루프에서 **마이크로태스크(`.then()`)는 이벤트(플랫폼 채널)보다 먼저 실행된다.** MapLibre 네이티브가 애니메이션 완료 알림과 함께 최종 위치의 카메라 이동 이벤트를 별도로 보내면, `.then()`이 먼저 실행되어 `_programmaticCamera = false`가 된 뒤 `onCameraMove`가 도착한다.

실제 MapLibreMapController:
```dart
// controller.dart:185, 190-192
_maplibrePlatform.onCameraMoveStartedPlatform.add((_) { ... });
_maplibrePlatform.onCameraMovePlatform.add((cameraPosition) {
    _cameraPosition = cameraPosition;
    onCameraMove?.call(cameraPosition);  // ← 이 콜백이 문제
});
```

### 결과

1. `_recenter(loc)` 호출 → `animateCamera` → 완료 → `.then()` → `_programmaticCamera = false` → **최종 `onCameraMove` 도착** → `_onMapGesture()` → `_isManualMode = true` + 10초 타이머 시작
2. 이후 10초 동안: GPS `_onPosition` → `if (!_isManualMode) _recenter(loc)` → `_isManualMode = true`이므로 **skip** → 카메라 이동 없음
3. 10초 후: 타이머가 `_isManualMode = false`, `_recenter(pos)` 호출 → 1번으로 반복
4. **재중심 버튼**: 버튼 탭 → `_recenter` → 카메라 스냅 → `onCameraMove` → `_onMapGesture()` → `_isManualMode = true` 즉시 재설정. 사용자 입장에서 "버튼이 안 먹음"으로 보임.

---

## 5. main_map_screen 대조 — 정상 동작 이유

main_map_screen의 MapLibreMap에는 **`onCameraMove` 콜백이 없다**:
```dart
// main_map_screen.dart lines 775-802
onMapCreated: (c) => _mlCtrl = c,
onStyleLoadedCallback: () async { ... },
onMapClick: ...,
onCameraIdle: () { ... },  // zoom 값 읽기용만
// onCameraMove: 없음
```

- `_programmaticCamera` 플래그 없음
- `_isManualMode` 개념 없음
- `animateCamera` 호출에 어떤 가드도 없이 직접 호출

main_map_screen이 정상 동작하는 이유: `onCameraMove` 자체를 사용하지 않으므로 레이스 컨디션 발생 불가.

---

## 6. 요약

| 항목 | 상태 | 원인 |
|---|---|---|
| (a) 내 위치 마커 미표시 | 예상된 동작 | 커밋 ③ 미완 (Circle 마커). 임시 FlutterMap 오버레이는 MapLibre 카메라와 동기화 안 됨 |
| (b) 재중심 버튼 무동작 | ✅ **원인 확정** | `_programmaticCamera` 레이스 → `_isManualMode = true` 즉시 재설정 |
| (c) 서울 고정 카메라 | ✅ **원인 확정** | 동일 레이스 + `getLastKnownPosition()` 없음 |

**가장 유력한 원인 (단 1개)**:

> `_programmaticCamera` 플래그 리셋(`.then()` 마이크로태스크)이 MapLibre의 최종 `onCameraMove` 플랫폼 이벤트보다 먼저 실행되어, 모든 프로그래매틱 카메라 이동이 `_onMapGesture()` → `_isManualMode = true`를 유발한다. 10초 타이머 반복으로 카메라가 사실상 GPS를 추적하지 못한다.

---

## 수정 방향 (다음 실행 턴에서 적용)

**A안 (권장)**: `onCameraMove` 대신 `onCameraIdle` + 사용자 제스처 감지에 `GestureDetector` 래핑 조합. MapLibre는 애니메이션 완료 후 `onCameraIdle`만 발생시키므로, `_programmaticCamera` 플래그 없이 안정적으로 수동 조작 감지 가능.

**B안 (간단)**: `_programmaticCamera` 플래그 전체 제거 + `onCameraMove` 제거. `_onMapGesture`를 MapLibreMap 위에 `GestureDetector(onPanStart, onScaleStart)`로 대체. 사용자 터치 시작 시 `_isManualMode = true`, 터치 종료 후 10초 타이머.

**C안 (최소 수정)**: `.then()` 대신 약간의 딜레이를 두고 `_programmaticCamera = false` 리셋. `Future.delayed(const Duration(milliseconds: 200), () => _programmaticCamera = false)`. 애니메이션 완료 후 200ms 뒤 리셋하여 최종 `onCameraMove`가 먼저 처리되도록.
