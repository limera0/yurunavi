# RECON — nav_screen 네이버식 UI 리디자인 (도착 배너 / 상시 재탐색 버튼 / 하단 앵커 카메라)

읽기 전용 조사. 코드 변경 없음.

## 1. Stack 레이어 인벤토리 — `lib/features/navigation/presentation/nav_screen.dart:644-962`

`build()`의 `Scaffold > body: Stack(children: [...])`. 위에서부터 순서(= z-order, 아래가 나중에 그려짐):

1. **로딩 스피너** — `:649-650`. `_styleJson == null`일 때만 `Center(CircularProgressIndicator())`.
2. **MapLibreMap 본체** — `:651-667`. `Listener(behavior: translucent, onPointerDown: _onMapGesture)`로 감싼 `ml.MapLibreMap`. `initialCameraPosition`은 `:657-660`(target=현재 pos 또는 `_kInitialMapView`, zoom:15 고정값). `rotateGesturesEnabled: false`, `tiltGesturesEnabled: false`, `compassEnabled: false`.
3. **임시 flutter_map 오버레이** — `:671-708`. `IgnorePointer` 안에 `FlutterMap`(투명 배경) — 목적지/경유지 마커(`MarkerLayer`)만 남아있음(폴리라인은 이미 GeoJSON LineLayer로 이관됨, 주석 `:669-670` 참고). 리디자인과 무관하지만 Stack에서 지도 위 레이어 순서에 끼어 있다는 점은 기록.
4. **수동모드 복귀 알림 배너** — `:711-732`. `if (_isManualMode)`, `Positioned(top: safeArea+88, left/right: 60)`. 이미 "비침습 배너" 패턴의 선례 — (A) 도착 배너 설계 시 이 위젯을 그대로 참고/재사용 가능한 구조.
5. **상단 회전 안내 카드** — `:735-841`. `Positioned(top:0)+SafeArea`, GestureDetector로 탭하면 스텝 수동 진행(디버그용으로 보임). 흰 카드 + LinearProgressIndicator + 회전 아이콘 + 거리/라벨.
6. **좌측 속도계** — `:844-851`. `Positioned(left:12, top: 화면높이*0.30)`.
7. **우측 컨트롤 컬럼** — `:854-885`. `Positioned(right:12, top:200, bottom:160)` → `Column[Expanded(DaylightBar), SizedBox(10), _NavIconBtn(GPS 재중심)]`. **(B) 재탐색 버튼을 놓기에 가장 자연스러운 기존 슬롯** — 이미 `_NavIconBtn` 재사용 가능한 컴포넌트가 있고(`:1043-1066`), 이 컬럼에 버튼 하나만 더 추가하면 됨.
8. **하단 ETA 바** — `:888-950`. `Positioned(bottom:0)`, 상세는 §5.
9. **야간 디밍 오버레이** — `:954-961`. `if (!isDay)`, `Positioned.fill(IgnorePointer(Container(black@0.35)))`. **이건 "도착 다이얼로그의 dim"이 아니라 일몰~일출 상시 오버레이임** — 아래 §도착 다이얼로그 항목과 혼동 주의.

## 도착 다이얼로그 — 정확한 호출부

`_showArrivalDialog(pois)` — `nav_screen.dart:429-476`. `showDialog<void>(context, barrierDismissible: false, builder: (ctx) => AlertDialog(...))`.

- **dim/모달 방식**: Flutter의 `showDialog`는 기본적으로 `barrierColor`를 명시하지 않으면 `Colors.black54`(반투명 검정)를 깜. 이 코드는 `barrierColor`를 커스텀하지 않았으므로 **기본 `Colors.black54` 배리어가 전체 화면을 덮음** — 이게 "center modal + dim" 증상의 실체. `barrierDismissible: false`라 탭으로 못 닫음, 오직 `확인` 버튼(`:465-473`)만 dismiss 경로.
- **트리거**: `:232-238`, `_progressSub` 콜백 안에서 `prog.arrived && !_arrived` → POI 조회(`_fetchNearbyPois`, `:392-418`, Overpass API 호출로 최대 5초 대기) → 완료 후 `_showArrivalDialog(pois)`. **주의: POI 조회가 끝날 때까지 다이얼로그가 안 뜸 → 도착 직후 최대 5초 무반응 구간 존재.** (A) 배너로 바꿀 때 이 지연도 같이 재검토할 만함(배너는 dim이 없으니 굳이 POI를 기다릴 필요 없이 "도착" 배너 먼저 띄우고 POI는 비동기로 배너에 채워 넣는 식으로 개선 가능).
- **상태 플래그**: `_arrivalDialogShown`(`:80`) — `_showArrivalDialog` 진입 시 `true`(`:431`), `showDialog(...).whenComplete(() => _arrivalDialogShown = false)`(`:475`)로 리셋. `_reroute()`가 시작되면(`:311-314`) 이 플래그를 보고 강제로 `Navigator.of(context).pop()`해서 다이얼로그를 닫음 — **(A)를 배너로 바꾸면 이 "재탐색 시작 시 강제 dismiss" 배선도 배너용으로 옮겨야 함**(배너는 Navigator push가 아니므로 `Navigator.pop()` 방식이 아니라 `setState(() => _arrivalBannerVisible = false)` 류로 교체 필요).

