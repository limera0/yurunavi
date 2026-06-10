# RECON: nav_screen MapLibre 이관 정찰

날짜: 2026-06-09  
브랜치: feat/maplibre-migration  
대상: lib/features/navigation/presentation/nav_screen.dart (982줄)  
레퍼런스: lib/features/map/presentation/main_map_screen.dart (1814줄, MapLibre 이관 완료)

---

## 조사 A — 레퍼런스 (main_map_screen.dart) 검증된 패턴

### A1. MapLibreMap 위젯 생성 (lines 764-802)

```dart
// import: package:maplibre_gl/maplibre_gl.dart as ml
ml.MapLibreMap(
  styleString: 'assets/images/osm_liberty_yurunavi.json',  // asset 상대경로
  initialCameraPosition: ml.CameraPosition(
    target: _toMl(_origin ?? _lastKnown ?? kInitialMapView),
    zoom: _currentZoom,                  // double (초기 16.0)
  ),
  rotateGesturesEnabled: false,          // North-up 고정
  tiltGesturesEnabled: false,            // 2D 유지
  compassEnabled: false,
  onMapCreated: (c) => _mlCtrl = c,      // nullable 할당만, 가드 없음
  onStyleLoadedCallback: () async {
    _styleLoaded = true;
    await _initRouteLayer();             // GeoJSON 소스/레이어 설치
    // addImage → addSymbol 순서 필수
    final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
    await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
    final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
    await _mlCtrl!.addImage('pointer_yellow', wpBytes.buffer.asUint8List());
    await _mlCtrl!.setSymbolIconAllowOverlap(true);
    await _ensureLocationMarker();
  },
  onCameraIdle: () {
    final z = _mlCtrl?.cameraPosition?.zoom;
    if (z != null) setState(() => _currentZoom = z);
  },
  onMapClick: (point, latLng) { ... },   // OnMapClickCallback
)
```

**nav_screen 차이**: `onCameraMove` 콜백이 필요함 (수동모드 감지, 아래 참조).  
`onStyleLoadedCallback`은 비동기 불가 시그니처이므로 내부에서 unawaited async 함수 호출.

---

### A2. 컨트롤러 보관 (lines 80-81)

```dart
ml.MapLibreMapController? _mlCtrl;  // nullable, late 없음
bool _styleLoaded = false;          // 스타일 로드 완료 가드
```

- `onMapCreated` 콜백에서 단순 할당 (`(c) => _mlCtrl = c`)
- 모든 API 호출 전 `if (ctrl == null) return;` 또는 `?.` 사용
- `_styleLoaded` 가드: `addSymbol`, `addCircle`, GeoJSON 업데이트 등은 스타일 로드 후에만 호출

---

### A3. 마커 추가 (lines 278-338)

**현위치 Circle 마커** (addCircle / updateCircle):
```dart
ml.Circle? _locMarker;
// 최초 생성:
_locMarker = await c.addCircle(ml.CircleOptions(
  geometry: _toMl(p),
  circleRadius: 8,
  circleColor: '#00C853',
  circleStrokeWidth: 3,
  circleStrokeColor: '#FFFFFF',
));
// 위치 갱신:
await c.updateCircle(_locMarker!, ml.CircleOptions(geometry: _toMl(p)));
```

**목적지 Symbol 마커** (PNG 아이콘, lines 297-320):
```dart
ml.Symbol? _destMarker;
// 등록 순서: onStyleLoadedCallback에서 addImage 먼저, 그 후 addSymbol
_destMarker = await c.addSymbol(ml.SymbolOptions(
  geometry: _toMl(dest),
  iconImage: 'pointer_red',   // addImage로 등록한 키
  iconSize: 1.5,
  iconAnchor: 'bottom',
  zIndex: 10,
));
// 좌표 갱신:
await c.updateSymbol(_destMarker!, ml.SymbolOptions(geometry: _toMl(dest)));
// 제거:
await c.removeSymbol(_destMarker!); _destMarker = null;
```

**경유지 Symbol 마커** (lines 322-338): 동일 패턴, `pointer_yellow` 아이콘.

**latlong2 → maplibre_gl 변환 헬퍼** (line 98):
```dart
ml.LatLng _toMl(LatLng p) => ml.LatLng(p.latitude, p.longitude);
```

