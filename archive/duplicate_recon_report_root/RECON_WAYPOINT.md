# RECON_WAYPOINT (경유지 기능 현황)

## 1. 경유지 심볼 전수 결과 (파일:라인, 정의/사용 구분)

| 파일 | 라인 | 내용 | 상태 |
|------|------|------|------|
| `map_providers.dart` | 77 | `enum MapInteractionMode { idle, destinationSelected, waypointSelecting }` | **살아있음** |
| `map_providers.dart` | 82 | `final List<LatLng> waypoints;` — MapInteractionState 필드 | **살아있음** |
| `map_providers.dart` | 103 | `LatLng? get waypoint` — 단일 getter (마지막 waypoint) | **살아있음** |
| `map_providers.dart` | 151-153 | `addWaypoint(LatLng wp)` | **살아있음 (호출됨)** |
| `map_providers.dart` | 159 | `setWaypoint(LatLng wp)` → `addWaypoint` 별칭 | **살아있음 (호출됨)** |
| `map_providers.dart` | 162-163 | `startWaypointSelection()` | **정의만 있음·미연결** — 호출처 없음 |
| `map_providers.dart` | 167-169 | `removeWaypoint(int idx)` | **정의만 있음·미연결** — 호출처 없음 |
| `main_map_screen.dart` | 27 | `enum _TapAction { destination, waypoint }` | **살아있음** |
| `main_map_screen.dart` | 119 | `bool _waypointAddedAtTouch` — 중복 추가 방지 플래그 | **살아있음** |
| `main_map_screen.dart` | 385-400 | 경로 표시 중 탭 → 도착지변경/경유지추가 시트 분기 | **살아있음 (동작)** |
| `main_map_screen.dart` | 390 | `addWaypoint(tapped)` 호출 후 `_fetchAndStoreAllRoutes` 재호출 | **살아있음 (동작)** |
| `main_map_screen.dart` | 445-448 | '경유지 추가' BottomSheet ListTile | **살아있음** |
| `main_map_screen.dart` | 508 | `fetchRoutes(..., waypoints: state.waypoints)` | **살아있음 (동작)** |
| `main_map_screen.dart` | 626 | `NavScreen(waypoints: state.waypoints)` | **살아있음 (동작)** |
| `main_map_screen.dart` | 684 | `final waypoint = interaction.waypoint;` | `// ignore: unused_local_variable` — **읽기만, 마커 미연결** |
| `main_map_screen.dart` | 879-887 | LAYER 6 '경유지 추가' FloatingActionLabel 버튼 | **살아있음 (탭 핸들러 동작)** |
| `routing_service.dart` | 121-130 | `fetchRoutes(waypoints: [])` — locations 배열에 삽입 | **살아있음 (동작)** |
| `native_engine.dart` | 178,228,332 | `calcRoute`/`calcDummyRoute(waypoints:)` — 경유지 포함 경로 계산 | **살아있음** |
| `nav_screen.dart` | 28,35 | `final List<LatLng> waypoints` Widget 파라미터 | **살아있음** |
| `nav_screen.dart` | 309 | Valhalla 내비 요청에 `waypoints: widget.waypoints` 전달 | **살아있음 (동작)** |
| `nav_screen.dart` | 543-556 | `FlutterMap`(구형) `Marker`로 경유지 노랑 `Icons.location_pin` 표시 | **살아있으나 구형 FlutterMap 마커** |

---

## 2. 상태 보관층 — 경유지 자료구조 유무

- **있음**: `MapInteractionState.waypoints: List<LatLng>` (`map_providers.dart:82`)
- **초기값**: `const []` — 빈 리스트
- **살아있음**: `addWaypoint()` / `setWaypoint()` 실제로 호출됨 (main_map_screen:390, 885)
- **clearWaypoints 플래그**: `copyWith(clearWaypoints: true)` — 리셋 경로도 존재