## 2. 카메라 컨트롤 — MapLibre 0.26.1 API 조사

### 코드 내 카메라 호출 지점
- `_recenter(loc, {animate, speedKmh})` — `:526-538`. `ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom)`, `animateCamera` 또는 `moveCamera`. **GPS 틱마다 호출**(위치 구독 `:213`), target은 항상 사용자의 정확한 현재 좌표 — 오프셋 없음.
- 초기 카메라 — `:657-660`. `ml.CameraPosition(target: 현재pos 또는 fallback, zoom: 15)` 고정.
- bearing 회전 — `:214-216`. `next.headingDeg != null && next.speedKmh > 2 && _styleLoaded`일 때만 `_mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(next.headingDeg!))`. **`rotateGesturesEnabled: false`는 사용자 제스처 회전만 막을 뿐, 코드가 API로 bearing을 계속 갱신하는 건 막지 않음** — 즉 지도는 실제로 진행방향으로 계속 회전 중(North-up이 아님). 상단 지도 위젯 주석(`:661`, "North-up 고정(바이크 거치)")은 제스처 잠금에 대한 설명이지 회전 자체가 없다는 뜻이 아님 — 오독 소지 있는 주석.
- `_onMapGesture`(`:608-616`) — 사용자가 지도를 터치하면 10초간 수동모드(`_isManualMode`), 이후 자동으로 `_recenter` 복귀.

### maplibre_gl 0.26.1 패키지가 실제로 노출하는 것 (`~/.pub-cache/hosted/pub.dev/maplibre_gl{,_platform_interface}-0.26.1`)

`CameraUpdate` 팩토리 전체 목록(`maplibre_gl_platform_interface-0.26.1/lib/src/camera.dart:92-178`):
`newCameraPosition`, `newLatLng`, `newLatLngBounds(bounds, {left,top,right,bottom})`, `newLatLngZoom`, `scrollBy`, `zoomBy`, `zoomIn/Out/To`, `bearingTo`, `tiltTo`.

**핵심 결론: (a) "카메라 패딩"에 해당하는, GoogleMap의 `padding` 프로퍼티 같은 상시 뷰포트 오프셋 API가 이 버전엔 없다.**
- 패딩이 붙는 API는 딱 둘: `CameraUpdate.newLatLngBounds(..., left/top/right/bottom)`와 컨트롤러의 `setCameraBounds({west,north,south,east,padding:int})`(`controller.dart:1783-1797`). 둘 다 **바운딩 박스를 화면에 맞춰 fit하는 1회성 동작**이지, `newLatLngZoom`처럼 고정 줌을 유지하며 특정 지점을 화면의 특정 위치(예: 하단 15%)에 고정시키는 상시 옵션이 아님. 지금 `_recenter`가 매 GPS 틱마다 쓰는 `newLatLngZoom`에는 패딩 인자 자체가 없음.
- `MapLibreMap` 위젯의 다른 margin류 프로퍼티(`logoViewMargins`, `compassViewMargins`, `attributionButtonMargins`, `maplibre_map.dart:236,242,253`)는 **로고/컴�스/저작권 배지 위치 조정용이지 카메라 프레이밍과 무관**. (c)는 사용 불가.
- **(a) 카메라 패딩: 불가능** (0.26.1 API 범위 내에서 지속적 뷰포트 오프셋 수단 없음).
- **(b) 사용자 앞쪽 지점을 타겟팅: 가능하고, 유일한 실현 경로.** `newLatLngZoom(target, zoom)`의 `target`을 사용자의 실좌표가 아니라 "진행방향으로 N미터 앞"으로 계산한 좌표로 바꾸면, 지도가 이미 heading에 맞춰 회전 중이므로(위 bearing 항목) 화면상 사용자 실제 위치가 자연히 중심보다 아래로 밀려나는 시각효과가 남. 이미 `lib/features/route/offset_origin.dart:8-15`에 `offsetOrigin(lat, lng, headingDeg, meters)` 헬퍼가 존재(현재는 재탐색 origin 오프셋용, `nav_screen.dart:321`에서 40m 전방으로 사용 중) — **그대로 재사용 가능**.
  - 주의점: 미터 단위 오프셋은 줌 레벨에 따라 화면상 픽셀 오프셋이 달라짐(줌 클수록 같은 미터가 더 큰 화면 이동으로 보임). 화면상 "하단 10~15%"처럼 일정한 비율로 고정하려면 `controller.getMetersPerPixelAtLatitude(lat)`(`controller.dart:1770`)로 현재 줌의 미터/픽셀을 구해 목표 화면 오프셋(예: 화면 높이의 35%)에 맞는 미터값을 역산해야 함. 그냥 고정 미터값(예: 40m)을 쓰면 저속 고줌(18)에서는 과도하게 밀리고 고속 저줌(14)에서는 거의 안 밀리는 불일치가 생김.
  - `headingDeg == null`(정지 또는 `speedKmh <= 2`, `:214` 조건과 동일 기준) 구간에서는 오프셋 기준이 없음 — 이 경우 오프셋을 0으로 두고(=현재처럼 사용자 위치를 그대로 타겟) 저속/정지 시엔 화면 중앙 배치로 폴백하는 게 안전(고속 주행 중에만 하단 앵커 효과 필요하다는 요구사항과도 부합).