---

### A4. 경로 폴리라인 (lines 240-274, 341-376)

GeoJSON Source + LineLayer 방식 (`PolylineLayer` 아님):

```dart
// 상수 (lines 83-86):
static const _routeSourceId  = 'route-source';
static const _routeLayerId   = 'route-layer';
static const _routeBgSourceId = 'route-bg-source';
static const _routeBgLayerId  = 'route-bg-layer';

// 초기 설치 (onStyleLoadedCallback → _initRouteLayer):
await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson([]));
await ctrl.addLineLayer(
  _routeSourceId, _routeLayerId,
  const ml.LineLayerProperties(
    lineColor: '#1E5AFF', lineWidth: 6.0, lineCap: 'round', lineJoin: 'round',
  ),
  belowLayerId: circleLyr,  // circle 레이어 아래에 삽입
);
// 업데이트 (경로 변경 시):
_mlCtrl?.setGeoJsonSource(_routeSourceId, _buildRouteGeoJson(points));
```

**GeoJSON 빌더** (lines 205-221):
```dart
Map<String, dynamic> _buildRouteGeoJson(List<LatLng> points) => {
  'type': 'FeatureCollection',
  'features': points.isEmpty ? [] : [{
    'type': 'Feature',
    'geometry': {
      'type': 'LineString',
      'coordinates': points.map((p) => [p.longitude, p.latitude]).toList(), // [lng, lat] 순서!
    },
    'properties': <String, dynamic>{},
  }],
};
```

**nav_screen 차이**: 대체 경로(bg)가 없음 → `_routeBgSource` 불필요. 선택 경로 1개만.  
nav_screen 색상은 현재 `Color(0xFFF28C28)` (오렌지) → MapLibre hex `'#F28C28'`.

---

### A5. 카메라 이동 (lines 168-199, 364-375, 881-882)

```dart
// 위치 + 줌:
_mlCtrl?.animateCamera(
  ml.CameraUpdate.newLatLngZoom(_toMl(loc), zoomLevel),
);
// bounds 맞춤:
_mlCtrl?.animateCamera(
  ml.CameraUpdate.newLatLngBounds(
    ml.LatLngBounds(southwest: ml.LatLng(...), northeast: ml.LatLng(...)),
    left: 50, top: 110, right: 80, bottom: 80,
  ),
);
// 줌 인/아웃:
_mlCtrl?.animateCamera(ml.CameraUpdate.zoomIn());
_mlCtrl?.animateCamera(ml.CameraUpdate.zoomOut());
// bearing 전용:
ml.CameraUpdate.bearingTo(bearing);    // ← CameraUpdate.bearingTo() 존재
// 복합 (위치 + bearing):
ml.CameraUpdate.newCameraPosition(
  ml.CameraPosition(target: _toMl(loc), zoom: zoom, bearing: bearing),
);
```

`moveCamera`도 존재하지만 main_map_screen은 `animateCamera` 통일 사용.

---

### A6. 스타일 URL

```dart
styleString: 'assets/images/osm_liberty_yurunavi.json'  // Flutter asset 경로
```

- tiles.westinx.com (외부 타일서버)를 반영한 osm_liberty_yurunavi.json이 이미 asset에 존재
- nav_screen도 동일 asset 사용. 별도 스타일 불필요.

---

## 조사 B — nav_screen.dart 교체 지점 전체 목록

### B0. import 교체 (line 12)

| 현재 | 교체 후 |
|---|---|
| `import 'package:flutter_map/flutter_map.dart';` | `import 'package:maplibre_gl/maplibre_gl.dart' as ml;` |
| `import 'package:flutter/services.dart';` | 유지 (rootBundle 필요) |

---

### B1. 컨트롤러 필드 (line 49)

| Line | 현재 | 교체 후 |
|---|---|---|
| 49 | `final MapController _mapCtrl = MapController();` | `ml.MapLibreMapController? _mlCtrl;` |
| 추가 | (없음) | `bool _styleLoaded = false;` |

---

### B2. dispose (line 159)

| Line | 현재 | 교체 후 |
|---|---|---|
| 159 | `_mapCtrl.dispose();` | 삭제 (MapLibreMapController는 dispose 없음) |

---

### B3. heading 회전 (lines 211-213)

