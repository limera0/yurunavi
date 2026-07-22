# RECON_ZORDER — 마커 z-order 버그 사전조사

## 버그 루트코즈 (실코드 확인)

`maplibre_gl-0.26.1/lib/src/controller.dart:205~258`

플랫폼의 `onMapStyleLoadedPlatform` 이벤트 처리 순서:

```
1. 기존 매니저 dispose
2. annotationOrder 순으로 각 AnnotationManager.initialize() — 레이어 추가
3. onStyleLoadedCallback?.call()  ← 우리 콜백 시작
   3-1. _initRouteLayer() → route-bg-layer, route-layer 추가  ← 맨 위에 쌓임
   3-2. _ensureLocationMarker() → addCircle() → circleManager.add() (레이어 재추가 없음)
```

**결론**: CircleManager 레이어가 step-2에서 먼저 추가되고, 경로 레이어가 step-3에서 나중에 추가된다.
MapLibre GL에서 나중에 추가된 레이어가 위(전면)에 그려지므로 **경로선이 원형 마커 위를 덮음**.

---

## 1) addLineLayer / addCircleLayer — belowLayerId 지원 여부

**controller.dart:654-676 (addLineLayer)**
```dart
Future<void> addLineLayer(
  String sourceId,
  String layerId,
  LineLayerProperties properties, {
  String? belowLayerId,   // ← 지원 확인
  String? sourceLayer,
  double? minzoom,
  double? maxzoom,
  dynamic filter,
  bool enableInteraction = true,
}) async { ... }
```

**controller.dart:801-823 (addCircleLayer)**
```dart
Future<void> addCircleLayer(
  String sourceId,
  String layerId,
  CircleLayerProperties properties, {
  String? belowLayerId,   // ← 지원 확인
  ...
}) async { ... }
```

→ **addLineLayer, addCircleLayer 모두 `belowLayerId` named param 지원 확인.**

---

## 2) Annotation Manager 레이어 id 구조

### AnnotationManager 베이스 클래스 (annotation_manager.dart:123)
```dart
String _makeLayerId(int layerIndex) => "${id}_$layerIndex";
List<String> get layerIds => [
  for (int i = 0; i < allLayerProperties.length; i++) _makeLayerId(i),
];
```
- `id`는 `getRandomString()` — **컴파일타임에 알 수 없음**
- 외부 접근: `_mlCtrl?.circleManager?.layerIds` (공개 필드/getter 확인)

### CircleManager (annotation_manager.dart:290-313)
```dart
class CircleManager extends AnnotationManager<Circle> {
  @override
  List<LayerProperties> get allLayerProperties => const [
    CircleLayerProperties(...)  // 레이어 1개
  ];
}
```
- `allLayerProperties.length == 1` → layerIds = `["${randomId}_0"]` (단 1개)
- `_mlCtrl?.circleManager?.layerIds.first` 로 접근 가능

### 접근 가능 여부 확인
- `controller.dart:304`: `CircleManager? circleManager;` — `_` 없음 → **공개 필드** ✓
- `annotation_manager.dart`는 `maplibre_gl.dart`의 `part` 파일 (`maplibre_gl.dart:107`) → 라이브러리 내부 공개 심볼 외부 접근 가능 ✓
- 단, `CircleManager` 타입 자체는 `maplibre_gl.dart` export 목록에 없음 → 타입 어노테이션 불가하나, **`.layerIds`까지 체이닝하면 결과는 `List<String>?`** → 타입 추론으로 사용 가능 ✓

---

## 3) MapLibreMap 위젯 annotationOrder

**maplibre_map.dart (line 56)** 기본값:
```dart
annotationOrder = const [
  AnnotationType.line,
  AnnotationType.symbol,
  AnnotationType.circle,   // ← 3번째 — symbol 위, fill 아래
  AnnotationType.fill,
],
```
현재 `main_map_screen.dart`의 `MapLibreMap` 위젯 호출에 `annotationOrder` 미지정 → **기본값 사용**.