### 줌 (item 3)

`_navZoom`(`:93`, 초기 15.0) — **속도 기반 동적 보간**, 고정 아님.
- `_zoomForSpeed(kmh)`(`:519-524`): 0km/h→18, 20km/h→16, 60km/h+→14, 선형 보간.
- `_recenter`(`:526-538`)에서 매 틱마다 목표 줌으로 최대 ±0.3레벨씩만 수렴(`:530-531`, 급격한 줌 점프 방지).
- 초기 카메라(`:659`)는 zoom 15 하드코딩 — 첫 GPS fix 오기 전 기본값.
- (C)로 하단 앵커를 적용하면 이 동적 줌과 오프셋 미터값이 서로 얽히므로, 위 "메터/픽셀 역산" 로직은 `_navZoom`이 바뀔 때마다 재계산돼야 함(즉 `_recenter` 안에서 줌과 오프셋을 같은 프레임에 같이 계산).

## 4. 재탐색 수동 트리거 경로

호출 그래프: 유일한 진입점은 `_progressSub`의 `prog.offRoute` 분기(`:247-248`) → `_triggerReroute()`(`:295-307`) → 3초 디바운스 타이머 → `_reroute(current)`(`:309-366`). **`_reroute()`를 직접 부르는 다른 경로는 코드 전체에 없음**(grep 확인, `nav_screen.dart` 내 `_reroute(` 호출은 `:305` 단 한 곳).

게이트 위치 정리:
- **쿨다운 게이트**: `_triggerReroute()` 내부, `:296-301`. `_isRerouting || _rerouteFallback` 즉시 반환, 이어서 `_lastRerouteAt`과 `_kRerouteCooldown(8s)` 비교해 스킵.
- **디바운스**: `_triggerReroute()` 내부, `:302-306`. offRoute가 3초 이상 지속돼야 실제 `_reroute` 호출.
- **`_reroute()` 자체의 게이트는 `:310` `if (_isRerouting || !mounted) return;` 뿐** — 쿨다운/폴백 체크가 없음.

**결론: 수동 재탐색 버튼은 `_triggerReroute()`가 아니라 `_reroute(currentPos)`를 직접 호출하는 별도 경로를 만들면, 쿨다운(`:297-301`)과 폴백 게이트(`:296`)를 자연스럽게 우회한다** — 코드 구조상 이미 그렇게 되어 있음(쿨다운/폴백 체크가 `_triggerReroute` 레이어에만 있고 `_reroute`엔 없음). 별도 `if` 분기를 새로 짤 필요 없이 호출 지점만 다르게 하면 됨. 다만:
- `_reroute`는 `origin: LatLng`을 요구(`:309`) — 버튼 핸들러에서 `ref.read(navStateProvider)?.pos`가 null이면(GPS 미획득) 버튼을 비활성화하거나 무시해야 함.
- `dest`는 `widget.destination`을 그대로 씀(`:315-316`, null이면 즉시 return) — 이미 필드로 존재, 버튼 쪽에서 별도로 들고 있을 필요 없음.
- **로딩 피드백 없음**: `_isRerouting`(`:97`)은 `setState`로 갱신되지만(`:317`, `:350`) build()의 어떤 위젯도 이 값을 읽지 않음(grep 확인, `_isRerouting`은 게이트 조건에만 쓰이고 UI 바인딩 없음) — 버튼을 추가하면 스피너/디세이블 상태를 새로 그려야 함. 안 그러면 사용자가 여러 번 연타해도 시각적으로 아무 반응이 없어 보임(내부적으론 `_isRerouting` 가드가 막아주지만).
- 재탐색 성공 시 `_vps?.speak('reroute')`(`:340`)가 무조건 발화됨 — 수동 버튼 눌러도 동일 음성이 나감(의도된 동작인지 UX 판단 필요, 이번 RECON 범위 밖으로 기록만 함).

