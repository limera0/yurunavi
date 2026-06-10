# RECON_reroute.md — 재탐색 heading 무시 & maneuver/TTS 미동작 정찰

조사 대상 브랜치: `feat/maplibre-migration` / 정찰일 2026-06-10
**본 문서는 정찰 산출물이며 코드는 한 글자도 수정하지 않음.**

> ⚠️ 실제 코드 구조는 CLAUDE.md의 `lib/modules/navigation` 과 다름.
> 네비 화면 = `lib/features/navigation/presentation/nav_screen.dart`
> 라우팅 = `lib/services/routing_service.dart`

---

## 1. 요약 (판정)

| 증상 | 판정 | 한 줄 결론 |
|---|---|---|
| **증상3 (heading 무시)** | **원인 확정** | `fetchRoutes`에 heading 파라미터 자체가 없음. 요청 JSON `locations`는 lon/lat만 보냄. **최초·재탐색 모두** heading 미전송 (재탐색만의 문제가 아님). |
| **증상4 (maneuver·TTS 미동작)** | **원인 확정** | `_reroute`의 `setState`가 `_routePoints`/`_durationMin`만 갱신. `_steps`는 `late final`이라 갱신 불가하며, `_stepEndDistM`·`_stepIdx`·`_lastAnnouncedIdx`·`_preAnnounced` 전부 리셋 안 함. 새 경로의 maneuvers는 수신되지만 버려짐. |
| **D (Valhalla fork heading 지원)** | **미확인** | 리포에 Valhalla 소스 없음(원격 `valhalla.westinx.com`). 표준 upstream Valhalla는 `heading`/`heading_tolerance`를 지원하나 포크 동작은 curl 검증 필요. |

---

## 2. 증상3 (heading) — 근거

### A. 재탐색 트리거
- 이탈 감지: `_checkOffRoute(LatLng loc)` — `nav_screen.dart:320`
  - 판정 거리 상수: `static const _kOffRouteM = 20.0;` (`nav_screen.dart:89`)
  - 디바운스 상수: `static const _kDebounceSec = 3;` (`nav_screen.dart:90`)
  - 트리거 조건식 (`nav_screen.dart:327-334`):
    ```dart
    if (minDist > _kOffRouteM) {
      _offRouteDebounce ??= Timer(const Duration(seconds: _kDebounceSec), () {
        _offRouteDebounce = null;
        final current = _currentPos;
        if (current != null) _reroute(current);   // ← 현재 위치만 전달
      });
    }
    ```
  - **트리거가 `_reroute`에 넘기는 것은 `_currentPos`(LatLng) 뿐.** heading 객체는 여기서부터 전달되지 않음.

### B. heading 전달 여부
**2~3. `_reroute()` 정의·인자** — `nav_screen.dart:356-366`
```dart
Future<void> _reroute(LatLng origin) async {
  if (_isRerouting || !mounted) return;
  final dest = widget.destination;
  if (dest == null) return;
  setState(() => _isRerouting = true);
  try {
    final routes = await RoutingService.fetchRoutes(
      origin: origin,          // ← 현재 위치(lat/lng)만
      destination: dest,
      waypoints: widget.waypoints,
    );
```
- 넘기는 인자 전부: `origin`, `destination`, `waypoints`. **끝.**

**4. heading/bearing 파라미터?** → **아니오.**
- `_reroute` 시그니처는 `LatLng origin` 한 점만 받음 (`nav_screen.dart:356`). 위경도에 heading 정보 없음.
- 현재 위치의 heading 값은 화면 다른 곳(카메라 회전 `pos.heading`, `nav_screen.dart:261-262`)에서만 사용되고 라우팅엔 전달 안 됨.

**5. fetchRoutes 내부 HTTP JSON** — `routing_service.dart`
- `locations` 구성 (`routing_service.dart:128-133`):
  ```dart
  final locations = [
    {'lon': origin.longitude, 'lat': origin.latitude},
    for (final w in waypoints) {'lon': w.longitude, 'lat': w.latitude},
    {'lon': destination.longitude, 'lat': destination.latitude},
  ];
  ```
  → **lon/lat만. `heading` 필드 없음.**
- 실제 전송 바디 `_doFetch` (`routing_service.dart:262-266`):
  ```dart
  body: jsonEncode({
    'locations': locations,
    'costing': 'motorcycle',
    'costing_options': {'motorcycle': opts},
  }),
  ```
  → heading 없음. 시골길 폴백 재요청(`routing_service.dart:357-365`)도 같은 `locations` 사용 → 역시 heading 없음.
