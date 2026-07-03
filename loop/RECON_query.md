# RECON_query — queryRenderedFeatures 실측 (읽기 전용)
규칙: 읽기 전용, 코드변경 금지, 모호하면 중단+원문보고. 결과 하단 append.
- [ ] maplibre_gl 0.26.1 MapLibreMapController.queryRenderedFeatures 시그니처 실측
      rg -n "queryRenderedFeatures" ~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.1/
      → rect(LatLng 2점/Rect) vs point+radius 중 무엇? layerIds 필터 인자 있나?
- [ ] 반환 타입/구조: List<dynamic>? 각 원소의 properties 접근 경로 (feature['properties']?)
- [ ] 좌표→화면px 변환 함수 존재? (screenDist 계산용)
      rg -n "toScreenLocation|toLatLng" ~/.pub-cache/.../maplibre_gl-0.26.1/
출력: 시그니처 원문 + properties 접근 경로 + toScreenLocation 유무.

---

## 실측 결과 (2026-06-29)

### 1. queryRenderedFeatures 시그니처

**point 버전** (`controller.dart:1562`, `method_channel_maplibre_gl.dart:394`)
```dart
Future<List> queryRenderedFeatures(
  Point<double> point,   // 화면 좌표 (픽셀), dart:math Point
  List<String> layerIds, // 빈 리스트 [] = 전체 레이어
  List<Object>? filter,  // MapLibre expression, null 가능
) async
```

**rect 버전** (`controller.dart:1571`)
```dart
Future<List> queryRenderedFeaturesInRect(
  Rect rect,             // dart:ui Rect (left/top/right/bottom, 화면 픽셀)
  List<String> layerIds,
  String? filter,        // ⚠️ String? (point 버전과 달리 JSON 문자열)
) async
```

→ `point` 버전이 주력. `radius` 개념은 없음 — 반경 쿼리가 필요하면 rect로 bounding box를 잡아야 함.

### 2. 반환 타입 및 properties 접근 경로

반환: `List<dynamic>` — 각 원소는 **jsonDecode(feature)** 결과 (GeoJSON Feature Map)

```dart
// Android native: feature.toJson() → JSON 문자열 → Dart에서 jsonDecode
// method_channel: reply['features'].map((f) => jsonDecode(f)).toList()
```

원소 접근 경로:
```dart
final List features = await controller.queryRenderedFeatures(point, ['layer-id'], null);
for (final feature in features) {
  final props = feature['properties'] as Map;   // feature['properties']
  final geom  = feature['geometry'];            // feature['geometry']
  final id    = feature['id'];                  // optional
}
```

### 3. 좌표 변환 함수 (`controller.dart:1755`)

```dart
// LatLng → 화면 픽셀 Point
Future<Point> toScreenLocation(LatLng latLng) async
Future<List<Point>> toScreenLocationBatch(Iterable<LatLng> latLngs) async

// 화면 픽셀 → LatLng
Future<LatLng> toLatLng(Point screenLocation) async

// 1픽셀 = 몇 미터
Future<double> getMetersPerPixelAtLatitude(double latitude) async
```

→ `toScreenLocation` 존재 확인. screenDist 계산은 `toScreenLocation` 2점 → 유클리드 거리로 가능.
→ `getMetersPerPixelAtLatitude`로 미터→픽셀 역산도 가능.

### 요약

| 항목 | 실측값 |
|---|---|
| point 쿼리 인자 | `Point<double>` (화면px) + `List<String>` layerIds + `List<Object>?` filter |
| rect 쿼리 인자 | `Rect` (화면px) + `List<String>` layerIds + `String?` filter |
| radius 쿼리 | **없음** — rect bounding box로 대체 |
| 반환 타입 | `List<dynamic>` (jsonDecode된 GeoJSON Feature Map) |
| properties 접근 | `feature['properties']` |
| 좌표→픽셀 | `toScreenLocation(LatLng)` → `Point` |
| 픽셀→좌표 | `toLatLng(Point)` → `LatLng` |
| m/px 환산 | `getMetersPerPixelAtLatitude(lat)` |