Circle 레이어는 스타일 로드 시 (onStyleLoadedCallback 이전에) 이미 추가됨. 그 뒤에 `_initRouteLayer`가 경로 레이어를 추가하므로 경로가 위.

---

## 4) 현재 코드 상태 (main_map_screen.dart)

### _initRouteLayer (line 235)
```dart
Future<void> _initRouteLayer() async {
  await ctrl.addGeoJsonSource(_routeBgSourceId, ...);
  await ctrl.addLineLayer(_routeBgSourceId, _routeBgLayerId, ...);  // belowLayerId 없음
  await ctrl.addGeoJsonSource(_routeSourceId, ...);
  await ctrl.addLineLayer(_routeSourceId, _routeLayerId, ...);      // belowLayerId 없음
}
```
→ belowLayerId 미지정 → 경로 레이어가 맨 위에 추가됨.

### _updateRouteLayer (line 264)
```dart
void _updateRouteLayer(List<LatLng> points) {
  _mlCtrl?.setGeoJsonSource(...)  // 데이터만 업데이트, 레이어 재추가 없음
  ...
}
```
→ 레이어 순서 변경 없음. 경로 레이어 = **1회 생성** 확인.

---

## 5) 수정 방안 판정

### Option A (권장): `_initRouteLayer`에 `belowLayerId` 추가 (최소 변경)

```dart
Future<void> _initRouteLayer() async {
  final ctrl = _mlCtrl;
  if (ctrl == null) return;
  // 실행 시점에 circleManager가 이미 초기화되어 있으므로 layerIds 접근 가능
  final circleLyr = ctrl.circleManager?.layerIds.isNotEmpty == true
      ? ctrl.circleManager!.layerIds.first
      : null;

  await ctrl.addGeoJsonSource(_routeBgSourceId, _buildBgGeoJson([]));
  await ctrl.addLineLayer(
    _routeBgSourceId, _routeBgLayerId, ...,
    belowLayerId: circleLyr,  // route-bg를 circle 레이어 아래에 삽입
  );
  await ctrl.addGeoJsonSource(_routeSourceId, _buildRouteGeoJson([]));
  await ctrl.addLineLayer(
    _routeSourceId, _routeLayerId, ...,
    belowLayerId: circleLyr,  // route를 circle 레이어 아래에 삽입
  );
}
```

- z-order 결과: route-bg < route-selected < circle-marker ✓
- 변경 파일: `main_map_screen.dart` 단 1곳 (`_initRouteLayer`)
- 위험도: `circleLyr == null`이면 기존과 동일(맨 위)로 fallback — 안전

### Option B (대안): `addCircle` → `addGeoJsonSource + addCircleLayer` 교체

- `_initRouteLayer` 안에 마커 source/layer도 명시적 id로 추가 (route layers 이후)
- `_ensureLocationMarker` / `_ensureDestMarker` → `setGeoJsonSource`만 사용
- `_removeDestMarker` → `setGeoJsonSource(emptyFeatureCollection)`
- 장점: layer id 완전 결정론적, 런타임 랜덤 id 의존 없음
- 단점: `_locMarker`/`_destMarker` Circle 객체 모두 제거 + 메서드 전면 개편 → 코드 변경 범위 큼

### 권장: **Option A**
- 수정 범위 최소 (`_initRouteLayer` 2개 addLineLayer 호출에 `belowLayerId` 추가)
- `_mlCtrl?.circleManager?.layerIds.first` 접근성 실파일 확인 완료
- `circleLyr == null` 가드로 안전 fallback 보장

---

## 6) 미확인 항목
- `AnnotationType` 타입이 `ml.AnnotationType` 프리픽스로 외부에서 사용 가능한지 (maplibre_gl.dart export 목록 미확인) — 실행 턴에서 `annotationOrder` 파라미터 건드릴 경우 확인 필요. 단, Option A는 `annotationOrder` 변경 불필요.
- Android 실기기에서 실제 z-order가 기대와 일치하는지 — GL 렌더러 구현에 따라 다를 수 있음. Option A 적용 후 폰 실측 필수.
