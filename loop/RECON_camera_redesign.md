# RECON_camera_redesign — bottom-anchor 카메라 (C) 필드테스트 문제 조사

Read-only recon. No edits made.

Scope: `lib/features/navigation/presentation/nav_screen.dart` (nav_screen), plus
`maplibre_gl-0.26.1` package internals, `nav_state_provider.dart`, `offset_origin.dart`.

---

## 1. 초록 위치점(puck) 렌더링 방식

**소스: `nav_screen.dart:556-573` `_ensureLocationMarker()`**

```dart
_locMarker = await c.addCircle(ml.CircleOptions(
  geometry: geo,
  circleRadius: 8,
  circleColor: _kLocColor,        // '#00C853'  (:66)
  circleStrokeWidth: 3,
  circleStrokeColor: '#FFFFFF',
));
```

- MapLibreMap의 built-in `myLocationEnabled` 컴포넌트가 **아님** (nav_screen.dart의 `ml.MapLibreMap(...)` 위젯 생성부 :637-648에는 `myLocationEnabled` 파라미터 자체가 없음).
- flutter_map 마커도 아님 — flutter_map 오버레이(:653-690)는 waypoint/destination 핀만 그리며, 코드 주석대로 "임시 오버레이" 용도.
- 실제로는 **MapLibre "annotation" API의 `Circle`** — `MapLibreMapController.addCircle()` (`maplibre_gl-0.26.1/lib/src/controller.dart:1346-1357`), 내부적으로 `CircleManager`(`annotation_manager.dart:290-308`)가 소유하는 단일 GeoJSON source + `circle` 타입 레이어.

### (a) 크기 조절 가능?
가능. `CircleOptions.circleRadius`는 `double?`이며 상한 없음 (`maplibre_gl_platform_interface-0.26.1/lib/src/circle.dart:61,72`). `circleRadius: 8`을 12~16 등으로 올리는 것은 단순 값 변경.

### (b) z-order를 route LineLayer 위로 올릴 수 있는가?
**annotation API(`addCircle`) 자체로는 z-order 제어 불가** — `AnnotationManager.initialize()` (`annotation_manager.dart:74-98`)가 내부적으로 호출하는
`controller.addLayer(layerId, layerId, allLayerProperties[i], enableInteraction: ...)`에는 `belowLayerId`를 넘기지 않음(고정, 매니저가 임의로 선택 불가).
단, **`MapLibreMapController.addCircleLayer()`** (raw layer API, `controller.dart` — 기존 조사 `RECON_ZORDER.md` §1 인용: `addCircleLayer`/`addLineLayer` 모두 `belowLayerId` named param 지원 확인됨)를 쓰면 z-order를 명시적으로 지정 가능.
→ **결론: `addCircle()`(annotation) 대신 route line과 동일한 패턴(수동 `addGeoJsonSource` + `addCircleLayer(..., belowLayerId: ...)`)으로 옮기면 z-order·사이즈·스타일 전부 통제 가능.** Naver 스타일의 더 크고 위에 그려지는 puck은 0.26.1에서 feasible.

### (c) 색상/스타일 제어
`CircleOptions`의 `circleColor`, `circleStrokeWidth`, `circleStrokeColor`, `circleBlur`, `circleOpacity` 전부 자유 지정 가능 (`maplibre_gl_platform_interface-0.26.1/lib/src/circle.dart:61-69`). 방향성 화살표(헤딩 표시)까지 원하면 `circle`이 아니라 `symbol`(아이콘 회전) 레이어로 바꿔야 함 — 이번 recon 범위 밖이지만 같은 raw-layer 패턴으로 가능.

---

## 2. Route line vs 위치점 z-order — 현재 어느 쪽이 위인가

**경로선이 위 (버그).** 근거:

- `nav_screen.dart:575-585` `_onStyleLoaded()`:
  ```dart
  void _onStyleLoaded() {
    setState(() => _styleLoaded = true);
    _initRouteLayer().whenComplete(() {
      ...
      _ensureLocationMarker(); // unawaited — ③
    });
  }
  ```
  `_initRouteLayer()`(:539-554)는 `belowLayerId` 없이 `addLineLayer` 호출 → 항상 스택 맨 위에 추가.

