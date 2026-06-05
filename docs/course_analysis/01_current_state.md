# 01 — 현황 진단: 왜 3코스가 같은 경로인가

> **코드에서 확인** / **문서에서 확인** / **추정** 을 각 항목 뒤에 명시함.

---

## 1. 3코스 Valhalla 요청 구조 — 정확한 코드 인용

### 1.1 `routing_service.dart` — Dart 클라이언트

파일 위치: `lib/services/routing_service.dart`

**공통 사항** (코드에서 확인):

- 3코스 모두 `"costing": "motorcycle"` [L240]
- 3코스 모두 `'use_highways': 0.0` [L146, L162, L177]
- 3코스 모두 `'use_ferry': 0.0` [L147, L163, L178]
- 3코스를 **병렬로 동시 요청** (`Future.wait`) [L233-249]

**코스별 costing_options** (코드에서 확인):

| 파라미터 | 시골길 (idx 0) | 지방도로 (idx 1) | 국도 (idx 2) |
|---|---|---|---|
| `use_living_streets` | `1.0` | `0.5` | `0.0` |
| `use_tracks` | `0.8` | `0.2` | `0.0` |
| `top_speed` | `40` | (없음) | (없음) |
| `shortest` | (없음) | (없음) | `true` |
| `urban_penalty` | `50.0` | (없음) | (없음) |
| `class_factors["1"]` | `100.0` | `100.0` | `100.0` |
| `class_factors["2"]` | `5.0` | `2.0` | `0.4` |
| `class_factors["3"]` | `2.5` | `0.5` | `1.0` |
| `class_factors["4"]` | `1.0` | `0.7` | `2.0` |
| `class_factors["5"]` | `0.2` | `1.5` | `10.0` |

코드 인용 (라인 번호):
```
// 시골길 L143-159
{
  'use_highways': 0.0, 'use_ferry': 0.0,
  'use_living_streets': 1.0, 'use_tracks': 0.8,
  'top_speed': 40,
  'class_factors': { '1': 100.0, '2': 5.0, '3': 2.5, '4': 1.0, '5': 0.2 },
  'urban_penalty': 50.0,
}

// 지방도로 L161-173
{
  'use_highways': 0.0, 'use_ferry': 0.0,
  'use_living_streets': 0.5, 'use_tracks': 0.2,
  'class_factors': { '1': 100.0, '2': 2.0, '3': 0.5, '4': 0.7, '5': 1.5 },
}

// 국도 L175-188
{
  'use_highways': 0.0, 'use_ferry': 0.0,
  'use_living_streets': 0.0, 'use_tracks': 0.0,
  'shortest': true,
  'class_factors': { '1': 100.0, '2': 0.4, '3': 1.0, '4': 2.0, '5': 10.0 },
}
```

### 1.2 `native/src/main.rs` — Rust HTTP 서버

파일 위치: `native/src/main.rs`

**중요**: Rust 서버의 `/calc_route`는 **현재 앱에서 호출되지 않는다** (코드에서 확인).

- `main_map_screen.dart`는 `RoutingService.fetchRoutes()`만 호출 [main_map_screen.dart L526]
- `NativeEngine.calcRoute()`는 Rust HTTP 서버를 호출하나, 이 함수 자체가 앱 경로에서 사용되지 않음
- Rust 서버의 costing 설정은 Dart의 것과 동일 [main.rs L215-239]

Rust 서버 `handle_calc_route`의 구조 (코드에서 확인, main.rs L199-309):
1. `route_type` 0 (시골길): rural + provincial 병렬 요청 → 1.3배 폴백 로직
2. `route_type` 1/2: 단일 요청
3. 응답에 `trace_attributes`로 FC 평균 계산 → `fun_score_v2/v3` 포함

---

## 2. ETA 계산 방식 — geometry와 무관하게 재계산

**핵심 발견** (코드에서 확인):

routing_service.dart L285-291:
```dart
final km = legs.fold<double>(0, (sum, leg) =>
    sum + ((leg['summary']?['length'] as num?) ?? 0).toDouble());
final realisticMins = (km / _courseSpeeds[i] * 60).round();
```