### 소비처
| 소비처 | 방식 | 동작 |
|--------|------|------|
| `_fetchAndStoreAllRoutes` | `state.waypoints`를 `fetchRoutes`에 전달 | **동작** |
| `NavScreen` 진입 | `waypoints: state.waypoints` 파라미터 전달 | **동작** |
| `interaction.waypoint` getter | `// ignore: unused_local_variable` | **읽으나 지도 마커 미연결** |

---

## 3. UI 진입층 — 경유지 추가 인터랙션

**두 개 경로 모두 살아있음:**

### 경로 A — 경로 카드 표시 중 탭 (`main_map_screen.dart:385-407`)
- 경로 카드 표시 중(`_showCourseSheet=true`) 지도 탭 → `_showTapActionSheet()` → '경유지 추가' / '도착지변경' BottomSheet
- '경유지 추가' 선택 시: `addWaypoint(tapped)` → `_fetchAndStoreAllRoutes` 재호출
- **살아있고 동작함**

### 경로 B — LAYER 6 '경유지 추가' FloatingActionLabel (`main_map_screen.dart:879-887`)
- 목적지 미확정 상태(`dest == null`)에서 지도 탭 후 뜨는 플로팅 버튼
- `setWaypoint(_touchPoint!)` 호출 → `_waypointAddedAtTouch = true`로 중복 방지
- **살아있음. 단 호출 후 라우팅 재계산을 트리거하지 않는다** — 목적지 미확정이라 fetchRoutes 호출 경로 없음

---

## 4. 라우팅 전달층 (★) — Valhalla/OSRM 요청에 경유지 자리

### `fetchRoutes` locations 배열 구조 (`routing_service.dart:121-130`)
```dart
final locations = [
  {'lon': origin.longitude, 'lat': origin.latitude},
  for (final w in waypoints)
    {'lon': w.longitude, 'lat': w.latitude},   // ← 경유지 중간 삽입
  {'lon': destination.longitude, 'lat': destination.latitude},
];
```
- **중간 삽입 구현 완료**. `[origin, ...waypoints, destination]` 구조 정상.
- `_cacheKey`도 waypoints 포함하여 캐시 키 생성.
- `calcRoute` / `calcDummyRoute` (native_engine.dart)도 동일한 `[origin, ...waypoints, destination]` 패턴.

### 실제 요청 도달 여부
- `_fetchAndStoreAllRoutes`에서 `state.waypoints`를 읽어 `fetchRoutes`에 전달 — **살아있고 실제 Valhalla 요청에 들어감**.

---

## 5. 마커 렌더링 — 노랑 핀 연결 지점

### 지도(MapLibre) 위 경유지 마커: **없음**
- `main_map_screen.dart:684`: `interaction.waypoint` 읽으나 `// ignore: unused_local_variable` — **지도에 표시하는 코드 없음**
- `ref.listen`은 `routePolyline` 변화만 감시, `waypoints` 변화 감지 없음 (`main_map_screen.dart:688-692`)
- `addSymbol`/`addImage`/`pointer_yellow` 참조 완전 없음

### nav_screen 경유지 마커: 구형 FlutterMap 방식
- `nav_screen.dart:543-556`: `FlutterMap`의 `Marker` 위젯으로 `Icons.location_pin` 노랑 아이콘 렌더링
- 구형 FlutterMap 방식 — MapLibre 마이그레이션 대상

### 목적지 핀 패턴 (재사용 가능)
```dart
// 목적지 (pointer_red):
_destMarker = await c.addSymbol(SymbolOptions(
  geometry: geo, iconImage: 'pointer_red',
  iconSize: 1.5, iconAnchor: 'bottom',
));
// → 경유지(pointer_yellow)도 동일 패턴 적용 가능
```
- `addImage` 등록은 `onStyleLoadedCallback`에서 1회 수행 → `pointer_yellow`도 같이 등록하면 됨
- 다중 경유지이므로 `List<ml.Symbol> _waypointMarkers = []` 구조 필요

---

## 6. git 이력·주석 잔재

