# RECON_WPMARKER (경로B 비활성 + 경유지 노랑핀)

## 1. 경로B 버튼 — 비활성화 지점

### 버튼 위젯 위치
- **외곽 가시성 조건** (`main_map_screen.dart:867`):
  ```dart
  if (_touchPoint != null && dest == null)
    Positioned(...)
  ```
  → LAYER 6 전체가 `_touchPoint != null && dest == null` 조건으로 감싸임.  
  `dest`는 `interaction.destination` (line 683).

- **경유지 버튼 직접 조건** (line 877, 891 — 두 곳):
  ```dart
  if (!_waypointAddedAtTouch)
    _FloatingActionLabel(label: '경유지 추가', ...)
  if (!_waypointAddedAtTouch)
    const SizedBox(width: 10),
  ```
  `_waypointAddedAtTouch`가 `true`이면 버튼과 간격 둘 다 숨겨짐.

- **setWaypoint 호출 라인**: `line 885`
  ```dart
  ref.read(mapInteractionProvider.notifier).setWaypoint(_touchPoint!);
  ```

### 가장 안전한 비활성 방법
**버튼 조건에 `dest == null` → `false`로 만드는 대신, 버튼 자체를 `if` 조건에서 완전 제거하는 것이 가장 단순.**

구체적으로: line 877의 `if (!_waypointAddedAtTouch)` 앞에 `&& dest != null`(또는 `&& false`) 추가보다,  
**`if (!_waypointAddedAtTouch)` 블록 전체(line 877-890: 버튼 + SizedBox)를 삭제**하는 게 안전.

단, 이렇게 하면 경유지 버튼이 이 경로에서 영구 제거됨. LAYER 6 전체는 살려두고(`_touchPoint != null && dest == null`) 목적지 버튼만 남김.

**정찰자 권장**: `if (!_waypointAddedAtTouch) _FloatingActionLabel(label: '경유지 추가', ...)` 블록과 `if (!_waypointAddedAtTouch) const SizedBox(width: 10)` — 이 두 덩어리 제거. `_waypointAddedAtTouch` 필드와 관련 setState도 이 경로에서 쓰는 곳이 이것뿐이라면 같이 정리 가능(아래 미확인 항목 참조).

---

## 2. 경로A(살려둘 것) 경계 — 건드리면 안 되는 라인 범위

- **경로A 전체**: `main_map_screen.dart:385-413` (`_onMapTap` 내부 `_showCourseSheet` 분기)
  ```dart
  if (_showCourseSheet) {                          // 385
    final action = await _showTapActionSheet(...); // 387
    if (action == _TapAction.waypoint) {           // 389
      addWaypoint(tapped); ...                     // 390
      _fetchAndStoreAllRoutes(origin, dest);       // 395
    }                                              // 401
    if (action != _TapAction.destination) return;  // 403
  }                                                // 405
  ```
- **탭 액션 시트** (`_showTapActionSheet`): line 415-460 — 건드리지 마라.
- **`addWaypoint`** (line 390) / **`_fetchAndStoreAllRoutes`** (line 395) — 건드리지 마라.

---

## 3. waypoints 변화 감지 — 리스너 추가 지점

### 현재 ref.listen (line 688-692)
```dart
ref.listen<MapInteractionState>(mapInteractionProvider, (prev, next) {
  if (prev?.routePolyline != next.routePolyline) {
    _updateRouteLayer(next.routePolyline);
  }
});
```
감시 대상: `routePolyline` 변화만. `waypoints` 감지 없음.

### waypoints 감지 추가 위치
**동일한 `ref.listen` 블록 안에 조건 추가**:
```dart
ref.listen<MapInteractionState>(mapInteractionProvider, (prev, next) {
  if (prev?.routePolyline != next.routePolyline) {
    _updateRouteLayer(next.routePolyline);
  }
  // 추가:
  if (prev?.waypoints != next.waypoints) {
    _syncWaypointMarkers(next.waypoints);  // 새로 만들 메서드
  }
});
```
→ 위치: line 688-692 블록 내부, 기존 if 아래에 추가. 기존 코드 흐름 무변경.

