# RECON N3: 초기 지도 줌 레벨 확인

---

## main_map_screen (탐색/경로탐색 화면)

| 항목 | 값 | file:line |
|------|----|-----------|
| 초기값 필드 | `_currentZoom = 16.0` | main_map_screen.dart:117 |
| CameraPosition | `zoom: _currentZoom` (= 16.0) | main_map_screen.dart:796 |
| 폴백 좌표 | `kInitialMapView = LatLng(36.5, 127.5)` (한국 지리 중심, GPS 없을 때) | main_map_screen.dart:35 |
| 실제 target | `_origin ?? _lastKnown ?? kInitialMapView` | main_map_screen.dart:795 |

줌 16은 사용자 제스처로 변경되면 `_currentZoom`에 반영됨 (main_map_screen.dart:832-833).  
GPS 위치 이동 시 `_currentZoom.clamp(10.0, 14.0)` 으로 clamping하여 카메라 이동 (main_map_screen.dart:187, 206, 217).

---

## nav_screen (주행 안내 화면)

| 항목 | 값 | file:line |
|------|----|-----------|
| 초기값 필드 | `_navZoom = 15.0` | nav_screen.dart:100 |
| CameraPosition | `zoom: 15` (하드코딩) | nav_screen.dart:834 |
| 폴백 좌표 | `_kInitialMapView = LatLng(37.5665, 126.9780)` (서울 광화문) | nav_screen.dart:28 |
| 실제 target | `_currentPos ?? _kInitialMapView` | nav_screen.dart:833 |

속도 연동 줌 함수 `_zoomForSpeed(kmh)` (nav_screen.dart:696):
```
0 km/h → z18
20 km/h → z16
60+ km/h → z14
```
GPS 틱마다 `_navZoom += diff.clamp(-0.3, 0.3)` 으로 부드럽게 수렴 (nav_screen.dart:706-707).

---

## 요약

| 화면 | 초기 줌 | 폴백 좌표 |
|------|---------|-----------|
| main_map_screen | **z16.0** | 한국 지리 중심 (36.5, 127.5) |
| nav_screen | **z15** (하드코딩) / `_navZoom=15.0` | 서울 광화문 (37.5665, 126.9780) |