## 5. 하단 ETA 바 — 충돌 없는 재탐색 버튼 배치 지점

`nav_screen.dart:888-950`. 구조: `Positioned(bottom:0,left:0,right:0) > Container(surface, top-rounded 24) > SafeArea(top:false) > Padding > Row[Expanded(ETA/거리 텍스트, :903-925), 세로 구분선(:926), 종료 버튼(GestureDetector, :927-944)]`.

- 이 Row는 이미 꽉 차 있음(ETA 텍스트 + 구분선 + 종료 버튼) — **여기에 재탐색 버튼을 새 컬럼으로 추가하면 Row 폭이 좁아지고 종료 버튼과 시각적으로 경합**할 수 있음.
- 대신 §1-7 우측 컨트롤 컬럼(`:854-885`)에 `_NavIconBtn` 하나 더 추가(GPS 재중심 버튼 아래)하는 편이 레이아웃 충돌 없이 안전 — 이미 존재하는 재사용 컴포넌트(`_NavIconBtn`, `:1043-1066`)와 배치 패턴을 그대로 따르면 됨.
- 대안: 하단 ETA 바 Row 자체를 재구성(예: 종료 버튼 왼쪽에 재탐색 아이콘 버튼 추가)하려면 `Row`의 `Expanded`(ETA 텍스트)와 `Container`(종료) 사이에 별도 `GestureDetector`/아이콘 버튼 삽입 필요 — 레이아웃 재설계 범위가 더 커짐.

## 인벤토리 — A/B/C 난이도 및 실현성 평가

| 항목 | 난이도 | 비고 |
|---|---|---|
| **(A) 도착 배너화** | **쉬움** | `showDialog`(기본 `barrierColor: black54`)를 `_isManualMode` 배너(`:711-732`)와 같은 `Positioned` 오버레이 패턴으로 교체. 이미 선례 있는 패턴 재사용. 유일한 추가 배선: `_reroute()`가 다이얼로그를 강제 dismiss하던 로직(`:311-314`)을 배너 bool 플래그 토글로 교체. POI 조회 지연(최대 5초, `_fetchNearbyPois`) 처리 방식도 같이 재검토 권장. |
| **(B) 상시 재탐색 버튼** | **쉬움** | 우측 컨트롤 컬럼(`:854-885`)에 `_NavIconBtn` 하나 추가 + `_reroute(pos)` 직접 호출 핸들러. 쿨다운/폴백은 `_reroute()` 레이어에 게이트가 없어 구조적으로 자동 우회됨(§4). 부족한 건 로딩/비활성 상태 UI뿐(`_isRerouting`이 현재 미바인딩). |
| **(C) 하단 앵커 카메라** | **MapLibre 특유 트릭 필요, 중간~어려움** | **카메라 패딩(a)은 0.26.1에 없음 — 사용 불가.** 유일한 경로는 (b) 전방 오프셋 타겟(`offsetOrigin` 재사용) + `getMetersPerPixelAtLatitude`로 줌별 미터/픽셀 역산해 화면상 비율(10~15%)을 유지. `_recenter`(`:526-538`) 내부 로직을 수정해야 하고, 동적 줌(`_navZoom`)과 오프셋 계산이 얽히므로 같은 프레임에서 재계산 필요. 정지/저속(`headingDeg == null`, speedKmh ≤ 2) 구간 폴백(중앙 배치) 별도 처리 필요. bearing이 이미 heading을 따라 회전 중이므로(§2) 오프셋 방향 계산 자체는 heading 그대로 쓰면 되고 별도 화면-좌표 변환은 불필요. |

**카메라 패딩 실현성 최종 판정**: MapLibre gl 0.26.1 플러그인은 지속적 뷰포트 패딩 API를 제공하지 않는다. (C)는 반드시 (b) 전방-타겟 오프셋 방식으로 구현해야 하며, 줌 연동 미터/픽셀 보정이 정확도의 핵심이다.
