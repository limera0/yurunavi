# RECON_reroute.md — 재탐색 heading 미전달 (증상3: 제자리 유턴)

생성일: 2026-06-17  
범위: nav_screen.dart + routing_service.dart (코드 변경 0)

---

## §D 재탐색 요청이 Valhalla에 heading/bearing을 싣는지

### D1. 재탐색 호출 경로

```
_onPosition()  →  _checkOffRoute(loc)  →  (3초 debounce)  →  _reroute(_currentPos)
```

- `_currentPos` 는 `LatLng` 타입 (위도·경도만, heading 없음)  
  **nav_screen.dart:68, 469–470**

- `pos.heading` 은 `_onPosition` (nav_screen.dart:364) 에서 **지도 카메라 회전에만** 사용됨.  
  별도 상태 필드(`_currentHeading` 등)로 저장되지 않음 — heading 보관 코드 없음.

### D2. RoutingService.fetchRoutes() 시그니처

```dart
// routing_service.dart:123–127
static Future<List<RouteResult>> fetchRoutes({
  required LatLng origin,
  required LatLng destination,
  List<LatLng> waypoints = const [],
}) async {
```

heading 파라미터 없음.

### D3. Valhalla 요청 JSON 구조

```dart
// routing_service.dart:128–133
final locations = [
  {'lon': origin.longitude, 'lat': origin.latitude},  // ← heading 필드 없음
  for (final w in waypoints) {'lon': w.longitude, 'lat': w.latitude},
  {'lon': destination.longitude, 'lat': destination.latitude},
];
```

모든 위치 객체에 `heading`/`heading_tolerance` 키 없음.

---

## §D curl A/B — Valhalla 포크 heading 수용 여부

**서버**: `https://valhalla.westinx.com`

### A. heading 없음 (현재 코드 방식)

```bash
curl -X POST https://valhalla.westinx.com/route \
  -H 'Content-Type: application/json' \
  -d '{"locations":[{"lon":127.0,"lat":37.5},{"lon":127.1,"lat":37.6}],
       "costing":"motorcycle","costing_options":{"motorcycle":{}}}'
```

결과: **HTTP 200** ✅

### B. heading 포함 (수정 후 예상 방식)

```bash
curl -X POST https://valhalla.westinx.com/route \
  -H 'Content-Type: application/json' \
  -d '{"locations":[{"lon":127.0,"lat":37.5,"heading":90,"heading_tolerance":45},
       {"lon":127.1,"lat":37.6}],
       "costing":"motorcycle","costing_options":{"motorcycle":{}}}'
```

결과: **HTTP 200** ✅  
응답 trip.locations[0]에 `"heading": 90` 에코됨 — **파라미터 수용 확인**.

---

## §D 결론

| 항목 | 상태 |
|---|---|
| Valhalla 포크 heading 수용 | ✅ 수용 (curl B 확인) |
| Flutter 코드가 heading 전달 | ❌ 없음 (routing_service.dart:128–133) |
| `pos.heading` 상태 보관 | ❌ 없음 (지도 회전에만 일회 소비) |
| 재탐색 호출부 heading 인자 | ❌ 없음 (`_reroute(LatLng)` — nav_screen.dart:493) |

**제자리 유턴 원인**: Valhalla가 진행 방향을 모르기 때문에 현위치에서 모든 방향의 도로를 동등하게 고려하여 경로를 계획함. 유턴이 거리상 유리한 경우 선택됨.

---

## §D 수정 방향 (구현 아님)

1. `nav_screen.dart` — `double? _currentHeading` 상태 추가, `_onPosition`에서 `pos.heading >= 0` 일 때 갱신  
2. `routing_service.dart:fetchRoutes()` — `double? heading` 파라미터 추가, `locations[0]`에 `'heading': heading.round(), 'heading_tolerance': 45` 삽입 (heading != null 조건부)  
3. `nav_screen.dart:_reroute()` — `_currentHeading`을 `fetchRoutes`에 전달

우선순위: LOC-UNIFY 이후 (위치 파이프라인 통합 시 동시 처리 권장)
