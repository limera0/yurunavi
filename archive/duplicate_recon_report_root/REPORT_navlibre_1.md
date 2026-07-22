# REPORT: nav_screen MapLibre 이관 커밋 ① 골격

커밋: afa8b76  
날짜: 2026-06-09  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증 결과

### 라인번호 일치 확인
RECON_navlibre.md의 모든 라인번호가 현재 nav_screen.dart와 정확히 일치:
- L49: `MapController _mapCtrl` ✅
- L159: `_mapCtrl.dispose()` ✅
- L213: `_mapCtrl.rotate(-pos.heading)` ✅
- L515: `_mapCtrl.move(loc, _navZoom)` ✅
- L547-627: `FlutterMap` 블록 ✅

### API 시그니처 실측
- `MapLibreMapController` → `ChangeNotifier` (dispose 불필요) ✅
- `CameraUpdate.bearingTo(double bearing)` → `platform_interface-0.26.1/lib/src/camera.dart:169` ✅
- `OnCameraMoveCallback = void Function(CameraPosition cameraPosition)` → `controller.dart:59` ✅
- `MapLibreMap.onCameraMove` 파라미터 → `maplibre_map.dart:53, 295` ✅
- `animateCamera` 반환 타입: `Future<bool?>` (비nullable) → `?.then()` 사용 시 경고 발생 → 변수 분리로 해결

### 체크포인트 커밋
nav_screen.dart 미수정 상태 → 생략.

---

## 변경 요약

### 파일: `lib/features/navigation/presentation/nav_screen.dart`
**96 insertions, 81 deletions**

| 변경 | 내용 |
|---|---|
| import 추가 | `package:maplibre_gl/maplibre_gl.dart as ml` (flutter_map은 임시 오버레이용 유지) |
| 컨트롤러 교체 | `MapController _mapCtrl` → `ml.MapLibreMapController? _mlCtrl` |
| 신규 필드 | `bool _styleLoaded = false`, `bool _programmaticCamera = false` |
| dispose 수정 | `_mapCtrl.dispose()` 제거 |
| heading 회전 | `_mapCtrl.rotate(-pos.heading)` → `animateCamera(CameraUpdate.bearingTo(pos.heading))` + `_programmaticCamera` 가드 + `_styleLoaded` 가드 |
| 카메라 이동 | `_mapCtrl.move(loc, _navZoom)` → `animateCamera(CameraUpdate.newLatLngZoom)` + 가드 |
| 수동모드 감지 | `MapEventMoveStart + MapEventSource` → `onCameraMove + !_programmaticCamera` |
| 헬퍼 추가 | `_toMl(LatLng) → ml.LatLng` |
| 스타일 콜백 | `_onStyleLoaded()` 메서드 (②③ 훅 예약) |
| 지도 위젯 교체 | `FlutterMap + TileLayer` → `ml.MapLibreMap(styleString: osm_liberty_yurunavi.json)` |
| 임시 오버레이 | `IgnorePointer(FlutterMap(InteractiveFlag.none))` 안에 기존 PolylineLayer + MarkerLayer 유지 |

### null-aware 경고 수정
`animateCamera` 반환 타입이 `Future<bool?>` (비nullable)이므로 체인 `?.then()` 에 경고 발생.
변수에 먼저 할당 후 `?.then()` 으로 분리:
```dart
final bf = _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(pos.heading));
bf?.then((_) { if (mounted) _programmaticCamera = false; });
```

---

## 검증 결과

```
flutter analyze lib/features/navigation/presentation/nav_screen.dart
→ No issues found! (ran in 1.5s)

flutter build apk --debug
→ ✓ Built build/app/outputs/flutter-apk/app-debug.apk  (22.1s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

확인 항목:
1. 내비 진입 → 지도가 OSM 표준 타일 아닌 **자체서버 스타일(osm_liberty)로 표시**되는지
2. 경로/마커가 임시 Flutter 오버레이로 **어딘가에 보이는지** (정렬 불일치 허용)
3. 지도 수동 드래그 → 10초 후 현위치 복귀 배너 + 재센터링 동작하는지
4. 지도가 회전(진행방향 연동)하는지 — 정지 시 회전 없음, 주행 시 bearing 연동

---

## 다음 커밋 예고

### 커밋 ② — 경로 폴리라인 GeoJSON 레이어
**범위**: nav_screen.dart만
- `_buildRouteGeoJson()` 헬퍼 + `_routeSourceId` 상수
- `_onStyleLoaded()` 내 `_initRouteLayer()` (addGeoJsonSource + addLineLayer, 색상 `#F28C28`)
- `_reroute()` 성공 후 `setGeoJsonSource()` 갱신
- `IgnorePointer(FlutterMap)` 내 PolylineLayer 제거

### 커밋 ③ — 마커 Circle/Symbol화
**범위**: nav_screen.dart만
- `onStyleLoadedCallback`에서 addImage(`pointer_red`, `pointer_yellow`)
- `_ensureLocMarker()` (Circle), `_syncDestMarker()`, `_syncWaypointMarkers()` (Symbol)
- MarkerLayer 제거 + IgnorePointer(FlutterMap) 블록 완전 제거

### 커밋 ④ — 카메라 bearing 통합 + flutter_map 최종 삭제
**범위**: nav_screen.dart + pubspec.yaml (flutter_map 삭제 여부는 main_map_screen 확인 후)
- `_currentBearing` 필드, bearing + zoom을 newCameraPosition으로 통합
- `import 'package:flutter_map/flutter_map.dart'` 제거