**주의**: `List`의 `!=` 비교는 참조 동일성. `addWaypoint`/`removeWaypoint`는 항상 새 리스트를 만들어 반환(`[...state.waypoints, wp]`)하므로 참조가 바뀜 → 감지 정상 동작.

### interaction.waypoint vs state.waypoints
- `interaction.waypoint`: `waypoints.isEmpty ? null : waypoints.last` — **단일, 마지막 것만**. 다중 경유지 마커에 부적합.
- `next.waypoints`: `List<LatLng>` — **전체 리스트**. 마커 동기화는 이것을 써야 함.
- line 684 `final waypoint = interaction.waypoint; // ignore: unused_local_variable` → 마커 연결 후 `ignore` 제거 가능(또는 유지).

---

## 4. 목적지 핀 패턴 + addImage 블록(복제 기준)

### `_ensureDestMarker` 구조 (line 295-316)
```dart
Future<void> _ensureDestMarker(LatLng dest) async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;        // 가드: 컨트롤러+스타일 로드 확인
  final geo = _toMl(dest);
  if (_destMarker == null) {
    _destMarker = await c.addSymbol(ml.SymbolOptions(
      geometry: geo,
      iconImage: _kDestIcon,       // 'pointer_red'
      iconSize: _kDestIconSize,    // 1.5
      iconAnchor: 'bottom',
    ));
  } else {
    await c.updateSymbol(_destMarker!, ml.SymbolOptions(geometry: geo));
  }
}
```
→ 경유지용은 단일 Symbol 대신 `List<ml.Symbol>`로 관리. `_removeDestMarker` 패턴도 동일하게 복제.

### addImage 등록 위치 (line 752-754)
```dart
onStyleLoadedCallback: () async {
  _styleLoaded = true;
  await _initRouteLayer();
  final poly = ref.read(mapInteractionProvider).routePolyline;
  if (poly.isNotEmpty) _updateRouteLayer(poly);
  // ← 여기: pointer_yellow도 같이 등록
  final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
  await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
  // pointer_yellow 추가할 자리: 위 두 줄 아래에 동일 패턴으로
  await _ensureLocationMarker();
},
```
추가할 코드:
```dart
final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
await _mlCtrl!.addImage('pointer_yellow', wpBytes.buffer.asUint8List());
```

---

## 5. waypoints 자료구조 + 변경 메서드(마커 동기화 매핑)

| 동작 | 메서드 | 결과 |
|------|--------|------|
| 추가 | `addWaypoint(wp)` / `setWaypoint(wp)` | 새 리스트 `[...old, wp]` |
| 삭제 | `removeWaypoint(idx)` | 해당 인덱스 제거한 새 리스트 |
| 전체 초기화 | `reset()` → `MapInteractionState()` 기본값 `waypoints: const []` | 빈 리스트 |
| 선택 초기화 | `copyWith(clearWaypoints: true)` | 빈 리스트 |

`reset()`은 `const MapInteractionState()`를 직접 할당 → `waypoints = const []`로 초기화됨.  
`clearWaypoints: true` 경로도 동일하게 빈 리스트.

---

## 6. 목적지 해제 시 경유지 정리 여부

**YES — 자동 정리됨.**

`_clearDestination()` (line 594-604):
```dart
void _clearDestination() {
  ref.read(mapInteractionProvider.notifier).reset();  // ← waypoints도 초기화
  ref.read(poiListProvider.notifier).clear();
  setState(() { _showCourseSheet = false; _touchPoint = null; });
  _sheetCtrl.reverse();
  _recenterMap();
  _removeDestMarker(); // unawaited — B2
}
```
- `reset()` = `state = const MapInteractionState()` → `waypoints = const []`
- **waypoints 상태는 자동 초기화**. 단, 지도 위 경유지 마커는 현재 없으므로 마커 제거 코드도 `_clearDestination` 에 추가해야 함.
- 추가할 것: `_clearWaypointMarkers();` — `_removeDestMarker()` 호출 근처에.