- **최초 경로탐색과 재탐색은 같은 `fetchRoutes`/`_doFetch`를 공유한다.** 별도 경로 아님.
  - 최초 호출처: `main_map_screen.dart:526` `RoutingService.fetchRoutes(...)`.

**6. 최초 vs 재탐색 비교** → **차이 없음. 둘 다 heading 미전송.**
즉 "재탐색만 heading 누락"이라는 가설은 부분적으로 틀림 — 앱은 **애초에 heading을 한 번도 보내지 않는다.** 다만 체감 증상이 재탐색에서 두드러지는 이유는, 출발 시엔 사용자가 정방향으로 출발하므로 유턴 경로가 드물지만, 주행 중 이탈 재탐색 시점엔 진행 방향과 무관한 유턴 경로가 나오기 쉽기 때문(해석).

### 후보 수정 위치 (코드 수정은 하지 않음)
1. `fetchRoutes` 시그니처(`routing_service.dart:123-127`)에 `double? originHeading` 추가.
2. `locations[0]`(`routing_service.dart:129`)에 `if (originHeading != null) 'heading': originHeading, 'heading_tolerance': <각도>` 삽입.
3. `_reroute`(`nav_screen.dart:356,362`)가 `_currentPos`의 heading을 함께 보유·전달하도록 변경. 단 `_reroute`는 현재 `LatLng`만 받으므로 호출부(`nav_screen.dart:333`)에서 heading도 캡처 필요. (`_onPosition`에서 마지막 `pos.heading`을 필드로 보관 → `_reroute`에 전달)
4. ⚠️ **선결 조건**: Valhalla fork가 `heading`을 수용하는지 D항 검증 후 적용.

---

## 3. 증상4 (maneuver·TTS) — 근거

### C. 안내 상태 리셋 여부

**7. maneuver 카드가 읽는 상태** — `build()` `nav_screen.dart:639`
```dart
final step = _steps[_stepIdx];
```
- `_steps` (`List<_TurnStep>`) — **`late final`** 선언 (`nav_screen.dart:92`)
- `_stepIdx` (`int`) — `nav_screen.dart:93`
- 진행바도 `_steps`/`_stepIdx` 사용 (`nav_screen.dart:789`)

**8. TTS 발화 지점·의존 변수**
- `_announceStep(int idx)` (`nav_screen.dart:395-404`): `_steps[idx]`, 중복방지 `_lastAnnouncedIdx` (`nav_screen.dart:397-398`)
- `_updateStepByDistance(loc)` (`nav_screen.dart:298-318`): `_stepEndDistM`, `_stepIdx`, `_preAnnounced`, `_steps` 의존. 400m 예비발화/50m 자동진행 모두 `_stepEndDistM`(경로 누적거리) 기준.
- `_stepEndDistM`는 `_computeStepEndDistances()`(`nav_screen.dart:272-278`)가 `_steps` 기준으로 산출.

**9. `_reroute`가 새 RouteResult 수신 후 갱신하는 것** — `nav_screen.dart:367-378`
```dart
if (mounted && routes.isNotEmpty) {
  final selIdx = ref.read(mapInteractionProvider).selectedRouteIdx.clamp(0, routes.length - 1);
  final newPoints = routes[selIdx].points;
  setState(() {
    _routePoints = newPoints;          // ✓ 갱신
    _durationMin = routes[selIdx].durationMin;  // ✓ 갱신
  });
  if (_styleLoaded) {
    _mlCtrl?.setGeoJsonSource(_navRouteSourceId, _buildRouteGeoJson(newPoints));
  }
}
```
- **`routes[selIdx].maneuvers` 는 읽지 않음 → 새 안내 정보가 통째로 버려짐.**
- `_steps`는 `late final`이라 **재할당 자체가 불가능**(컴파일 제약). 즉 현재 구조로는 setState 안에서 갱신하려 해도 못 함 → 리팩터 필요.
- `_computeStepEndDistances()` **재호출 없음** → `_stepEndDistM`이 옛 경로 누적거리 그대로.
- `_stepIdx`, `_lastAnnouncedIdx`, `_preAnnounced` **리셋 없음.**

**결과 메커니즘**: 새 경로 polyline은 그려지지만, maneuver 카드는 옛 `_steps[_stepIdx]`를 계속 표시. `_updateStepByDistance`는 새 polyline 위 `_traveledDistM`와 옛 `_stepEndDistM`를 비교 → 거리 정합 깨져 TTS 예비발화/자동진행이 정상 동작 안 함. (= 증상4)

**10. 최초 vs 재탐색 상태세팅 대조표**