- 그런데 **CircleManager(위치점)의 레이어는 이보다 먼저, 스타일 로드 직후에 자동으로 이미 추가되어 있음.** 기존 recon(`/data/projects/yurunavi/RECON_ZORDER.md`, 이 리포지토리에 이미 존재, 동일 플러그인 버전 대상)이 정확히 이 메커니즘을 확인함:
  - MapLibreMap 위젯의 `onMapStyleLoadedPlatform` 처리 순서(`controller.dart:205~258`): (1) 기존 매니저 dispose → (2) `annotationOrder` 순서대로 각 `AnnotationManager.initialize()` 호출(레이어 추가, 기본 `annotationOrder`엔 `circle` 포함 — `maplibre_map.dart:56`) → (3) 그제서야 앱의 `onStyleLoadedCallback`(= `_onStyleLoaded`) 호출.
  - 즉 `_ensureLocationMarker()`가 처음 `addCircle()`을 호출하는 시점에 관계없이, **CircleManager의 빈 레이어 자체는 이미 스타일 로드 단계(2번)에서 생성되어 있고**, `_initRouteLayer()`(3-1)가 그 뒤에 route 레이어를 추가하므로 **route가 항상 더 나중 = 항상 위**.
  - `_ensureLocationMarker()`가 실제 좌표로 `addCircle`을 부르는 시점(3-2, 처음 위치 수신 시)은 이미 CircleManager 레이어 슬롯이 있는 상태에서 데이터만 채우는 것 — 레이어 재추가가 아니므로 이 타이밍은 z-order에 영향 없음.
- 이후 `_reroute()`(:349-351)의 `setGeoJsonSource` 호출도 데이터만 갱신, 레이어 재삽입 없음 → 최초 순서가 계속 유지.

**결론: 매 세션 결정적(deterministic)으로 route line이 puck 위에 그려짐** — field report의 "puck이 route line 아래 렌더링" 관찰과 정확히 일치. (레이스 컨디션이 아니라 annotationOrder 초기화가 항상 onStyleLoadedCallback보다 먼저 실행되는 구조적 순서 문제.)

기존 `RECON_ZORDER.md` §5에 이미 검증된 수정안 존재(다른 화면 `main_map_screen.dart` 대상으로 작성됐지만 동일 플러그인·동일 구조이므로 nav_screen에도 그대로 적용 가능): `_initRouteLayer()`에서 `ctrl.circleManager?.layerIds.first`를 얻어 `addLineLayer(..., belowLayerId: circleLyr)`로 넘기면 route가 circle 아래로 삽입됨. nav_screen.dart:552의 주석 `// belowLayerId: ③에서 Circle 레이어 추가 후 z-order 삽입`이 바로 이걸 하려다 만 흔적으로 보이나 실제 코드에는 반영되지 않음 (미완).

---

## 3. `_recenter` 오프셋 수식 (커밋 314528e + a84c980)

**`nav_screen.dart:489-517`**

```dart
Future<void> _recenter(LatLng loc, {bool animate = false, double speedKmh = 0, double? headingDeg}) async {
  if (!_styleLoaded) return;
  final target = _zoomForSpeed(speedKmh);
  final diff = target - _navZoom;
  _navZoom += diff.clamp(-0.3, 0.3);

  if (headingDeg != null) _lastHeadingDeg = headingDeg;                 // :496 — 무조건 갱신, 속도 게이트 없음
  final effectiveHeadingDeg = headingDeg ?? _lastHeadingDeg;

  var camTarget = loc;
  if (effectiveHeadingDeg != null) {
    final metersPerPixel = await _mlCtrl?.getMetersPerPixelAtLatitude(loc.latitude);  // :501
    if (metersPerPixel != null && mounted) {
      final screenHeightPx = MediaQuery.of(context).size.height;         // :503 — 로지컬 px (dp)
      final metersAhead = metersPerPixel * screenHeightPx * 0.35;        // :504
      final off = offsetOrigin(loc.latitude, loc.longitude, effectiveHeadingDeg, metersAhead);
      camTarget = LatLng(off.lat, off.lng);
    }
  }

  final update = ml.CameraUpdate.newLatLngZoom(_toMl(camTarget), _navZoom);
  if (animate) { _mlCtrl?.animateCamera(update); } else { _mlCtrl?.moveCamera(update); }
}
```

현재 계수: **`0.35`** (`:504`), 튜닝 지점은 여기 리터럴 하나.