| Line | 현재 | 교체 후 |
|---|---|---|
| 212-213 | `_mapCtrl.rotate(-pos.heading)` | `_mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(pos.heading))` |

**주의**: flutter_map은 `rotate(angle)` (지도 회전각 직접), maplibre는 `bearingTo(bearing)` (나침반 방향, 0=북). GPS heading은 북=0, 동=90 — maplibre bearing과 동일 방향이므로 부호 반전 없이 그대로 전달.

---

### B4. 카메라 이동 / 속도연동 줌 (lines 503-515)

| Line | 현재 | 교체 후 |
|---|---|---|
| 515 | `_mapCtrl.move(loc, _navZoom)` | `_mlCtrl?.animateCamera(ml.CameraUpdate.newCameraPosition(ml.CameraPosition(target: _toMl(loc), zoom: _navZoom, bearing: _currentBearing)))` |

`_currentBearing` 필드 추가 필요 (heading을 저장, 초기값 0.0).  
현재 `_navZoom`(수렴 로직 그대로 유지) + bearing 동기화.

---

### B5. 수동모드 감지 (lines 518-526 `_onMapGesture`)

| 현재 트리거 | 교체 후 |
|---|---|
| `onMapEvent: (event) { if (event is MapEventMoveStart && event.source != MapEventSource.mapController) _onMapGesture(); }` | `onCameraMove: (_) { if (!_programmaticCamera) _onMapGesture(); }` |

MapLibre에는 `MapEventSource` 구분이 없음. 대신 프로그래매틱 카메라 이동 전/후에 bool 플래그 `_programmaticCamera`를 set/clear하는 방식:
```dart
bool _programmaticCamera = false;

void _recenter(LatLng loc) {
  _programmaticCamera = true;
  _mlCtrl?.animateCamera(...).then((_) => _programmaticCamera = false);
}
// onCameraMove: (_) { if (!_programmaticCamera) _onMapGesture(); }
```

---

### B6. FlutterMap 위젯 블록 (lines 547-627)

교체 범위: `FlutterMap(...)` 전체 → `ml.MapLibreMap(...)` + `onStyleLoadedCallback` 내 마커/레이어 초기화.

**하위 레이어 교체 목록**:

| 현재 (flutter_map) | 교체 후 (maplibre_gl) |
|---|---|
| `TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/...')` | 삭제 (styleString에 타일 내장) |
| `PolylineLayer(polylines: [Polyline(points: _routePoints, color: 0xFFF28C28, strokeWidth: 4.5)])` | GeoJSON Source + LineLayer `'#F28C28'`, width 4.5~6 |
| `MarkerLayer(markers: [현위치 Container, 경유지 Icon, 목적지 Icon])` | Circle(현위치) + Symbol×N(경유지/목적지) |

**현위치 마커** (lines 586-601): 현재 `Container(BoxDecoration.circle, color: cs.tertiary)` — MapLibre Circle로 대체 시 테마 컬러 추출이 필요. 단순화 방안: `'#00C853'` 고정 (main_map_screen과 동일).

**경유지 마커** (lines 603-615): `Icon(Icons.location_pin, color: 0xFFFFB300)` → `pointer_yellow` 심볼.

**목적지 마커** (lines 617-624): `Icon(Icons.location_pin, color: Colors.redAccent)` → `pointer_red` 심볼.

---

### B7. 수동복귀 버튼 `_onMapGesture` Timer (lines 518-526)

로직 변경 없음. `_recenterTimer` + `_isManualMode` 패턴 그대로 유지.

---

## 제안 커밋 분할

각 커밋이 `flutter analyze` 통과 + `flutter build apk --debug` 빌드 가능.

### 커밋 ① — 위젯+컨트롤러 골격 (빈 지도, 타일만)
**범위**: nav_screen.dart만
- `flutter_map` import → `maplibre_gl as ml`
- `MapController _mapCtrl` → `ml.MapLibreMapController? _mlCtrl` + `_styleLoaded`
- `dispose()`에서 `_mapCtrl.dispose()` 제거
- `FlutterMap(...)` 전체를 `ml.MapLibreMap(styleString: ..., onMapCreated: ..., onStyleLoadedCallback: ..., ...)` 로 교체 (빈 콜백)
- `TileLayer` 삭제
- `PolylineLayer`, `MarkerLayer`는 임시 Flutter 위젯 오버레이(Stack)로 유지 (빌드 통과 목적)
- `_mapCtrl.move`, `.rotate` 호출을 `_mlCtrl?.animateCamera` 로 교체
- `_programmaticCamera` 플래그 + `onCameraMove` 수동모드 감지 교체

