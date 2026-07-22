# RECON_MARKER (B1+B2 마커)

## A. 브랜치/작업트리 상태
- 브랜치: `feat/maplibre-migration`
- Untracked: `REPORT_ZOOM.md` (1개) — 작업트리 클린

## B. MapLibre 패키지 (이름 + 정확한 버전)
- `maplibre_gl: 0.26.1` (pub.dev, sha256: 3c383a7e...)
- 전이 의존: `maplibre_gl_platform_interface: 0.26.1`, `maplibre_gl_web: 0.26.1`
- 캐시 경로: `~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.1/`

## C. 사용 가능한 마커 API (실파일 경로+라인 근거 첨부)

### addSymbol/addCircle 계열 가능 여부: **YES — 둘 다 가능**
- `controller.dart:1123` → `Future<Symbol> addSymbol(SymbolOptions options, [Map? data])`
- `controller.dart:1346` → `Future<Circle> addCircle(CircleOptions options, [Map? data])`
- `controller.dart:1394` → `Future<void> updateCircle(Circle circle, CircleOptions changes)` (위치 업데이트용)

### addImage 시그니처 (심볼 아이콘용):
- `controller.dart:1656` → `Future<void> addImage(String name, Uint8List bytes, [bool sdf = false])`
  - `name`: 스타일 내 참조 이름, `bytes`: PNG 바이트, `sdf=true`면 색상 재지정 가능

### CircleOptions 필드 (platform_interface/lib/src/circle.dart 실 확인):
```dart
const CircleOptions({
  double? circleRadius,      // 픽셀 단위 반지름
  String? circleColor,       // "#RRGGBB" 또는 "rgba(r,g,b,a)"
  double? circleBlur,
  double? circleOpacity,
  double? circleStrokeWidth,
  String? circleStrokeColor,
  double? circleStrokeOpacity,
  LatLng? geometry,          // 위치 (필수)
  bool? draggable,
})
```

### 레이어/소스 계열도 가능 여부: YES
- `controller.dart:446` → `addGeoJsonSource`, `controller.dart:611` → `addSymbolLayer`, `controller.dart:801` → `addCircleLayer`
- annotation_manager.dart도 내부적으로 GeoJsonSource+Layer 방식 사용

## D. main_map_screen.dart 핵심 지점

### 컨트롤러 변수명/타입:
- `_mlCtrl` (line 80): `ml.MapLibreMapController?`
- 선언: `ml.MapLibreMapController? _mlCtrl;` (line 80)

### 스타일 로드 완료 콜백 위치 (여기서만 레이어/마커 추가 가능):
- `onStyleLoadedCallback: () async { ... }` — line **682~689**
- `_styleLoaded = true` 세팅 (line 683), `_initRouteLayer()` 호출 (line 684)
- **마커/소스/레이어 추가는 반드시 이 콜백 내부 또는 `_styleLoaded == true` 확인 후에만**

### 현위치 값 보관 변수 + 갱신되는 지점:
- `_lastKnown` (line 94): `LatLng?` — `getLastKnownPosition()` 결과 (빠른 초기값)
  - 갱신: line 159, `setState(() => _lastKnown = loc)` — `_initLocation()` 내부
- `_origin` (line 93): `LatLng?` — GPS 스트림 실시간 값
  - 갱신: line 175, `setState(() => _origin = loc)` — `_locationSub.listen()` 내부
- **현위치 마커는 `_origin`(또는 초기엔 `_lastKnown`) 기준으로 관리**

### 목적지 탭 핸들러 위치 + 목적지 좌표 보관 변수:
- 탭 핸들러: `_onMapTap(TapPosition _, LatLng tapped)` — line **311**
  - `onMapClick` 연결: line 690 (`onMapClick: (point, latLng) { _onMapTap(...) }`)
