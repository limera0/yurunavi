# RECON_marker.md — 목적지 마커 위치 고정 버그 (증상2)

생성일: 2026-06-17  
범위: nav_screen.dart + main_map_screen.dart (코드 변경 0)

---

## §A 목적지 마커에 LatLng 부여하는 지점

### A1. nav_screen.dart — FlutterMap Marker

```
nav_screen.dart:896-903
  if (widget.destination != null)
    Marker(
      point: widget.destination!,          ← LatLng 부여 지점
      width: 38, height: 38,
      alignment: Alignment.topCenter,
      child: Icon(Icons.location_pin, color: Colors.redAccent, size: 38),
    ),
```

FlutterMap의 `MarkerLayer` 내 Flutter 위젯으로 렌더링됨.  
경유지 마커도 동일 구조: `nav_screen.dart:883–895` (Marker.point: wp).

### A2. main_map_screen.dart — MapLibre 네이티브 Symbol

```
main_map_screen.dart:315–329  _ensureDestMarker(LatLng dest)
  geo = _toMl(dest)                        ← LatLng → ml.LatLng 변환
  _destMarker = await c.addSymbol(ml.SymbolOptions(
    geometry: geo,
    iconImage: 'pointer_red',
    iconAnchor: 'bottom',
    zIndex: 10,
  ))
  또는
  await c.updateSymbol(_destMarker!, ml.SymbolOptions(geometry: geo))
```

MapLibre 네이티브 Symbol → 지도 렌더러가 geo 좌표를 화면으로 투영 (지도 좌표 추적).

---

## §B 화면좌표 고정 vs 지도좌표 추적

### B1. nav_screen — **화면좌표 고정 (버그)**

FlutterMap 오버레이 구조:

```
nav_screen.dart:870–907
  IgnorePointer(
    child: FlutterMap(
      options: MapOptions(
        backgroundColor: Colors.transparent,
        initialCenter: _currentPos ?? _kInitialMapView,  ← 초기값만 설정
        initialZoom: _navZoom,
        interactionOptions: InteractiveFlag.none,        ← 사용자 조작 비활성
      ),
      children: [ MarkerLayer(...) ],
    ),
  )
```

- FlutterMap에 `MapController` 필드 없음 (`grep MapController nav_screen.dart` → 0건)
- MapLibre 카메라 이동 함수 `_recenter()` (nav_screen.dart:726–738):
  - `_mlCtrl?.animateCamera / moveCamera()` 만 호출
  - FlutterMap 카메라에 대한 호출 없음
- FlutterMap 뷰포트는 `initialCenter`에 영구 고정됨

**결과:** 내비게이션 중 MapLibre 카메라가 이동하면 FlutterMap 뷰포트는 초기 위치에
머물러, Marker의 geo 좌표가 초기 뷰포트 기준 화면 좌표로 투영됨. MapLibre 타일
위에서 목적지 마커가 엉뚱한 위치(또는 화면 밖)에 표시되는 "위치 고정" 현상 발생.

### B2. main_map_screen — 지도 좌표 추적 (정상, 단 별도 소멸 버그 있음)

MapLibre 네이티브 Symbol은 지도 렌더러가 geo 좌표를 직접 투영하므로
화면 좌표 고정 문제 없음.

---

## §C 스타일 재주입 시 마커 파괴/재생성 경로

### C1. main_map_screen 스타일 재주입 트리거

```
main_map_screen.dart:746–751  (ref.listen mapLanguageProvider)
  setState(() => _styleJson = applyMapLanguageToStyle(raw, lang))
```

`_styleJson` 변경 → Flutter rebuild → `ml.MapLibreMap(styleString: _styleJson!, ...)`
(main_map_screen.dart:793) 가 새 styleString 을 받음 → MapLibre 내부 스타일 리로드.

### C2. onStyleLoadedCallback 처리 (main_map_screen.dart:804–824)

```dart
onStyleLoadedCallback: () async {
  _styleLoaded = true;
  _locMarker = null;
  _destMarker = null;               ← ① 목적지 마커 참조 초기화
  _waypointMarkers = [];
  await _initRouteLayer();
  final poly = ref.read(mapInteractionProvider).routePolyline;
  if (poly.isNotEmpty) _updateRouteLayer(poly);
  await _mlCtrl!.addImage('pointer_red', ...);   ← ② 이미지 재등록
  await _mlCtrl!.addImage(_kWpIcon, ...);
  await _mlCtrl!.setSymbolIconAllowOverlap(true);
  await _ensureLocationMarker();    ← ③ 위치 마커만 재생성
  // _ensureDestMarker 호출 없음   ← ④ 목적지 마커 재생성 누락
}
```

### C3. _ensureDestMarker 호출처

| 호출 위치 | 조건 |
|---|---|
| main_map_screen.dart:534 | 목적지 탭 시 `_onMapTap` 완료 후 |
| onStyleLoadedCallback | **없음** ← 버그 |

`ref.listen<MapInteractionState>` (main_map_screen.dart:734–740) 가 감시하는 항목:
- `routePolyline` → `_updateRouteLayer`
- `waypoints` → `_syncWaypointMarkers`
- `destination` → **없음** ← `_ensureDestMarker` 재호출 트리거 없음

**결과:** 언어 설정 변경 등으로 스타일이 재주입되면 목적지 마커가 소멸하고
`destination` 상태에 값이 남아 있어도 재생성되지 않음.

---

## §D nav_screen 목적지 마커 구현 비교

| 항목 | nav_screen | main_map_screen |
|---|---|---|
| 렌더링 방식 | FlutterMap MarkerLayer 위젯 | MapLibre 네이티브 Symbol |
| LatLng 부여 | `Marker(point: widget.destination!)` | `SymbolOptions(geometry: _toMl(dest))` |
| 지도 카메라 동기화 | **없음** (FlutterMap 뷰포트 고정) | 자동 (MapLibre 자체 투영) |
| 스타일 리로드 영향 | 없음 (Flutter 위젯층) | 소멸 후 미복구 |

---

## §E 수정 방향 (RECON 전용 — 구현은 별도 태스크)

### E1. nav_screen 목적지 마커 (우선순위 높음)

**옵션 A (권장):** FlutterMap 오버레이를 완전 제거하고 MapLibre 네이티브 Symbol로 교체.
- nav_screen의 `_locMarker` (Circle) 방식 그대로 목적지·경유지도 Symbol로 추가
- `_onStyleLoaded()` (nav_screen.dart:796) 에서 이미지 등록 + Symbol 생성
- 장점: FlutterMap 의존성 제거, 카메라 동기화 문제 원천 차단

**옵션 B (임시):** FlutterMap에 `MapController` 추가 후 MapLibre 카메라 이동 시
`_flutterMapCtrl.move(center, zoom)` 동기 호출.
- 단점: MapLibre ↔ FlutterMap 줌 스케일 불일치, 성능 overhead, 두 렌더러 유지 비용

### E2. main_map_screen 스타일 재주입 후 목적지 마커 소멸 (우선순위 중간)

`onStyleLoadedCallback` 의 `_ensureLocationMarker()` 호출 직후:

```dart
final dest = ref.read(mapInteractionProvider).destination;
if (dest != null) _ensureDestMarker(dest); // unawaited
```

추가로 `_syncWaypointMarkers(ref.read(...).waypoints)` 도 동일 위치에서 재호출 필요.