### 로지컬 vs 피지컬 px 불일치 — 확인됨, 실재하는 버그
- `MediaQuery.of(context).size.height`(`:503`)는 Flutter **로지컬 픽셀(dp)**.
- `getMetersPerPixelAtLatitude`(`:501`)는 `maplibre_gl` 플랫폼 채널을 거쳐 **네이티브 MapLibre SDK의 `Projection.getMetersPerPixelAtLatitude(latitude)`를 그대로 호출** (`maplibre_gl-0.26.1/android/.../MapLibreMapController.java:955-964`):
  ```java
  case "map#getMetersPerPixelAtLatitude": {
    Double retVal = mapLibreMap.getProjection().getMetersPerPixelAtLatitude((Double) call.argument("latitude"));
    ...
  }
  ```
  이 핸들러는 **`density`(디바이스 밀도)를 전혀 참조하지 않음** — 바로 위/아래에 있는 다른 핸들러(`camera#move`, :967-974)는 `Convert.toCameraUpdate(..., mapLibreMap, density)`로 **명시적으로 density를 넘기는 것과 대조적**. 이는 플러그인 작성자가 카메라 이동류 API는 dp↔px 변환이 필요하다고 인지했지만, `getMetersPerPixelAtLatitude`는 변환 없이 네이티브 값을 그대로 반환한다는 뜻.
  MapLibre(Mapbox 계열) 네이티브 `Projection.getMetersPerPixelAtLatitude`는 뷰의 **물리 픽셀(device pixel)** 기준으로 정의됨 (Android View 좌표계는 기본적으로 physical px).
- 즉 `metersPerPixel`은 **물리 px당 미터**, `screenHeightPx`는 **로지컬 px(dp)** — 서로 다른 단위를 곱하고 있음.
- `devicePixelRatio`(전형적으로 2.5~3.5, 예: `MediaQuery.of(context).devicePixelRatio`)만큼 `metersAhead`가 실제 의도보다 **과대 계산**됨. 예: density=3.0이면 "0.35 화면 높이만큼 앞"이 아니라 사실상 **~1.05 화면 높이(전체 화면 밖)** 만큼 오프셋되는 셈.
- **이것이 "off-screen too low"의 유력한 근본 원인** — 0.35라는 계수 자체보다, 계수에 곱해지는 두 값의 단위가 다른 것이 훨씬 큰 배율 오차를 만듦. 0.35만 낮추는 튠으로는 디바이스 density에 따라 여전히 들쭉날쭉할 것(고밀도 화면일수록 더 심하게 밀림 — "때때로 한쪽으로 쏠린다"는 관찰과도 device 편차 측면에서 정합적).
- 수정 시 두 가지 옵션: (1) `screenHeightPx`를 물리 px로 변환(`* MediaQuery.of(context).devicePixelRatio`) 후 곱하거나, (2) `metersAhead`를 아예 `metersPerPixel(로지컬 등가치가 필요하면 density로 나눔) * screenHeightPx * ratio` 식으로 단위를 로지컬로 통일. 실측(로그 `YNAV_CAM anchor ... mpp=... mAhead=...`, `:505`)으로 실제 배율을 먼저 확인 권장.

---

## 4. `_lastHeadingDeg` / heading 소스 — smoothing 유무

**`nav_state_provider.dart:144`**
```dart
_headingDeg = pos.heading >= 0 ? pos.heading : null;
```
`geolocator`의 `Position.heading`을 **가공 없이 그대로** 대입. 스무딩/데드밴드/이동평균/속도 게이트 전혀 없음 — `_onFix()`(:100-160) 전체를 봐도 `_headingDeg` 관련 필터링 로직 없음(반면 `_speedKmh`는 `_tickSpeed()`에서 정교한 파킹감지·기울기보간·jump guard 등을 거침 — heading만 예외적으로 무필터).

이 raw `headingDeg`가 그대로 `NavigationState.headingDeg`로 나가고, `nav_screen.dart:215`에서 매 틱마다:
```dart
if (!_isManualMode) _recenter(loc, speedKmh: next.speedKmh, headingDeg: next.headingDeg);
```
**정지 여부와 무관하게 항상 `_recenter`에 전달됨.** `_recenter` 내부(`:496`)도 `if (headingDeg != null) _lastHeadingDeg = headingDeg;` — 속도 게이트 없이 무조건 최신값으로 덮어씀.

