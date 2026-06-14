# 00 — 미확인 의문 & 리스크 누적 목록

> 분석 진행 중 발견된 미확인 사항을 지속 추가한다.
> 각 항목: 발견 경위 / 왜 중요한가 / 어떻게 검증할지.

---

## Q1. `class_factors` 가 Valhalla motorcycle costing에 실제 적용되는가? ✅ 해결

**발견 경위**: routing_service.dart L151-158, main.rs L219-221 에서 `class_factors` 키를 사용.  
**결론**: **적용됨** — Night7 (2026-06-02) curl 검증으로 확인. 3경로 각각 다른 거리(17.2/15.9/15.4km) 반환. `class_factors`를 포함해도 400 에러 없음.  
**근거**: git commit 10eab85 MORNING_REPORT_night7.md

---

## Q2. `use_living_streets`, `use_tracks` 가 실제 경로를 바꾸는가 vs 속도만 바꾸는가?

**발견 경위**: 시골길(L148-149)에서 `use_living_streets: 1.0`, `use_tracks: 0.8` 사용.  
**문제**: Valhalla에서 `use_*` 계열 파라미터는 "factor"이지, penalty가 아님. factor=1.0이면 해당 도로 유형을 "선호"하지만, 상대적으로 더 짧거나 빠른 경로가 있으면 여전히 그쪽으로 갈 수 있음.  
**검증 방법**: 동일 OD에서 `use_tracks: 0.8` vs `use_tracks: 0.0` 비교 테스트.

---

## Q3. `top_speed: 40` 이 경로 선택에 영향을 주는가?

**발견 경위**: 시골길(L150)에서 사용. ETA 계산 속도를 제한하는 파라미터.  
**문제**: Valhalla의 `top_speed`는 내부 비용 계산에서 에지 트래버스 코스트를 높이는 방식으로 작동. 이로 인해 60-80km/h 도로의 "비용"이 올라가 간접적으로 저속 도로가 선택될 수 있음. 단, 효과가 얼마나 강한지 불명확.  
**검증 방법**: 실제 Valhalla 응답에서 시골길/지방도로의 geometry 비교.

---

## Q4. `urban_penalty: 50.0` 의 효과 범위

**발견 경위**: 시골길 opts(L159)에서만 사용.  
**문제**: Valhalla `urban_penalty`는 urban classified 도로에 추가 페널티를 부여. "urban" 분류의 OSM 기준이 불명확 — `urban=yes` 태그 혹은 도시 내 도로 속도 기준으로 판단하는지 확인 필요.

---

## Q5. 현재 캐시 키에 costing_options가 포함되지 않음

**발견 경위**: routing_service.dart L107-113.  
**문제**: 캐시 키가 `origin→destination|waypoints` 형태로, 코스 타입 정보가 없음. 하지만 `fetchRoutes`는 항상 3코스를 함께 반환하므로 현재는 문제없음. 단, 미래에 코스별 개별 호출로 분리할 경우 캐시 충돌 발생 가능.

---

## Q6. Rust 서버(`navi.westinx.com:8003`)와 Valhalla 서버(`valhalla.westinx.com`) 이중 라우팅 경로

**발견 경위**: native_engine.dart L170-231 에서 Rust HTTP 서버 우선 → Dart fallback 구조.  
**문제**: `NativeEngine.calcRoute()`는 현재 어디서도 호출되지 않음(`main_map_screen.dart`는 `RoutingService.fetchRoutes()`만 사용). Rust HTTP 서버(`handle_calc_route`)는 단일 routeType만 처리하므로, RoutingService의 3코스 병렬 패턴과 API 불일치.  
**검증 방법**: `grep -rn "calcRoute\|calcDummyRoute" lib/` — 실제 호출 지점 확인.

---

## Q7. `scoreFunV2` 결과가 UI에서 어떻게 활용되는가 — 경로 선택에 영향 없음

**발견 경위**: main_map_screen.dart L534-541에서 `NativeEngine.scoreFunV2()`를 3코스 각각 호출 후 `windingScore`로 저장.  
**문제**: fun_score_v2/v3는 현재 **표시 전용** — 가장 높은 점수 카드에 "베스트" 뱃지 표시(L1438). 라우팅 결과를 바꾸거나 경로를 재랭킹하지 않음.  
**의미**: fun-road scoring 인프라는 구축되어 있지만, 실제로 "재미있는 경로를 선택"하는 루프가 아직 연결되지 않은 상태.

