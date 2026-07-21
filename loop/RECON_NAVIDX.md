# RECON_NAVIDX (nav_screen 선택코스 무시 버그)

## 1. 버그 지점
- **routes[0] 하드코딩 위치(라인)**: `nav_screen.dart:311`
  ```dart
  if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);
  ```
  맥락: `_reroute()` 메서드 내부 — GPS 이탈 감지 후 `RoutingService.fetchRoutes()`를 호출하고,
  반환된 routes 리스트에서 무조건 `[0]`(시골길)을 선택.

- **다른 routes[0]/고정인덱스 사용처**: 없음.
  `_routePoints` 초기화(`L118`)는 `widget.routePolyline`을 사용하므로 별개 경로(정상).

---

## 2. nav_screen 파라미터 현황
- **selectedRouteIdx(또는 유사) 파라미터 존재?**: **없음**
- **현재 받는 widget 파라미터 목록** (`nav_screen.dart:27-37`):
  ```
  final LatLng? destination
  final List<LatLng> waypoints
  final List<LatLng> routePolyline   ← 선택된 경로 폴리라인(초기 표시용)
  final List<ManeuverStep> maneuvers ← 선택된 경로의 안내 단계
  ```
  `selectedRouteIdx` 파라미터는 선언되어 있지 않다.

---

## 3. 재탐색 흐름 — routes 받아 그리는 구조

```
GPS 이탈 감지 (L272 디바운스 3초)
  → _reroute(LatLng origin)  [L300]
    → RoutingService.fetchRoutes(origin, destination, waypoints)  [L306]
    → routes[0].points 로 _routePoints 갱신  [L311]  ← 버그
    → setState() → 폴리라인 재렌더링  [L513-517]
```

`_reroute`는 `_steps`(maneuvers)를 갱신하지 않는다.
`_routePoints`만 교체 — 재탐색 후 안내 단계는 초기 코스 기준 그대로 유지된다
(이 부분도 추후 이슈지만 현재 버그와는 분리).

`NavScreen`은 `ConsumerStatefulWidget`을 상속하며, `_NavScreenState`는 `ref`를 보유한다.
따라서 `ref.read(mapInteractionProvider)` 호출이 `_reroute` 내에서 즉시 가능하다.

---

## 4. 호출부(main_map_screen) — NavScreen에 무엇을 넘기나

호출 위치: `main_map_screen.dart:646` — `_startNavigation()` 내부

```dart
NavScreen(
  destination: dest,
  waypoints: state.waypoints,
  routePolyline: state.routePolyline,   // provider의 선택 경로 폴리라인 (정상)
  maneuvers: _selectedManeuvers,        // setState로 관리되는 선택 maneuvers (정상)
)
```

- **현재 넘기는 인자 목록**: destination, waypoints, routePolyline, maneuvers
- **선택코스 인덱스를 넘기나?**: **아니오**
- **main_map_screen에 선택코스 인덱스 상태가 있나?**:
  - provider 상태: `mapInteractionProvider.selectedRouteIdx` (int, `map_providers.dart:87`)
    - 기본값 = `2` (국도), `setSelectedRouteIdx(idx)` 로 변경
  - 로컬 변수: `main_map_screen.dart:348` `selIdx = state.selectedRouteIdx` (읽기 전용 사용)
  - `_startNavigation()` 내부에서 `state.selectedRouteIdx`를 읽지 않으며 NavScreen에 전달하지 않는다.

---

## 5. 선택 인덱스 출처(provider state / 로컬 / 없음)

**provider state** (`MapInteractionState.selectedRouteIdx`).
- `map_providers.dart:87`: `final int selectedRouteIdx; // 0: 시골길, 1: 지방도로, 2: 국도`
- `map_providers.dart:183-184`: `void setSelectedRouteIdx(int idx)`
- 사용자가 코스 카드를 누르면 `_onRouteCardSelect(idx)` → `setSelectedRouteIdx(idx)` 저장.
- NavScreen이 실행 중일 때도 provider는 살아있으므로 `ref.read()`로 접근 가능.

---

## 6. 결론 — 수정 범위 판정

### 분석의 "2파일 수정"이 맞나?
**아니오. 1파일(nav_screen.dart) 단일 라인 수정으로 충분하다.**

`NavScreen`은 이미 `ConsumerStatefulWidget`이고 `ref`를 보유한다.
`_reroute()` 안에서 provider를 직접 읽으면 파라미터 신설 없이 해결된다.

```dart
// 현재 (L311)
setState(() => _routePoints = routes[0].points);

// 수정안
final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx
    .clamp(0, routes.length - 1);
setState(() => _routePoints = routes[selIdx].points);
```

### 필요한 변경 목록(파일별)
- **nav_screen.dart** (L311):
  `routes[0].points` →
  `routes[ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length-1)].points`
  (1줄 수정)

- **main_map_screen.dart**: 변경 불필요.
  `_startNavigation()`이 넘기는 `state.routePolyline`은 이미 선택 경로이므로 초기 표시는 정상.

- **provider(map_providers.dart)**: 변경 불필요.
  `selectedRouteIdx`는 이미 존재하고 올바르게 유지된다.

### 한 커밋 스코프로 적절한가
**예.** 1파일 1라인 수정 → 단일 커밋.

### 가장 안전한 구현 순서
1. `nav_screen.dart:311` — `routes[0]` → `routes[selIdx]` (clamp 포함)
2. `flutter analyze` 확인
3. 커밋

### 미확인/리스크
- **selectedRouteIdx가 재탐색 중 바뀌나?**
  `_reroute`는 async. 재탐색 API 대기 중 사용자가 앱에 돌아와 코스를 바꿀 수 없다
  (NavScreen이 활성화된 상태이므로 main_map_screen의 코스 카드 UI가 닫혀 있다).
  사실상 경쟁 없음.

- **clamp 범위**: `RoutingService.fetchRoutes`가 3개 미만의 routes를 반환할 경우
  (네트워크 부분 실패 등) clamp가 안전망 역할을 한다. 필수.

- **maneuvers 미동기화**: 재탐색 시 `_steps`(안내 단계)은 갱신되지 않는다.
  현재 버그 범위(코스 인덱스)와는 다른 문제이므로 이번 커밋에서 건드리지 말 것.
  별도 이슈로 등록 권장.

- **provider import**: `nav_screen.dart:20`에 `map_providers.dart` import 이미 존재.
  추가 import 불필요.
