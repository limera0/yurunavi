# RECON N2: 경로 폴리라인 색상 처리 현황

대상: `lib/features/map/presentation/main_map_screen.dart`  
       `lib/features/navigation/presentation/nav_screen.dart`

---

## 지도 화면(main_map_screen) 폴리라인 색 지정

### LineLayer 구성 (main_map_screen.dart:258-291)

| 레이어 | 색상 | 선 굵기 | 용도 |
|--------|------|---------|------|
| `_routeBgLayerId` | `'#9E9E9E'` (회색) :272 | 4.0 | 미선택 경로 전부 |
| `_routeLayerId` | `'#1E5AFF'` (파란색) :285 | 6.0 | 선택된 경로 1개 |

### 색 분기 로직 (main_map_screen.dart:359-375)

```dart
void _updateRouteLayer(List<LatLng> points) {           // :359
  _mlCtrl?.setGeoJsonSource(_routeSourceId, _buildRouteGeoJson(points));  // 선택: 파란색
  final selIdx = state.selectedRouteIdx;
  if (allRoutes.length > 1) {
    final bgRoutes = [for (int i = 0; i < allRoutes.length; i++)
                       if (i != selIdx) allRoutes[i]];  // 나머지 모두 회색
    _mlCtrl?.setGeoJsonSource(_routeBgSourceId, _buildBgGeoJson(bgRoutes));
  }
}
```

→ **선택=`#1E5AFF`(파란색) / 미선택=`#9E9E9E`(회색) 2단계 고정.**  
→ **코스별(시골/지방/국도) 색 분기 없음.** 색은 선택 여부에만 의존.

### 코스 시트 카드 색 (_CourseSheet, main_map_screen.dart:1403-1406)

```dart
static const _routes = [
  _RouteInfo('시골길로\n느긋하게', AppColors.mapCourse),   // #4CAF50 (녹색)
  _RouteInfo('지방도로\n여유롭게', AppColors.tertiary),     // theme tertiary
  _RouteInfo('국도로\n빠르게',     AppColors.primary),      // theme primary
];
```

→ 코스 식별 색은 **UI 카드 내부**에만 존재. 지도 폴리라인(LineLayer)에는 미적용.

---

## 주행 화면(nav_screen) 경로 색

nav_screen.dart:744:
```dart
lineColor: '#F28C28',  // nav 오렌지색 유지
lineWidth: 6.0,
```

→ 주행 중 경로: 고정 오렌지색. 코스 분기 없음.

---

## 판정

| 항목 | 현황 |
|------|------|
| 선택 경로 색 | `#1E5AFF` 고정 (파란색) |
| 미선택 경로 색 | `#9E9E9E` 고정 (회색) |
| 코스별(시골/지방/국도) 폴리라인 색 분기 | **없음** |
| 주행 중 경로 색 | `#F28C28` 고정 (오렌지) |

코스별 색 분기를 구현하려면 `_buildBgGeoJson`을 코스 인덱스별로 분리하고  
각 LineLayer에 코스 색(mapCourse/tertiary/primary)을 적용해야 한다.