---

## 7. 결론 — 실행 설계

### 경로B 비활성 방법 (1줄)
`if (!_waypointAddedAtTouch)` 블록 2개(경유지 버튼 + SizedBox, line 877-892)를 통째 제거. `_waypointAddedAtTouch` 필드·setState도 이 경로에서만 쓰이면 같이 제거(미확인 사항 1 참조).

### 경유지 마커 관리 구조

**전체 재생성(clear 후 재add) 방식 채택 권장.**

이유:
- waypoints 변경 빈도 낮음 (사용자 수동 탭)
- 순서 중요 (List 순서 = 경로 순서 = 마커 순서)
- 증분 관리(add/remove per index)는 인덱스 추적 복잡
- `addWaypoint`/`removeWaypoint` 모두 `_syncWaypointMarkers(waypoints)` 단일 진입점으로 처리 가능

```dart
List<ml.Symbol> _waypointMarkers = [];

Future<void> _syncWaypointMarkers(List<LatLng> waypoints) async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;
  // 전체 제거
  for (final s in _waypointMarkers) await c.removeSymbol(s);
  _waypointMarkers = [];
  // 전체 재생성
  for (final wp in waypoints) {
    final s = await c.addSymbol(ml.SymbolOptions(
      geometry: _toMl(wp),
      iconImage: 'pointer_yellow',
      iconSize: _kWpIconSize,     // 상수 추가 필요
      iconAnchor: 'bottom',
    ));
    _waypointMarkers.add(s);
  }
}
```

`_clearWaypointMarkers()` = `_syncWaypointMarkers([])` 와 동일하므로 별도 메서드 불필요.

### z-order 예상 + 리스크

MapLibre annotation manager 레이어 초기화 순서 (RECON_ZORDER 참조):
- circleManager(현위치 원형) → symbolManager(목적지핀/경유지핀) 순으로 초기화
- route 레이어: `belowLayerId: circleLyr` — circle 레이어 아래
- 결과 예상 z-order (하→상): **경로선 < circleManager(현위치 원) < symbolManager(경유지핀·목적지핀)**

**리스크**: symbolManager 내에서 경유지핀과 목적지핀의 z-order는 추가 순서에 의존. 경유지는 `_syncWaypointMarkers`에서, 목적지는 `_ensureDestMarker`에서 따로 추가됨 → 일반적으로 먼저 추가된 것이 아래. 실측으로 확인 필요.

### 한 커밋 스코프

**2커밋 분리 권장**:

| 커밋 | 내용 | 이유 |
|------|------|------|
| 커밋①  | 경로B 비활성 (버튼 2블록 제거) | 마커와 독립, 회귀 즉시 확인 가능 |
| 커밋② | pointer_yellow addImage + _syncWaypointMarkers + ref.listen 추가 + _clearDestination 연결 | 마커 기능 통합 |

두 작업을 한 커밋에 넣어도 불가는 아니나, 경로B 비활성은 단순 삭제라 독립 커밋이 더 명확.

### 미확인/리스크

1. **`_waypointAddedAtTouch` 다른 참조 여부**: line 119(선언), 410(setState), 877/891(조건). 경로B 버튼 제거 시 line 410(`_waypointAddedAtTouch = false`) setState도 불필요해질 수 있음. 완전 제거 여부는 실행 턴에서 grep으로 재확인 후 판단.

2. **pointer_yellow.png 픽셀 크기**: `file assets/images/pointer_yellow.png`를 실행 턴에서 확인 → `_kWpIconSize` 초기값 결정. 정찰에서 `ls -la`로 4431 bytes 확인했으나 픽셀 크기 미확인(`file` 명령 미실행). pointer_red가 96×96이므로 동일할 가능성 높음 — 실행 턴 0단계에서 `file` 로 확인 후 iconSize 결정.

3. **내비 화면 경유지 마커**: `nav_screen.dart:543` FlutterMap `Marker` 방식은 이번 스코프 외. 내비 진입 시 경유지가 FlutterMap 마커로 표시되는지 여부는 별도 확인 필요.
