# REPORT: nav_screen MapLibre 이관 커밋 ② 경로 폴리라인

커밋: b3a853c  
날짜: 2026-06-10  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

| 항목 | 결과 |
|---|---|
| 경로 데이터 필드 | `_routePoints` (List<LatLng>) — L82, initState L126, _reroute L335 갱신 |
| `_reroute()` setState 위치 | L334-337 (points + durationMin 동시 갱신) |
| `_onStyleLoaded()` 현재 상태 | setState만 있고 placeholder 주석 — 수정 대상 |
| main `_buildRouteGeoJson` | L205-221 (lng,lat 순서 확인) |
| main `_initRouteLayer` | L240-274 (bg 레이어 포함, belowLayerId circleManager) |
| main `setGeoJsonSource` 갱신 | `_updateRouteLayer()` L344 |

nav에는 대체경로(bg 레이어) 없음 → 단일 레이어만 구현.

---

## 변경 요약 (53+/12−)

### 1. 상수 추가
```dart
static const _navRouteSourceId = 'nav-route-source';
static const _navRouteLayerId  = 'nav-route-layer';
```
main_map_screen의 `route-source` 와 충돌 방지를 위해 `nav-` 접두어.

### 2. `_buildRouteGeoJson()` 헬퍼
main_map_screen에서 직접 복사. `[p.longitude, p.latitude]` 순서 (GeoJSON 규격).

### 3. `_initRouteLayer()` 비동기 메서드
```dart
await ctrl.addGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson([]));
await ctrl.addLineLayer(
  _navRouteSourceId, _navRouteLayerId,
  const ml.LineLayerProperties(
    lineColor: '#F28C28', lineWidth: 6.0, lineCap: 'round', lineJoin: 'round',
  ),
);
```
`belowLayerId`: ③에서 Circle 레이어 추가 후 z-order 설정 예정.

### 4. `_onStyleLoaded()` 갱신
```dart
_initRouteLayer().whenComplete(() {
  if (_routePoints.length >= 2 && mounted) {
    _mlCtrl?.setGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson(_routePoints));
  }
});
```
스타일 로드 전 경로가 이미 전달된 경우(내비 진입 즉시) 레이어 설치 완료 후 즉시 반영.

### 5. `_reroute()` 갱신
```dart
if (_styleLoaded) {
  _mlCtrl?.setGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson(newPoints));
}
```
재탐색 성공 시 GeoJSON 소스 갱신. `_styleLoaded` 가드로 레이어 미설치 시 skip.

### 6. 임시 오버레이 PolylineLayer 제거
`IgnorePointer(FlutterMap)` 내 PolylineLayer 블록 제거.
MarkerLayer는 커밋③까지 유지 (주석으로 명시).

---

## 검증

```
flutter analyze  →  No issues found! (1.5s)
flutter build apk --debug  →  ✓ Built app-debug.apk  (11.2s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| ① | 경로 오렌지선 표시 | 지도 위에 #F28C28 선 표시 |
| ② | 도로 정합 | 실제 도로 위에 선이 정확히 얹힘 (이전 오버레이처럼 어긋나지 않음) |
| ③ | 카메라 이동/회전 시 | 선이 지도에 붙어 따라옴 |
| ④ | 재탐색 시 | 새 경로선으로 갱신 |
| ⑤ | 임시 마커 | 여전히 어긋나 보임 — 정상, 커밋③에서 해소 |