정지 시 GPS course(`pos.heading`)는 위성 기하/멀티패스 노이즈로 몇 초 단위로 크게 요동치는 것이 일반적 현상(이동 벡터가 사실상 0이라 방향을 계산할 근거가 없음) — 이 앱은 그 잡음을 전혀 걸러내지 않고 카메라 오프셋 계산에 바로 먹임.

**데드밴드/freeze를 넣을 위치**: 자연스러운 지점은 `nav_state_provider.dart:144` 직전/직후 — 예를 들어 `_moving`(이미 계산됨, :131-137) 또는 `_speedKmh` 임계값 미만이면 `_headingDeg`를 갱신하지 않고 이전 값을 유지(또는 `null` 유지)하는 식. 대안으로 `nav_screen.dart:215-216`에서 `_recenter`/`bearingTo` 호출 전에 `next.speedKmh` 기준으로 헤딩 사용 여부를 게이팅(이미 `:216`의 bearing 쪽엔 `speedKmh > 2` 게이트가 있으나 `_recenter`로 넘기는 `headingDeg`엔 동일 게이트가 없음 — 이 비대칭이 핵심, 아래 §5 참조).

---

## 5. 정지 시 스핀 — bearing 회전 vs offset 재계산, 어느 쪽이 원인인가

**`nav_screen.dart:215-218`**
```dart
if (!_isManualMode) _recenter(loc, speedKmh: next.speedKmh, headingDeg: next.headingDeg);   // :215 — 게이트 없음
if (next.headingDeg != null && next.speedKmh > 2 && _styleLoaded) {                          // :216 — speedKmh>2 게이트 있음
  _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(next.headingDeg!));
}
```

- **Bearing 회전(:217)은 게이트가 정상 동작함.** 정지 시(`speedKmh<=2`) `bearingTo` 호출 자체가 스킵됨 → 지도 "회전"(북쪽 고정이 깨지는 것)은 발생하지 않음. (`rotateGesturesEnabled: false`이기도 함, :643 — 사용자가 손으로 돌릴 수도 없음.)
- **원인은 offset target 재계산 쪽(`_recenter` 내부의 `camTarget`).** `_recenter`는 speed 게이트 없이 매 GPS 틱마다 호출되고(:215), `headingDeg`가 null이 아니면(정지해도 GPS는 여전히 `pos.heading>=0`인 잡음값을 계속 내보내므로 §4에 의해 거의 항상 non-null) `:496`에서 `_lastHeadingDeg`를 매번 그 잡음값으로 덮어쓰고, `:500-508`에서 그 잡음 섞인 heading으로 `offsetOrigin()`을 다시 계산 → `camTarget`(카메라가 바라보는 실제 좌표)이 매 틱 널뛰기.
- 카메라는 **North-up 고정**(`rotateGesturesEnabled:false`)이라 화면이 "회전"하는 게 아니라, **카메라 center가 heading 잡음을 따라 사용자 주변을 빙빙 도는 좌표로 계속 재설정**되면서 지도가 사용자 기준 훽훽 미끄러지는 것처럼 보임 — 사용자가 표현한 "두리번거리며 맵이 휙휙"은 이 **offset-target 재계산**이 원인, bearing 회전이 아님.
- 결론: **정지 시 스핀의 근본 원인은 §4의 raw-heading + `_recenter`의 speed 게이트 부재(:215, :496) 조합.** 고치려면 (a) heading 자체에 데드밴드/freeze를 걸거나, (b) `_recenter`에도 `bearingTo`와 동일하게 `speedKmh` 임계값 이하일 때 `headingDeg`를 무시(= 이전 `_lastHeadingDeg`를 계속 씀 대신, 아예 오프셋 자체를 0으로 하거나 완전히 동결)하는 게이트를 넣어야 함.

---

## 6. "한쪽으로 쏠림" — bearing과 offset이 같은 틱에서 다른 heading을 쓰는가?

**같은 틱에서 넘겨받는 원본 값 자체는 동일함**: `:215`와 `:216`의 `next.headingDeg`는 같은 `next: NavigationState` 인스턴스에서 나온 같은 값. 코드상 "한 틱 안에서 다른 필드를 참조"하는 버그는 없음.

그러나 **비동기 경합(race)으로 인해 실행 시점이 어긋날 소지가 있음**:

