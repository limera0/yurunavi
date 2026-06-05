# REPORT_WPMARKER2 — 경유지 노랑핀 마커 연결 보고

## 0단계 판정

| 항목 | 결과 |
|------|------|
| `pointer_yellow.png` 픽셀 | **96×96 RGBA** — red와 동일 |
| `_kWpIconSize` 초기값 | **1.5** (red와 동일 기준, 폰 실측으로 조정) |
| waypoints 타입 | `List<LatLng>` (`latlong2.LatLng`) — `_toMl(LatLng p)` 그대로 사용 가능 |
| addImage 등록 위치 | onStyleLoadedCallback line 752 (pointer_red 등록) 바로 아래 |
| ref.listen 추가 위치 | line 686-690 블록 내, routePolyline if 아래 |
| `_clearDestination` 연결 위치 | `_removeDestMarker()` 줄 바로 아래 |

→ 전원 PASS.

---

## 변경 diff

### ① 필드/상수 추가 (line 90, 94-95)

```dart
// 추가:
List<ml.Symbol> _waypointMarkers = [];
static const String _kWpIcon = 'pointer_yellow';
static const double _kWpIconSize = 1.5; // 96px PNG, 폰 실측으로 조정
```

### ② addImage 등록 (onStyleLoadedCallback)

```dart
// BEFORE:
final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
// B1: 현위치 마커 ...

// AFTER:
final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
// B1: 현위치 마커 ...
```

### ③ `_syncWaypointMarkers` 메서드 추가 (`_removeDestMarker` 바로 뒤)

```dart
Future<void> _syncWaypointMarkers(List<LatLng> waypoints) async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;
  for (final s in _waypointMarkers) {
    await c.removeSymbol(s);
  }
  _waypointMarkers = [];
  for (final wp in waypoints) {
    final s = await c.addSymbol(ml.SymbolOptions(
      geometry: _toMl(wp),
      iconImage: _kWpIcon,
      iconSize: _kWpIconSize,
      iconAnchor: 'bottom',
    ));
    _waypointMarkers.add(s);
  }
}
```

### ④ ref.listen waypoints 감지 추가

```dart
// BEFORE:
ref.listen<MapInteractionState>(mapInteractionProvider, (prev, next) {
  if (prev?.routePolyline != next.routePolyline) {
    _updateRouteLayer(next.routePolyline);
  }
});

// AFTER:
ref.listen<MapInteractionState>(mapInteractionProvider, (prev, next) {
  if (prev?.routePolyline != next.routePolyline) {
    _updateRouteLayer(next.routePolyline);
  }
  if (prev?.waypoints != next.waypoints) {
    _syncWaypointMarkers(next.waypoints); // unawaited
  }
});
```

### ⑤ `_clearDestination` 경유지 핀 정리 연결

```dart
// BEFORE:
_removeDestMarker(); // unawaited — B2

// AFTER:
_removeDestMarker(); // unawaited — B2
_syncWaypointMarkers(const []); // unawaited — 경유지 핀 전체 제거
```

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.2s)

---

## 폰 실측 체크리스트

- [ ] 목적지 확정 후 경로A로 경유지 추가 → 노랑핀 표시
- [ ] 경유지 여러 개 추가 → 노랑핀 여러 개, 각 좌표에 정확히 (iconAnchor bottom)
- [ ] 노랑핀 크기 적절 (부적절 시 `_kWpIconSize` 권장값: 작으면 2.0, 크면 1.0)
- [ ] 노랑핀이 경로선 위 (z-order 정상)
- [ ] 노랑핀 vs 빨강(목적지)핀 겹칠 때 순서 어색하지 않은지
- [ ] 목적지 해제/내비 종료 시 노랑핀 모두 사라짐 (`_clearDestination` → `_syncWaypointMarkers([])`)
- [ ] 현위치 초록 원·목적지 빨강핀 회귀 없음

## 안 보이면

```
adb logcat -d | grep -iE "symbol|image|pointer|yellow"
```

## z-order 어색하면

symbolManager 내 추가 순서에 의존 — 경유지 핀이 목적지 핀 위에 표시될 수 있음. 후속 작업 후보로 기록 (이번 커밋 범위 밖).