즉, **ETA는 Valhalla 응답의 `time` 필드를 무시하고** 코스별 고정 속도로 재계산한다:
- 시골길: 30km/h [L71]
- 지방도로: 36km/h [L72]  
- 국도: 45km/h [L73]

이것이 "3코스가 거리는 같고 시간만 다르다"는 현상의 **Dart 쪽 원인**이다.

---

## 3. 핵심 진단: 왜 geometry가 같은가

### 3.0 `class_factors` 작동 여부 — **이미 검증됨** (코드에서 확인, git history)

**[코드에서 확인 — Night7 커밋 10eab85]**

Night7 (2026-06-02) curl 검증 결과:
- 수원 영통구 → 용인 처인구
- 시골길: **17.2km** / 지방도로: **15.9km** / 국도: **15.4km**
- `class_factors`, `urban_penalty` 파라미터 → 400 에러 없음 → 적용됨 ✅

Night6b (2026-06-02) curl 검증 결과:
- 서울강남 → 동탄
- 시골길: **45.6km** / 지방도로: **42.4km** / 국도: **40.6km** (shape 문자수: 4664/3796/2271)

**결론**: `class_factors`는 Valhalla motorcycle costing에 실제로 적용된다. 3코스가 다른 거리와 shape을 가짐이 확인됨.

### 3.1 그렇다면 "같은 경로" 문제의 진짜 원인은?

**[코드에서 확인]** Night7 curl 검증으로 `class_factors`는 motorcycle costing에 실제 적용됨이 확인됨. 3코스 거리가 다름(17.2/15.9/15.4 km).

### 3.2 재진단: 수치상 다른데 "같아 보이는" 이유

**[코드에서 확인 + 추정]**

Night7 검증에서 "3경로가 수치상 다름"은 확인됐지만, 사용자가 폰에서 "같아 보인다"고 느끼는 이유:

1. **간선 구간 공유**: 장거리 OD(서울→부산 등)에서 200~300km의 간선 구간은 세 코스 모두 같은 국도를 사용. 출발/도착 근처의 1~5km 구간만 다름. 지도로 확대하지 않으면 차이가 보이지 않음.

2. **"시골길다운 구불구불함"이 없음**: 현재 class_factors는 도로 등급만 조정. 설령 시골길이 FC5 도로를 경유하더라도, 그 도로가 직선이라면 "시골길다운" 느낌이 없음. 곡률(curviness)은 Valhalla에서 제어 불가.

3. **한국 OSM의 FC5 네트워크 한계**: 한국 오지의 임도/농도는 OSM에서 연속된 네트워크로 구성되지 않아, Valhalla가 장거리에서 FC5 일관 경로를 만들 수 없음.

4. **사용자 기대와 현실의 갭**: "시골길"은 "구불구불한 길"이지만 Valhalla는 "소규모 도로 경유 경로"를 만들 뿐. 이 둘은 같지 않음.

### 3.3 문제의 진짜 본질 재정의

**현재 3코스는 수치상으로는 다르다 (Night7 curl 검증). 그러나 다음 이유로 "진짜 차별화"가 되지 않는다:**

1. **차이의 규모가 작음**: 15.4 vs 17.2km (11% 차이) — 같은 주요 도로 사용하면서 우회 정도만 다름
2. **곡률 차별화 불가**: Valhalla는 "더 구불구불한 길"을 선호하게 할 수 없음
3. **감성적 차별화 없음**: "시골길스러운 경치"는 도로 데이터에 없음, fun_score로만 측정 가능

---

## 4. ETA가 다른 이유 — 단순 수식 차이

(코드에서 확인, L285-291)

3코스의 ETA는 Valhalla 응답과 무관하게 `km / speed * 60`으로 재계산된다. 속도가 30/36/45km/h로 다르므로 동일한 `km`에서 ETA가 다르게 나온다. 이것이 "거리 같고 시간만 다른" 현상의 전부다.

예시: 100km 경로라면
- 시골길: 100/30×60 = 200분
- 지방도로: 100/36×60 = 167분
- 국도: 100/45×60 = 133분

---

## 5. 코드 흐름 전체 요약

