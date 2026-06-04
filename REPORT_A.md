# REPORT_A — A묶음 4건 실행 결과

## 1. '좋은 장소를 찾고 있어요' 멘트 제거 (commit b53f1bc)

- **수정 위치**: `main_map_screen.dart` 라인 703–717 (loading overlay Row children)
- **변경**: `SizedBox(width:12)` + `Text('좋은 장소를 찾고 있어요…')` 제거, `CircularProgressIndicator`만 남김
- **커밋**: `fix(map): remove leftover snap loading text (keep spinner)`

---

## 2. '요약' 헤더/버튼 + '최단/최속' 뱃지 제거 (commit 1492ce2)

- **_showRouteSummary 함수** (라인 440–484): 全삭제. 유일한 호출처는 라인 848 `onShowSummary: _showRouteSummary` 배선뿐이었으므로 함께 제거.
- **_CourseSheet.onShowSummary 파라미터 + '요약' 버튼**: 클래스 필드(라인 1209, 1217) 및 버튼 렌더 블록(라인 1258–1269) 제거.
- **isBestDist/isBestTime**: `_RouteCard` 필드(1335–1336), 생성자 파라미터(1346–1347), 전달식(bestDist/bestTime 계산 포함) 제거. `isBestFun/bestWs`는 유지 (별도 렌더에 사용 중).
- **死코드 위젯 `_CompChip`, `_SummaryRow`** 제거 (analyze unused_element 경고 → 삭제).
- **死코드 여부**: `_showRouteSummary` 및 두 위젯 모두 이 파일에서만 사용 → 전부 제거.
- **커밋**: `feat(map): remove summary header & shortest/fastest badges (#4)`

---

## 3. 줌 자동맞춤 (commit dc9e8a9)

- **수정 위치**: `main_map_screen.dart` `_updateRouteLayer(List<LatLng> points)`
- **변경**: `points`의 실제 min/max lat·lng로 `ml.LatLngBounds` 계산 후 `animateCamera(newLatLngBounds)` 호출. `points.isEmpty`이면 카메라 호출 건너뜀.
- **효과**: 카드 전환 및 최초 경로 표시 시 해당 경로 선형에 맞게 카메라 자동 맞춤.
- **커밋**: `fix(map): fit camera to actual route geometry on update (#5)`

---

## 4. 대안경로 회색 동시 표시 (commit 6954bd1)

- **수정 위치**: `main_map_screen.dart` — 상수 2개 추가, `_buildBgGeoJson` 헬퍼 추가, `_initRouteLayer` 수정, `_updateRouteLayer` 수정
- **변경**: `route-bg-source` + `route-bg-layer`(회색 `#9E9E9E`, lineWidth 4) 추가. `_initRouteLayer`에서 bg 레이어를 선택 레이어보다 먼저 `addLineLayer` 하여 선택 경로가 위에 렌더됨. `_updateRouteLayer`에서 `allRoutes` 중 `selIdx` 외 경로를 `_buildBgGeoJson`으로 묶어 bg 소스에 set.
- **가드**: `allRoutes.length <= 1`이면 bg 소스를 빈 FeatureCollection으로 set.
- **커밋**: `feat(map): show non-selected routes in grey (#3)`

---

## 검증

- **flutter analyze**: 0 issues
- **flutter build apk --debug**: ✓ Built (KGP 경고 무해)