---

## Q8. Valhalla `motorcycle` costing의 정확한 정의

**추정**: `motorcycle`은 `auto` 계열에서 파생된 costing으로, 오토바이의 특성(좁은 길 통과 가능, 고속도로 제한 없음)을 반영. Valhalla 공식 API ref에서 motorcycle 전용 파라미터 목록 확인 필요.  
**공식 문서 위치**: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/ (costing models 섹션)

---

## Q9. `exclude_polygons` / `avoid_locations` API 가용성

**발견 경위**: 문서3 옵션C 분석 중.  
**문제**: Valhalla의 `exclude_polygons`는 모든 버전에서 지원되지 않을 수 있음. `westinx.com`의 Valhalla 버전 확인 필요.  
**검증 방법**: `/status` 엔드포인트에서 버전 조회; `exclude_polygons`를 포함한 요청을 직접 테스트(단, 본 분석에서는 금지).

---

## Q10. fun_score_v4(숲 근접도)의 OSM 데이터 가용성

**발견 경위**: api.rs L329-340에 `fun_score_v4` 구현 존재.  
**문제**: `forest_proximity` 파라미터가 0.0으로 하드코딩 되어있음(호출부 없음). OSM `landuse=forest`/`natural=wood` 폴리곤과의 경로 교차 계산이 아직 구현되지 않음. 이를 자가호스팅 환경에서 실시간으로 처리하려면 PostGIS + ST_Intersects 또는 R-tree 전처리가 필요.

---

## Q11. `_ruralDetourThreshold = 1.3` 기준의 근거

**발견 경위**: routing_service.dart L97.  
**문제**: 1.3배 기준이 임의로 설정된 것인지, 실측 기반인지 불명확. 너무 낮으면 시골길이 과도하게 balanced로 대체되어 차별화 손실. 너무 높으면 비현실적 우회로를 허용.

---

## Q12. 네비게이션 재탐색 시 선택된 코스 무시 — 버그

**발견 경위**: nav_screen.dart L311.

```dart
// nav_screen.dart L306-311 (_reroute 메서드)
final routes = await RoutingService.fetchRoutes(
  origin: origin,
  destination: dest,
  waypoints: widget.waypoints,
);
if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);
```

**문제**: 경로 이탈 후 재탐색 시 `routes[0]`(=시골길 코스)을 항상 사용. 사용자가 국도 코스(idx 2)를 선택했어도 재탐색 후 시골길 경로로 강제 전환됨.  
**수정 방법**: NavScreen에 `selectedRouteIdx` 파라미터 추가, `_reroute`에서 `routes[selectedRouteIdx].points` 사용.  
**영향 범위**: nav_screen.dart + NavScreen 호출부(main_map_screen.dart)

---

## Q13. NavScreen이 코스 정보를 전혀 받지 않음

**발견 경위**: NavScreen 생성자 (nav_screen.dart L26-38):
```dart
class NavScreen extends ConsumerStatefulWidget {
  final LatLng? destination;
  final List<LatLng> waypoints;
  final List<LatLng> routePolyline;
  final List<ManeuverStep> maneuvers;
  // selectedRouteIdx 없음!
```

**문제**: 선택된 코스 인덱스가 NavScreen으로 전달되지 않아 재탐색 시 코스 일관성 유지 불가.

---

## Q14. `_ruralBalancedOpts`와 Rust 서버 balanced 설정의 동기화

**발견 경위**: routing_service.dart L85-95의 `_ruralBalancedOpts`와 main.rs L256-262의 balanced 페이로드.

두 구현의 `class_factors` 비교:
- Dart: `{'1': 100.0, '2': 4.0, '3': 1.2, '4': 0.8, '5': 0.5}` (use_ferry: 0.0만 추가)
- Rust: 동일 (main.rs L260-261)

두 파일이 동기화되어 있음 (코드에서 확인). 단, 향후 한쪽만 수정 시 불일치 발생 위험.

---

*마지막 업데이트: 2026-06-05 (분석 Round 1 + 심화)*
