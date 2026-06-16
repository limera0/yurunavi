# RECON: 안내 거리 미갱신 추적 결과

## A. 카드의 "○○m 앞" 거리 값의 출처

**변수/필드:** `_TurnStep.dist` (`nav_screen.dart:1209`, `final String dist`)

**표시 위치:** `nav_screen.dart:950-958`
```dart
final step = _steps[_stepIdx];   // :783
...
if (step.dist.isNotEmpty)
  Text(step.dist, ...)            // :951
```

**set 위치 (단 1곳):**
- `nav_screen.dart:1217` — `_TurnStep.fromManeuver(m)` factory 내부:
  ```dart
  _formatDist(m.distanceKm)   // Valhalla 응답의 maneuver length를 포맷한 정적 문자열
  ```

**`_steps` 가 구성되는 위치 (2곳):**
1. `nav_screen.dart:153` — `initState()` → `_applyRouteGuidance(widget.maneuvers)`
2. `nav_screen.dart:479` — `_reroute()` → `_applyRouteGuidance(routes[selIdx].maneuvers)`

**결론:** `step.dist`는 Valhalla가 반환한 `maneuver.length`(km)를 포맷한 **정적 문자열**이다.
라우트 로드(또는 재탐색) 시 1회만 생성되며, GPS 콜백에서 갱신되지 않는다.

---

## B. GPS 위치 스트림 구독부

**스트림 구독:** `nav_screen.dart:221-232`
```dart
_locationSub = Geolocator.getPositionStream(...).listen(_onPosition);
```

**콜백 함수:** `_onPosition(Position pos)` — `nav_screen.dart:294`

**`_onPosition` 내부에서 (A)의 `step.dist` 를 재계산하는가?**  
→ **아니다.** 콜백 내부에서 `step.dist`(또는 `_TurnStep.dist`)를 건드리는 코드는 없다.

`_onPosition`이 하는 일:
- `:296` 위치 프로바이더 갱신
- `:297` 카메라 추종 (`_recenter`)
- `:302-303` ZUPT 링버퍼 push
- **`:311-318` 조기 리턴 경로:** `elapsedMs < intervalMs`(≤10km/h→500ms, 나머지→1000ms)이면
  `_currentPos` 만 setState 후 `return` → `_updateStepByDistance` **호출 안 됨**
- `:340-344` 속도(`_speedKmh`), 현위치(`_currentPos`) setState
- `:357` `_checkArrival`
- `:360` `_updateStepByDistance(loc)` — 단, `!_arrived && _routePoints.length >= 2` 조건 하

---

## C. step 진행 로직 (`_stepIdx` 증가 위치)

**위치 1 (GPS 자동 진행):** `nav_screen.dart:419-422`
```dart
if (remaining < 50) {          // 50m 임계값
  _preAnnounced = false;
  setState(() => _stepIdx++);
  _announceStep(_stepIdx);
}
```
트리거: `remaining` (현재위치 기준 이 step 종점까지 남은 거리) < 50m

**위치 2 (수동 탭):** `nav_screen.dart:903-906`
```dart
onTap: () {
  if (_stepIdx < _steps.length - 1) {
    setState(() => _stepIdx++);
    _announceStep(_stepIdx);
  }
},
```

**`remaining` 계산:** `nav_screen.dart:407-409`
```dart
final traveled  = _traveledDistM(loc);
final stepEnd   = _stepEndDistM[_stepIdx];
final remaining = (stepEnd - traveled).clamp(0.0, double.maxFinite);
```

`remaining`은 GPS틱마다 새로 계산되지만 **이 값은 카드 UI에 표시되지 않는다.**  
TTS 400m 예비 발화(`:415`)와 50m 자동 진행(`:419`) 에만 쓰인다.

---

## D. 현재위치→다음 maneuver 좌표 거리 계산 함수

**`ManeuverStep`에 좌표(lat/lng) 없음.** `routing_service.dart:31-43`:
```dart
class ManeuverStep {
  final int type;
  final String instruction;
  final double distanceKm;   // 거리만. 좌표 없음.
}
```
Valhalla의 `begin_shape_index`는 파싱하지 않는다.

**대신 폴리라인 투영으로 추정:** `_traveledDistM(loc)` — `nav_screen.dart:388-401`
- 전체 폴리라인(`_routePoints`) 세그먼트 중 현위치와 가장 가까운 세그먼트를 찾아
  그 시작점까지의 누적 거리를 합산한다.
- `_stepEndDistM[i]`는 각 step의 `rawDistKm`(Valhalla 거리) 누적값 — `nav_screen.dart:364-370`

→ "현위치→다음 회전 지점 직선 거리" 계산은 **없음.** 폴리라인 투영 기반 누적거리 차분으로 대체.

---

## 최종 1줄 판정

**(1) 라우트 로드 시 1회만 계산되고 GPS틱에 미갱신.**

카드의 `step.dist`는 `_TurnStep.fromManeuver()` 생성 시 Valhalla `maneuver.length`를
`_formatDist()`로 포맷한 **고정 문자열**이며, GPS 콜백(`_onPosition`/`_updateStepByDistance`)
어디서도 이 값을 덮어쓰거나 재계산하지 않는다. GPS틱마다 계산되는 `remaining`은
TTS·자동 스텝 진행에만 쓰이고 UI에 바인딩되지 않는다.