| 상태 변수 | 선언 | 최초탐색 세팅 | 재탐색 세팅 |
|---|---|---|---|
| `_routePoints` | `nav_screen.dart:86` | ✓ `initState:130` | ✓ `_reroute:371` |
| `_durationMin` | `:70` | ✓ `initState:131` | ✓ `_reroute:372` |
| `_steps` | `late final :92` | ✓ `initState:137-143` | ✗ (final이라 불가) |
| `_stepEndDistM` | `:79` | ✓ `_computeStepEndDistances() initState:145` | ✗ 재호출 없음 |
| `_stepIdx` | `:93` | 기본 0 | ✗ 0으로 리셋 안 함 |
| `_lastAnnouncedIdx` | `:78` | -1 + `_announceStep(0)`(`_initTts:392`) | ✗ 리셋·재발화 없음 |
| `_preAnnounced` | `:80` | 기본 false | ✗ 리셋 안 함 |
| 지도 route 레이어 | — | ✓ `_initRouteLayer` 후 `:619-621` | ✓ `_reroute:374-377` |

→ **최초엔 있는데 재탐색엔 없는 초기화: `_steps`(재생성), `_stepEndDistM`(재계산), `_stepIdx`/`_lastAnnouncedIdx`/`_preAnnounced`(리셋), 새 step 재발화.**

### 후보 수정 위치 (코드 수정은 하지 않음)
1. `_steps`를 `late final`(`nav_screen.dart:92`) → `late` (가변)로 변경.
2. `_reroute` setState 블록(`nav_screen.dart:370-373`)에서
   `_steps = routes[selIdx].maneuvers.map(_TurnStep.fromManeuver).toList();`
   (maneuvers 비었으면 더미 폴백 — initState:137-143 로직 재사용),
   `_stepIdx = 0; _lastAnnouncedIdx = -1; _preAnnounced = false;` 추가,
   setState 후 `_computeStepEndDistances();` 호출, 그리고 새 step0 재발화(`_announceStep(0)`).

---

## 4. 미확인 항목 (폰/curl로만 검증 가능)

- **D-11. Valhalla fork heading 수용 여부** — 미확인.
  - 리포에 Valhalla 소스/`options.proto` 없음(`find` 결과 docker-compose만). 라우팅은 원격 `https://valhalla.westinx.com`(`routing_service.dart:67`).
  - 표준 upstream Valhalla `/route`는 location별 `heading`(0–360)·`heading_tolerance`(기본 60°) 지원이 문서화돼 있으나, **이 포크가 그대로 받는지는 별도 curl 검증 필요.**
  - 검증 커맨드(예):
    ```
    curl -s https://valhalla.westinx.com/route -d '{"locations":[
      {"lat":37.5,"lon":127.0,"heading":90,"heading_tolerance":45},
      {"lat":37.55,"lon":127.05}],"costing":"motorcycle"}'
    ```
    → 200 + heading 반영 경로면 지원 확정.
- 증상4 실기기 재현(재탐색 후 카드 멈춤/TTS 무음)은 코드상 확정이나, 실제 폰 동작 영상 확인은 별도.

---

## 5. 권장 다음 실행 턴 분할안

원칙: **단일 논리변경 = 단일 커밋.** 두 증상은 독립적이므로 분리한다.

1. **턴 1 — 증상4 먼저 (클라이언트 단독, 서버 검증 불필요).**
   - 이유: 순수 Flutter 변경이고 즉시 검증 가능. 사용자 체감 큼(주행 중 안내 멈춤).
   - 변경: `_steps` final 해제 + `_reroute`에서 steps 재생성·`_stepEndDistM` 재계산·`_stepIdx/_lastAnnouncedIdx/_preAnnounced` 리셋·step0 재발화.
   - 단일 커밋: `fix(nav): rebuild maneuver/TTS state on reroute`.

2. **턴 2 — D항 Valhalla heading curl 검증 (코드 무변경, 정찰성).**
   - 지원 확정 시에만 턴 3 진행.

3. **턴 3 — 증상3 heading 전달 (서버 의존).**
   - 변경: `fetchRoutes`에 `originHeading` 추가 → `locations[0]`에 `heading`/`heading_tolerance` 주입; `_reroute`가 마지막 `pos.heading` 전달.
   - 단일 커밋: `fix(nav): pass heading on reroute to avoid u-turn routes`.
   - (선택) 최초 탐색에도 heading 적용할지는 별도 판단 — 최초는 정지 상태라 heading 무의미할 수 있어 재탐색 한정 권장.

**우선순위: 턴1(증상4) → 턴2(검증) → 턴3(증상3).** 증상4가 자기완결적이고 회귀 위험 낮아 선행.