```
사용자 목적지 탭
  └→ _fetchAndStoreAllRoutes() [main_map_screen.dart L522]
       └→ RoutingService.fetchRoutes() [routing_service.dart L118]
            └→ _doFetch() [L229] — 3개 Future.wait 병렬 요청
                 ├── 시골길: costing=motorcycle, use_living_streets=1.0, ...
                 ├── 지방도로: costing=motorcycle, use_living_streets=0.5, ...
                 └── 국도: costing=motorcycle, shortest=true, ...
            └→ 시골길 1.3배 폴백 체크 [L320-388]
            └→ 결과: List<RouteResult> (points, distanceKm, durationMin, maneuvers)
                 * durationMin = distanceKm / _courseSpeeds[i] * 60 (Valhalla time 무시!)
       └→ NativeEngine.scoreFunV2(points) × 3 [L534-541]
            └→ Rust /score_route 호출 → fun_score_v2 (표시 전용, 경로 변경 없음)
       └→ UI에 3카드 표시 (같은 geometry, 다른 ETA + fun_score 뱃지)
```

---

## 6. 결론: 현재 구조의 달성과 한계

**달성된 것 (코드에서 확인)**:
- 3코스가 수치상으로는 다른 거리와 geometry를 가짐 (Night7 curl 검증: 15.4/15.9/17.2km)
- `class_factors`로 FC 등급별 도로 선호가 실제로 작동
- ETA가 코스별 실효속도로 현실적으로 계산됨
- fun_score_v2/v3가 계산되어 UI에 표시됨
- 시골길 과다우회 1.3배 폴백으로 극단적 우회 방지됨

**근본 한계 (구조적 제약)**:
1. **곡률 선호 불가**: Valhalla에는 "굽이진 길을 선호하는" 파라미터가 없음. 도로 등급 우선이라도 직선 소도로가 선택될 수 있음.
2. **장거리 간선 공유**: 수백 km 경로에서 간선 구간은 세 코스 모두 동일. 차이는 출발/도착 근처에 집중됨.
3. **fun_score가 경로를 선택하지 않음**: fun_score는 결과 측정에만 사용. 경로 생성에 피드백되지 않아 순서가 역전됨.
4. **Rust `rank_candidates_v2` 미연결**: 이미 구현된 재랭킹 함수가 파이프라인에 연결되지 않음.

Valhalla 노브만으로는 "즐거운 경로"와 "빠른 경로"를 구분하는 데 구조적 한계가 있다. Rust fun-road 레이어에서 후보 경로들을 곡률+도로등급+속도 기준으로 재랭킹하는 것이 유일한 근본 해결책이다.

---

## 7. 코스 표시 UI 현황

(코드에서 확인, main_map_screen.dart L1364-1366):
```dart
static const _routes = [
  _RouteInfo('시골길로\n느긋하게', AppColors.mapCourse),    // 녹색
  _RouteInfo('지방도로\n여유롭게', AppColors.tertiary),     // 파랑 계열
  _RouteInfo('국도로\n빠르게', AppColors.primary),          // 주황/틸
];
```

코스 선택 시 (_onRouteCardSelect, L658-680):
- 이미 페치된 3경로 중 해당 인덱스로 polyline 전환 — Valhalla 재호출 없음
- fun_score_v2 기준 "Best" 뱃지 표시 (L1438)
- 카드 선택이 실제 라우팅에는 영향 없음 (이미 페치된 결과 중 선택만)

---

## 8. 네비게이션 재탐색의 추가 문제 — 코스 선택 소멸

(코드에서 확인, nav_screen.dart L300-317)

```dart
Future<void> _reroute(LatLng origin) async {
  // ...
  final routes = await RoutingService.fetchRoutes(
    origin: origin,
    destination: dest,
    waypoints: widget.waypoints,  // 경유지는 전달
  );
  // ⚠️ 항상 routes[0](시골길)을 사용 — 선택된 코스 무시!
  if (mounted && routes.isNotEmpty) setState(() => _routePoints = routes[0].points);
}
```