- 목적지 좌표 보관:
  - `_touchPoint` (line 110): `LatLng?` — 탭 좌표 (setState로 갱신, line 348)
  - `ref.read(mapInteractionProvider).destination` — provider 상태 (앱 전체 공유)
  - `_applyDestination(tapped)` (line 398): 실제 destination 설정 진입점

### _clearDestination 위치 (목적지 마커 제거 훅):
- line **532**: `void _clearDestination()`
- 내부: `ref.read(mapInteractionProvider.notifier).reset()`, `setState(() { _touchPoint = null; })`
- **목적지 마커 제거 코드는 여기에 추가하면 됨**

### _updateRouteLayer가 쓰는 source/layer id 목록:
- `_routeSourceId = 'route-source'` (line 83)
- `_routeLayerId = 'route-layer'` (line 84)
- `_routeBgSourceId = 'route-bg-source'` (line 85)
- `_routeBgLayerId = 'route-bg-layer'` (line 86)
- **마커용 id는 이와 충돌하지 않게 별도 명명 필요** (예: `'marker-location'`, `'marker-dest'`)

## E. 기존 마커/심볼 코드 유무
- `grep -rn "addSymbol\|addCircle\|addImage\|SymbolOptions\|CircleOptions\|SymbolLayer\|CircleLayer" lib/` → **출력 없음**
- 결론: **현재 lib/ 내 마커 코드 전무. 새로 추가해야 함.**

## F. 마커 아이콘 에셋 유무
- pubspec.yaml assets 선언: `assets/images/` 폴더 전체
- `ls -R assets | grep -iE "marker|pin|anchor|location"` → **"no marker asset found"**
- 결론: **마커 PNG/SVG 에셋 없음. addCircle 방식이면 에셋 불필요.**

## G. 결론 (정찰자 판단)

### 권장 구현 경로 한 줄:
**`addCircle` 단순 방식** — 에셋 불필요, PNG 없이 즉시 구현 가능, `circleColor`로 초록/빨강 지정, `updateCircle`로 위치 업데이트 가능. `circleStrokeWidth`+`circleStrokeColor`로 앵커 외곽선 표현. controller.dart:1346 실 확인.

### 현위치 마커 업데이트 전략:
- **1회 생성 후 `updateCircle`로 위치 업데이트** 권장
- 근거: `updateCircle(circle, CircleOptions(geometry: newLatLng))` 시그니처 존재 (controller.dart:1394). 매번 재생성(removeCircle+addCircle)보다 효율적. GPS 스트림이 `distanceFilter: 10`(10m)마다 발생하므로 업데이트 빈도 낮음.
- 단, **스타일 로드 전 GPS 픽스 도착 가능** → `_styleLoaded` 플래그로 가드 필요. 로드 완료 시 `_origin`이 이미 있으면 그 시점에 마커 생성.

### 미확인·리스크 항목 (다음 실행 턴에서 먼저 풀어야 할 것):
1. **`_initRouteLayer()` 내부 흐름** — `addCircle`이 `_initRouteLayer()`와 같은 `onStyleLoadedCallback`에서 await 순서가 중요. `addGeoJsonSource` 완료 후 circle 추가해야 레이어 순서 보장 (route 위에 마커가 그려지려면 circle이 나중에 추가되어야 함).
2. **`removeCircle` 시그니처** — `_clearDestination`에서 목적지 마커 제거 시 필요. controller.dart에 있을 것으로 추정되나 실 라인 미확인.
3. **`LatLng` import 충돌** — `main_map_screen.dart`는 `latlong2.LatLng`와 `ml.LatLng` 두 개 혼용 중. `CircleOptions(geometry:)`에는 `ml.LatLng` (platform_interface의 LatLng) 필요. `_toMl()` 헬퍼(line 89) 사용 여부 확인 필요.
4. **`_showCourseSheet` 상태 관리** — 목적지 마커는 `_touchPoint != null` 조건과 연동돼야 함. `_clearDestination`이 `_touchPoint = null`을 세팅하므로 마커 제거도 여기서 처리.