| 커밋 | 내용 |
|------|------|
| `1136774` | `feat(flutter): tap-action sheet for 도착지변경/경유지추가 (ROADMAP 6)` — 경유지 UI 최초 구현 |
| `229caa6` | `fix(map): waypoint button stays visible after adding waypoint (NIGHT11 item 8)` — 중복 버튼 버그 수정 |

주석 잔재:
- `native_engine.dart:277`: `//         waypoints: waypoints.map(...)` (Rust bridge 미구현 주석 처리)
- `native_engine.dart:331`: `// 경유지 포함 전체 구간을 분할해서 각 구간별로 곡선 생성` (구현 완료 주석)

---

## 7. 결론 — 판정

### **(B) 재배선 필요**

### 살아있는 부분 (연결 완료)
- 상태: `MapInteractionState.waypoints` + `addWaypoint()` / `setWaypoint()` / `clearWaypoints`
- UI 진입: 경로 표시 중 탭 시트 '경유지 추가', LAYER 6 플로팅 버튼
- 라우팅: `fetchRoutes(waypoints:)` → Valhalla locations 배열에 정상 삽입
- 내비: `NavScreen(waypoints:)` 파라미터 전달, Valhalla 내비 요청에 포함
- 캐시 키: waypoints 반영

### 죽어있는(연결 안 된) 부분
| 항목 | 현황 | 필요 작업 |
|------|------|----------|
| 지도 위 경유지 마커 (MapLibre) | **없음** — `unused_local_variable` | `_waypointMarkers: List<ml.Symbol>`, `_ensureWaypointMarkers()` 구현 |
| `pointer_yellow` addImage 등록 | **없음** | `onStyleLoadedCallback`에 `addImage('pointer_yellow', ...)` 추가 |
| waypoints 변화 → 마커 갱신 리스너 | **없음** | `ref.listen`에 `waypoints` 변화 감지 추가 |
| `removeWaypoint(idx)` UI | **정의만·미연결** | 경유지 삭제 UI 미구현 |
| `startWaypointSelection()` | **정의만·미연결** | 호출처 없음 (현재 탭 기반으로 충분) |
| nav_screen FlutterMap 마커 | **구형 방식** | MapLibre 전환 시 수정 필요 (현재는 FlutterMap 마커가 내비 화면에 보임) |

### 다음 세션 설계 범위 한 줄
`onStyleLoadedCallback`에 `pointer_yellow` addImage 등록 추가 + `List<ml.Symbol> _waypointMarkers` 관리 + `ref.listen`에 waypoints 변화 감지 → `_ensureWaypointMarkers()` 구현 (목적지 패턴 그대로 복제).

### 경유지 특유 난점 현황

| 난점 | 현재 코드가 가진 것 | 없는 것 |
|------|-------------------|---------|
| N개 관리 | `List<LatLng> waypoints` (다중 지원) | 마커 `List<ml.Symbol>` 없음 |
| 순서 | `[...waypoints]` 리스트 순서 그대로 Valhalla 전달 | 순서 변경 UI 없음 |
| 재탐색 | 경유지 추가 시 `_fetchAndStoreAllRoutes` 재호출 **동작** | LAYER 6 경로 탭 전 추가 시 재탐색 없음 |
| 삭제 UI | `removeWaypoint(idx)` 정의만 | 삭제 버튼/제스처 없음 |

### 미확인/리스크
1. LAYER 6 경유지 버튼(`setWaypoint`) — 목적지 미확정 상태에서 눌러봤자 fetchRoutes 미호출. 목적지 확정 후에야 경유지가 라우팅에 반영됨. 사용자 혼란 가능.
2. `nav_screen.dart:543-556` FlutterMap `Marker` 방식은 MapLibre 마이그레이션 후 구형 FlutterMap 레이어가 있어야만 보임 — 현재 내비 화면에 FlutterMap이 남아있는지 확인 필요.
3. 경유지 마커 z-order: 목적지 핀 아래에 경유지 핀이 그려질 가능성 — `belowLayerId` 조정 필요할 수 있음.