**롤백 기준**: 지도 타일이 보이면 성공.

---

### 커밋 ② — 경로 폴리라인 GeoJSON 레이어
**범위**: nav_screen.dart만
- `_buildRouteGeoJson()` 헬퍼 추가 (main_map_screen에서 직접 복사, sourceId 다르게)
- `_routeSourceId` / `_routeLayerId` 상수 추가
- `onStyleLoadedCallback` 내 `_initRouteLayer()` 호출 (addGeoJsonSource + addLineLayer)
- `_reroute()` 성공 후 `_mlCtrl?.setGeoJsonSource(...)` 로 폴리라인 갱신
- Stack의 임시 `PolylineLayer` 오버레이 제거

**롤백 기준**: 경로 오렌지선이 지도 위에 표시되면 성공.

---

### 커밋 ③ — 마커 (현위치 Circle + 목적지/경유지 Symbol)
**범위**: nav_screen.dart만
- `_toMl()` 헬퍼 추가
- `ml.Circle? _locMarker`, `ml.Symbol? _destMarker`, `List<ml.Symbol> _waypointMarkers` 필드
- `onStyleLoadedCallback`에서 `addImage('pointer_red', ...)`, `addImage('pointer_yellow', ...)` 추가
- `_ensureLocMarker()`, `_syncDestMarker()`, `_syncWaypointMarkers()` 헬퍼 추가
- `_onPosition()` 내 `_ensureLocMarker()` 호출
- Stack의 임시 `MarkerLayer` Flutter 오버레이 제거

**롤백 기준**: 현위치 녹색 원, 목적지 빨간 핀이 지도 위에 표시되면 성공.

---

### 커밋 ④ — 카메라 / 속도연동 줌 / heading 회전
**범위**: nav_screen.dart만
- `_currentBearing` 필드 (double, 초기 0.0)
- `_onPosition()` 내 heading → `_currentBearing` 갱신
- `_recenter()`: `_mapCtrl.move` → `animateCamera(newCameraPosition(target, zoom, bearing))`
- `_onPosition()` 내 `_mapCtrl.rotate` 제거 (bearing을 _recenter에 통합)
- `_programmaticCamera` 플래그로 수동모드 감지 완성
- `initState`에서 남은 `MapController` 참조 완전 제거
- `import 'package:flutter_map/flutter_map.dart'` 최종 삭제

**롤백 기준**: 주행 중 지도가 진행방향으로 회전하고 속도에 따라 줌이 바뀌면 성공.

---

## 주요 주의사항

1. **`onStyleLoadedCallback` 시그니처**: `void Function()` — `async` 불가. 내부 async 작업은 `unawaited(() async { ... }())` 또는 별도 `_initNavMapStyle()` async 함수로 분리.
2. **`_styleLoaded` 가드**: `_ensureLocMarker` 등 annotation API는 스타일 로드 전 호출 시 크래시. `if (!_styleLoaded) return;` 필수.
3. **heading 부호**: flutter_map `rotate(-heading)`은 CCW 보정이었음. maplibre `bearingTo(heading)` 은 0=북, 부호 반전 불필요. 실측 확인 필요.
4. **flutter_map 완전 제거**: `pubspec.yaml`의 `flutter_map` 의존성은 **main_map_screen도 아직 import하므로 유지**. nav_screen 이관 후 `grep -r flutter_map lib/`로 잔존 여부 확인 후 별도 커밋.
5. **현위치 색상**: main_map_screen은 `'#00C853'` 고정. nav_screen에서 `cs.tertiary` (테마 연동)를 원하면 `theme.colorScheme.tertiary`를 hex로 변환 필요. 단순화 추천: 동일하게 `'#00C853'` 고정.
6. **bg(대체) 경로 레이어**: nav_screen에는 대체 경로 표시가 없으므로 `_routeBgSource` 불필요. 선택 경로 1개 레이어만.