NavScreen은 `selectedRouteIdx`를 파라미터로 받지 않는다 (nav_screen.dart L26-38). 따라서:
1. 사용자가 국도(idx 2)를 선택하고 내비게이션 시작
2. 경로 이탈 발생 → `_reroute()` 호출
3. 재탐색 결과의 `routes[0]`(시골길) 경로를 사용 → 코스 강제 변경

**이것은 현재의 진짜 버그다** — 코스 차별화 문제와 별개로, 이 버그는 코스 선택 기능 자체를 무력화한다.

---

## 8B. ROADMAP v2 item 1 현황 정리

(코드에서 확인 — ROADMAP.md, TASK_fallback_rural.md, git history)

**ROADMAP v2 item 1**: "fun-road costing 실제 구현: Rust /calc_route가 반환하는 fun_score를 Valhalla custom_costing에 실제 반영 → 3경로가 진짜 다른 도로를 탐색하도록. 검증: 동일 출발/도착에 대해 3경로의 폴리라인이 서로 30% 이상 달라야 PASS."

**현재 달성 수준**:
- ✅ 3경로가 다른 도로 탐색: Night7 검증 (17.2/15.9/15.4km, 다른 shape)
- ✅ 시골길 1.3배 폴백: cc6104d 커밋으로 구현
- ❌ "폴리라인 30% 이상 다름" 검증: 아직 미수행 (폰 시각 확인 미완)
- ❌ fun_score를 라우팅 경로 선택에 반영: rank_candidates_v2 미연결

**TASK_fallback_rural.md 평가**: "item 1은 사실상 종료" — 그러나 이는 기본적인 3경로 분기가 동작하는 것을 말하며, "fun_score 기반 재랭킹"은 별도 작업으로 분류됨.

**결론**: ROADMAP item 1의 기초(3경로 분기, ETA 현실화, 폴백)는 완료. 고급 기능(fun_score 재랭킹, 곡률 차별화)은 미구현.

---

## 9. 전체 컴포넌트 상호작용 다이어그램

```
┌─────────────────────────────────────────────────────────────────────┐
│                          유루나비 라우팅 파이프라인                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  사용자 탭                                                            │
│  └→ main_map_screen.dart:_applyDestination()                         │
│       └→ RoutingService.fetchRoutes()                                 │
│            └→ Valhalla 3병렬 요청 (motorcycle costing x3)             │
│            └→ 1.3배 폴백 체크 (시골길 과다우회 방지)                  │
│            └→ List<RouteResult>(3개)                                  │
│       └→ NativeEngine.scoreFunV2() x3 (Rust /score_route)           │
│            └→ trace_attributes → avg_fc → fun_score_v2               │
│       └→ mapInteractionProvider.setAllRouteMeta()                    │
│       └→ UI: 3카드 (거리, ETA, fun_score 뱃지)                       │
│                                                                       │
│  카드 선택                                                            │
│  └→ _onRouteCardSelect(idx)                                          │
│       └→ allRoutes[idx] → routePolyline 갱신                         │
│       └→ _fetchedRoutes[idx].maneuvers → _selectedManeuvers          │
│                                                                       │
│  내비게이션 시작                                                       │
│  └→ NavScreen(routePolyline, maneuvers)                              │
│       └→ ⚠️ selectedRouteIdx 전달 없음                               │
│       └→ _reroute() → RoutingService.fetchRoutes() → routes[0] ⚠️   │
│                                                                       │
│  Rust 서버 (native/src/main.rs, port 8003)                           │
│  └→ /calc_route — 현재 앱에서 사용 안 함                              │
│  └→ /score_route — fun_score_v2/v3 계산에 사용                       │
│  └→ VALHALLA_URL = "http://localhost:8002/route" (로컬 서버!)        │
│       ↑ Dart는 https://valhalla.westinx.com 사용                     │
│       ↑ Rust는 localhost:8002 사용 → 다른 Valhalla 인스턴스?          │
└─────────────────────────────────────────────────────────────────────┘
```

**중요 발견**: Rust 서버는 `http://localhost:8002/route`를 사용하고, Dart는 `https://valhalla.westinx.com`을 사용한다. 이는 동일한 Valhalla 서버인가 다른 인스턴스인가? (추정 — 서버 설정 확인 필요)

---

*작성: 2026-06-05 (분석 Round 1 + 심화)*
