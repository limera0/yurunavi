# RECON_A — A묶음 정찰 결과

## 1. '좋은 장소를 찾고 있어요' 멘트 (폰#1)

- **위치**: `lib/features/map/presentation/main_map_screen.dart:715`
- **위젯**: `build()` 내 LAYER 2 loading overlay (`if (interaction.isLoading)` 조건, 라인 685).
  `CircularProgressIndicator` + 텍스트가 한 컨테이너에 묶인 구조.
- **결합 여부**: `interaction.isLoading == true`일 때만 렌더. 스피너와 항상 같이 뜸.
  `isLoading`은 `_fetchAndStoreAllRoutes`가 시작/종료 시 `setLoading(true/false)` 호출.
- **제거 방법**: 라인 685-721의 `if (interaction.isLoading) Positioned.fill(...)` 블록 전체 제거.
  `isLoading` 자체는 경로탐색 흐름 제어에도 쓰이므로 상태 변수는 남겨야 함.

---

## 2. '요약' 헤더 + '최단/최속' 뱃지 (폰#4)

### '요약' 헤더 (경로 요약 시트 제목)
- **위치**: `lib/features/map/presentation/main_map_screen.dart:471`
  `Text('$courseName 경로 요약', ...)` — `_CourseSheet`의 요약 팝업 바텀시트 빌더 내부.
  `_buildSummarySheet`에서 렌더됨.
- **순수 표시용**: 로직 참조 없음. 표시 전용.

### '요약' 버튼 (시트 상단 우측)
- **위치**: `lib/features/map/presentation/main_map_screen.dart:1318`
  `label: const Text('요약', style: ...)` — `_CourseSheet` 위젯 헤더 행.
  `onShowSummary != null`일 때만 렌더. 탭하면 `onShowSummary` 콜백 호출.
- **논리 의존**: 표시만. `onShowSummary` 콜백은 `_buildSummarySheet` 호출로 이어짐.

### '최단' / '최속' 뱃지
- **위치**: `lib/features/map/presentation/main_map_screen.dart:1475, 1479`
  `_RouteCard` 위젯 내부 `_CompChip(label: '최단'/'최속', color: info.color)`.
- **계산 위치**: 라인 1366-1367 — `allRouteMeta` 전체를 순회해 `bestDist`, `bestTime`을 뽑아 각 카드에 `isBestDist`/`isBestTime` 플래그 전달.
- **논리 의존**: **순수 표시용**. 선택 로직·정렬에는 참조되지 않음. 제거해도 동작에 영향 없음.

---

## 3. 줌맞춤 현황 (폰#5) — "이미 있는데 안 먹음"

- **newLatLngBounds 호출 위치**: `lib/features/map/presentation/main_map_screen.dart:352-363`
  `_applyDestination()` 함수 내부. **목적지 최초 설정 시 1회만** 호출됨.
- **카드 전환 시**: `_onRouteCardSelect(int idx)` (라인 553)에서 `setRoutePolyline(allRoutes[selIdx])` 호출 → `ref.listen`(라인 606) 트리거 → `_updateRouteLayer(points)` 호출.
  `_updateRouteLayer`는 GeoJSON 데이터만 교체하고 **카메라 재맞춤은 없음**.
- **결론**: 카드 전환할 때 경로선은 바뀌지만 카메라는 움직이지 않음. 최초 목적지 탭 시 bounds 계산도 origin↔dest 기준이므로 경로 실제 선형을 반영하지 않음.
  경로선에 맞는 줌맞춤이 필요하면 `_onRouteCardSelect` 또는 `_updateRouteLayer` 내에서
  경로 points의 min/max lat·lng로 `newLatLngBounds` 재호출 추가 필요.

---

## 4. 대안경로 현황 (폰#3)

- **현재**: 소스/레이어 ID가 `_routeSourceId = 'route-source'` 단수 1개.
  `setGeoJsonSource`로 **선택된 1개 경로(`routePolyline`)만** 갱신. `allRoutes`(3개 전체)는 레이어에 올라오지 않음.
- **allRoutes 접근**: `mapInteractionProvider.allRoutes`에 3개 경로 `List<List<LatLng>>`로 저장됨 (라인 602, 557-561). `_updateRouteLayer` 호출 시점에 접근 가능.
- **확장 방법**: 비선택 경로를 회색으로 표시하려면
  - 소스 2개 (`route-bg-source` + `route-source`) + 레이어 2개 (`route-bg-layer` + `route-layer`) 추가 필요.
  - `route-bg-source`에 선택 외 경로를 MultiLineString GeoJSON으로 통합 업로드.
  - `_initRouteLayer`를 수정해 bg 소스/레이어 먼저 추가하면 됨 (단, `_buildRouteGeoJson`·`_updateRouteLayer`도 확장 필요).
