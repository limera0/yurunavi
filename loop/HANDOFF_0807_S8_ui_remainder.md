GOAL: S8 UI 잔여 5건 처리 — 시스템바 색상 실제 미반영 지점 수정, 주유소 경유지 마커 표시 회귀 수정, 하단 카드 전체거리→남은거리, 하단 카드 현위치/목적지 3초 교대 표시, 상단 카드 장거리 줄바꿈 방지.

- 작성 2026-08-07 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S8 (376~388행)
- ⚠️ 이 작업은 **S7(HANDOFF_0807_S7_tunnel_dead_reckoning.md) 완료·커밋 이후에 시작할 것.**
  둘 다 `nav_screen.dart`를 건드린다 — 동시에 진행하면 같은 워크트리에서 충돌한다.

## 1. 시스템바 색상 — "홈은 투명" 아님, "#F5F1EC 통일이 일부 화면에서 누락됨"

> **마스터 확인 (2026-08-07)**: 체크리스트 원문("홈: 상단/하단 모두 투명 / 내비: 상단 투명,
> 하단 검정")은 **오전사**다. 실제 지적은 "2026-07-30 라운드2에서 분명히 `#F5F1EC`로
> 통일하라고 했는데 반영이 안 되고 투명하게 보여서 잘못됐다"는 것. **목표는 정반대 —
> 투명화가 아니라 전체를 `#F5F1EC`(`kSystemBarColor`)로 완전히 통일.**

**근본원인을 이 세션에서 특정했다.** `main.dart`(홈/코스시트/경로옵션시트)와
`nav_screen.dart`(내비 진입·dispose)는 이미 `kSystemBarColor`로 정확히 설정돼 있다
(라운드2 작업 그대로, 코드 확인 완료 — 이 두 파일은 **손댈 필요 없음**). 문제는
**라운드2가 애초에 스코프를 "3장(홈/지도, 코스 시트, 경로 옵션 시트)"로 한정**했다는 데
있다(`loop/layout_fixes/PROGRESS.md:108-116`) — 그 뒤에 생긴 `AppBar` 기반 화면들은 한
번도 커버된 적이 없다:

```
lib/features/tour_summary/presentation/tour_summary_list_screen.dart  (히스토리)
lib/features/settings/presentation/favorite_categories_screen.dart
lib/features/profile/presentation/profile_screen.dart                  (내계정/내바이크)
lib/features/settings/presentation/settings_screen.dart
lib/features/settings/presentation/terms_screen.dart
```

`lib/core/theme/app_theme.dart:159` `AppBarTheme`에 `systemOverlayStyle`이 **설정돼 있지
않다.** Flutter의 `AppBar`는 `systemOverlayStyle`을 명시하지 않으면 자기 `backgroundColor`
밝기에서 스스로 계산해 **매 빌드마다 자체적으로 `SystemChrome.setSystemUIOverlayStyle`을
호출**한다(잘 알려진 Flutter 함정) — 이게 `main.dart`가 전역으로 걸어둔 `kSystemBarColor`를
조용히 덮어써 이 5개 화면에서 색이 어긋나 보이는 것이다. `main.dart`/`nav_screen.dart`
쪽 코드가 틀린 게 아니라 **AppBar가 나중에 이긴다.**

### 수정

- `app_theme.dart:159` `AppBarTheme(...)`에
  `systemOverlayStyle: const SystemUiOverlayStyle(statusBarColor: kSystemBarColor,
  statusBarIconBrightness: Brightness.dark, systemNavigationBarColor: kSystemBarColor,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false)` 추가 — **화면별로 5곳을 패치하는 대신 테마
  한 곳에서 전 AppBar에 일괄 적용**(향후 새 AppBar 화면이 생겨도 자동으로 통일 유지).
  `main.dart`/`nav_screen.dart`의 기존 3개 호출부는 그대로 둔다(AppBar 없는 화면은 여전히
  거기서 설정).
- 적용 후 5개 AppBar 화면 + 홈/코스시트/내비 전환을 오가며 상태바·내비바가 전부
  `#F5F1EC`로 보이는지 확인(실기기 없으면 위젯 테스트로 `AppBarTheme.systemOverlayStyle`
  값 자체를 검증 — 실제 OS 렌더링까지는 실기기 필요).

## 2. 주유소 경유지 마커 미표시

**원인 확정**(체크리스트 원문 그대로): `nav_screen.dart` `_initDestLayer()`가
`widget.waypoints`(불변, nav_screen 생성 시점 고정)를 순회해 심볼을 찍는데
`_destLayerReady` 가드로 **1회만** 실행된다. 주행 중 `_addGasStationWaypoint()`가 추가하는
건 `_liveWaypoints`(런타임 가변 복사본)뿐이라 지도엔 영영 안 그려진다.

- `_initDestLayer()`의 순회 대상을 `widget.waypoints` → `_liveWaypoints`로 교체(최초
  실행 시점에 이미 추가된 경유지까지 커버).
- `_addGasStationWaypoint()`에서 `_liveWaypoints.insert(insertIdx, stationLoc);` 직후,
  **레이어가 이미 초기화된 이후에 추가되는 경우**를 위해 그 지점 하나만 바로
  `ctrl.addSymbol(...)`(`_initDestLayer()`가 쓰는 것과 동일한 `SymbolOptions` — `iconImage:
  _kWpIcon, iconSize: _kWpIconSize, iconAnchor: 'bottom', zIndex: 5`)로 즉시 그린다.
  `_canCallMap() && _destLayerReady`일 때만(레이어 자체가 아직이면 위 1번 수정이 알아서
  커버하므로 여기서 중복 추가하지 않게).

## 3. 하단 카드 — 전체 거리 → 남은 거리

`nav_screen.dart:1885` `final routeKm = _polylineKm(widget.routePolyline);`은 **내비 시작
시점의 고정값**(주행해도 안 줄어듦). `:2497`에서 그 값을 그대로 표시 중.

- `progressSub` 리스너(`:556` 부근, `_cardRemainingM = prog.distToNextTurnM;`를 이미 하는
  그 자리)에 `_remainingRouteM = prog.distToDestM;` 추가(새 state 필드).
  초기값은 `routeKm * 1000`(첫 GPS fix 전 표시용 폴백)로 시드.
- `:2497` `routeKm > 0 ? ... : '--'`를
  `_remainingRouteM > 0 ? '${(_remainingRouteM/1000).toStringAsFixed(1)} km' : '--'`로 교체.

## 4. 하단 카드 — 현위치(시/군/구) ↔ 목적지 3초 교대

- `lib/services/geocoding_service.dart`에 시/군/구 수준만 반환하는 메서드 추가(예:
  `reverseGeocodeCoarse(lat, lng)` — 기존 `reverseGeocode`처럼 `Placemark`를 가져오되
  `administrativeArea + locality`만 조합, 예: "경기도 평택시". 기존 메서드와 `Placemark`
  fetch 로직 공유해도 됨).
- **디바운스 필수** — S2에서 겪은 "네트워크/기기 API 폭주" 재발 방지 원칙을 그대로 적용
  (이번엔 기기 내장 geocoder라 네트워크 요청은 아니지만, 1Hz GPS 틱마다 부르면 불필요한
  기기 API 호출 폭주는 마찬가지). 이동 300m 이상 또는 60초 경과 중 먼저 오는 조건에서만
  재조회(시/군/구는 자주 안 바뀌므로 이 정도면 충분) — S2의 `PoiFetchThrottle` 패턴 재사용
  가능하면 재사용.
- 하단 카드(`:2480` 목적지 이름 `Text` 자리)에 `Timer.periodic(Duration(seconds: 3))`로
  토글되는 bool 상태 추가 — 목적지 이름과 위 현위치 문자열을 교대로 표시.
  현위치 조회가 아직 안 됐거나 실패(null)면 교대하지 않고 목적지 이름만 표시(널 가드).
  타이머는 `initState`에서 시작, `dispose`에서 취소 필수(다른 `Timer` 필드들과 같은 패턴 —
  `_recenterTimer`/`_offRouteDebounce`/`_exitAutoCloseTimer`/`_compassNorthTimer` 옆에
  나란히).

## 5. 상단 카드 — 남은거리 10km+ 줄바꿈

`nav_screen.dart:2026-2027` `SizedBox(width: MediaQuery.of(context).size.width * 0.62, ...)`
— 고정폭이라 "10.0km" + 도로명이 길어지면 줄바꿈된다.

- **1순위(마스터 우선 해법)**: 고정폭 대신 컨텐츠에 맞춰 늘어나되 기본값(현재 62%)보다는
  작아지지 않게. `SizedBox(width: fixed)`를 `ConstrainedBox(constraints: BoxConstraints(
  minWidth: 62%, maxWidth: <화면 밖으로 안 나가는 상한>))` + 내부를 `IntrinsicWidth`로
  감싸는 방향. **주의**: 안쪽 `Expanded`(`:2066`, 텍스트 컬럼을 감싸는 것)는 `IntrinsicWidth`/
  가변폭 부모 안에서 동작하지 않는다(Flutter 제약 — `Expanded`는 폭이 확정된 부모가
  필요) — `Flexible` + `mainAxisSize: MainAxisSize.min`으로 바꾸거나 `Row` 자체를
  `mainAxisSize: MainAxisSize.min`으로 돌리는 등 구조 조정이 같이 필요하다. 이 부분은
  Flutter 레이아웃 세부사항이라 구현 중 실제로 렌더해보고(위젯 테스트로 overflow 여부
  확인) 판단할 것.
- **차선책(1순위가 너무 위험/복잡하면)**: 고정폭을 "88.8km"(3자리+소수점, 최대 케이스)
  기준으로 한 줄에 들어가는 값까지 넓힌다(예: 0.62 → 실측 후 조정). 평소 불필요한 여백이
  생기지 않는 선에서 최소한만 늘릴 것 — 임의로 크게 잡지 말고 실제 텍스트 폭을
  측정(`TextPainter` 또는 위젯 테스트로 overflow 확인)해서 근거를 남길 것.
- 어느 쪽으로 갔든 **완료 후 리포트에 어떤 방식을 썼는지와 그 이유**를 남길 것
  (이전 세션들의 "72px 결정" 같은 근거 기록 관례를 따른다).

## 검증 요구

- `flutter analyze` 이슈 0, `flutter test` 전건 통과(S7 완료 시점의 카운트 + 신규분)
- 신규 위젯 테스트: 남은거리 3~4자리 + 긴 도로명 조합에서 상단 카드 `RenderFlex overflow`
  없음(여러 자리수 조합으로 경계 테스트, S1의 DaylightBar 높이 경계테스트 패턴 참고)
- `AppBarTheme.systemOverlayStyle` 값이 `kSystemBarColor` 조합과 일치하는지 테마 테스트
- 주유소 마커: `_addGasStationWaypoint` 호출 후 `addSymbol`이 실제로 불리는지(mock
  MapLibre controller 대상 정적/단위 검증, 기존 지도 관련 테스트 패턴 참고)
- 실기기 검증(마스터 몫): 5개 AppBar 화면 육안 확인, 실제 남은거리 감소 확인, 3초 교대
  표시 육안 확인, 88.8km급 목적지에서 줄바꿈 없음, 주유소 추가 시 마커 즉시 표시

## 완료 후

- `code-auditor` PASS 후 커밋, `CHECKLIST_0805_testride0802.md` §S8 `[x]`로 갱신
- `loop/MORNING_REPORT_0807_S8_ui_remainder.md`에 기록(특히 시스템바 근본원인 재분류와
  상단 카드 방식 선택 이유를 명확히 남길 것)