- `:215`의 `_recenter(...)` 호출은 **await 없이 fire-and-forget**(`_recenter`는 `async` 함수, 반환된 Future를 버림). `_recenter` 내부(`:501`)에 `await _mlCtrl?.getMetersPerPixelAtLatitude(...)`라는 **플랫폼 채널 왕복(비동기 I/O)** 이 있음.
- `:217`의 `bearingTo`도 `animateCamera`가 반환하는 Future를 기다리지 않고 바로 다음 GPS 틱으로 넘어감(리스너 콜백 자체가 async 아님).
- GPS 틱 주기가 `getMetersPerPixelAtLatitude`의 왕복 지연보다 짧으면(예: 정차 후 재출발 구간처럼 픽스가 촘촘히 들어올 때), **틱 N의 `_recenter`가 아직 await 중인 사이에 틱 N+1의 `bearingTo`가 이미 실행되어 카메라 bearing이 N+1의 heading으로 먼저 회전**하고, 그 후 틱 N의 `_recenter`가 뒤늦게 완료되어 **N(더 오래된, 이미 지나간) heading 기준의 offset으로 `camTarget`을 이동**시키는 순서 역전이 가능함. `moveCamera`/`animateCamera`는 각각 독립 호출이라 서로 취소·조율되지 않음.
- 즉 **"같은 틱" 내부 값 자체는 안 어긋나지만, `_recenter`가 비동기(await 포함)인데 호출부(:215)가 그 완료를 기다리지 않고 다음 틱을 계속 흘려보내는 구조 때문에, 화면에 실제로 적용되는 시점 기준으로는 bearing이 최신 heading, offset이 한두 틱 뒤처진 heading을 쓰는 상황이 생길 수 있음** — 이것이 "헤딩이 실제 진행 방향보다 지연되는 커브/GPS 지연 구간"에서 관찰된 "한쪽으로 쏠림"의 유력한 메커니즘. 커브에서는 프레임마다 heading이 빠르게 바뀌므로 이 지연 효과가 특히 두드러짐.
- 부수적으로: `_navZoom`(:493-494), `_lastHeadingDeg`(:496)는 인스턴스 필드라 여러 개의 동시 진행 중인 `_recenter` 호출이 서로의 상태를 밟고 지나갈 수 있음(re-entrancy 가드 없음) — 이 역시 같은 계열의 문제.

---

## 요약 (fix는 하지 않음)

**(a) 크고 z-order 높은 puck — 0.26.1에서 feasible한가, 어떻게?**
Feasible. `addCircle()`(annotation API)는 z-order를 통제할 수 없으므로, route line과 동일하게 **raw `addGeoJsonSource` + `addCircleLayer(..., belowLayerId: ...)`** 패턴으로 위치점을 직접 관리하는 레이어로 바꿔야 함. `circleRadius`/`circleColor` 등은 상한 없이 자유 조정 가능.

**(b) 정지 시 스핀의 근본 원인**
`bearingTo` 회전은 아님(정상적으로 `speedKmh>2` 게이트로 막힘, `:216`). 원인은 **`_recenter`의 offset-target 재계산**(`:489-517`)이 speed 게이트 없이 매 틱 raw GPS heading(`nav_state_provider.dart:144`, 무필터)을 그대로 반영해 `camTarget`을 흔드는 것.

**(c) "off-screen too low"의 근본 원인**
`_recenter`(`:503-504`)가 **로지컬 px**(`MediaQuery...size.height`)와 **물리 px 기준**(`getMetersPerPixelAtLatitude`, 네이티브 `Projection` 값, density 미보정 — `MapLibreMapController.java:955-964`)을 그대로 곱해 단위 불일치 발생. `devicePixelRatio`배만큼(전형적으로 2.5~3배) `metersAhead`가 의도보다 과대해짐 — 0.35 계수 자체보다 이 단위 버그가 지배적 원인으로 추정됨.

**(d) "한쪽으로 쏠림"의 근본 원인**
같은 틱 안에서 다른 필드를 참조하는 버그는 없음(둘 다 같은 `next.headingDeg`). 대신 `_recenter`가 `await`(플랫폼 채널 왕복)를 포함한 비동기 함수인데 호출부(`:215`)가 그 완료를 기다리지 않고 다음 GPS 틱을 계속 처리하는 구조 때문에, **bearing 회전(:217, 매 틱 즉시 실행)과 offset 이동(`_recenter`, 완료까지 지연될 수 있음)이 서로 다른 heading 세대를 기준으로 화면에 순서 역전되어 적용될 수 있음** — 특히 커브·GPS 지연 구간에서 두드러질 것으로 추정.
