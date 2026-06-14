# 04 — 단계별 구현 로드맵

> 전제: 문서3의 권장 전략(옵션 B+D1 조합).  
> 마스터의 작업 원칙: 한 단계=한 커밋, 단일 파일 스코프, 정찰→실행 분리, 폰 실측이 동작 증거.

---

## 0. 전제 조건 — 이미 확인된 것

**[코드에서 확인 — Night7 커밋 10eab85]**

`class_factors`는 motorcycle costing에 적용됨이 이미 검증됨:
- Night7 curl 검증: 3경로 각각 다른 거리(17.2/15.9/15.4 km)
- Night6b curl 검증: 3경로 각각 다른 거리(45.6/42.4/40.6 km), shape 문자수 상이

따라서 **Phase 2의 optionB (class_factors 강화)는 유효한 전략**이다.

현재 문제는 "수치상 다른 경로가 '시골길다운 느낌'을 주지 못하는 것"이므로, 해결책은:
1. class_factors를 더 극단적으로 조정해 차이를 확대 (단기)
2. fun_score 기반 재랭킹으로 곡률이 높은 경로를 시골길에 매핑 (중기, 핵심)

---

## 0-B. Valhalla alternates 지원 여부 확인 (마스터 확인 필요 ⚠️)

> **⚠️ 마스터 확인 필요**

Phase 3 (alternates 재랭킹)은 Valhalla의 `"alternates": N` 파라미터 지원에 의존.

검증 방법:
```bash
curl -X POST https://valhalla.westinx.com/route \
  -H "Content-Type: application/json" \
  -d '{"locations":[{"lat":37.5,"lon":127.0},{"lat":37.7,"lon":127.3}],
       "costing":"motorcycle",
       "costing_options":{"motorcycle":{"use_highways":0.0}},
       "alternates":2}'
```

결과 확인:
- 응답에 `alternates[0]`, `alternates[1]` 존재 → Phase 3 가능
- 400 에러 또는 alternates 없음 → Phase 3 불가 → Phase 2 강화에 집중

---

## Phase 0.5: 즉시 가능한 2파일 개선 (낮은 위험)

### Step 0.5: fun_score_v3 UI 표시 (2파일)

**대상 파일**: `lib/services/native_engine.dart` + `lib/features/map/presentation/main_map_screen.dart`  
**작업**:
1. `FunScoreResult`에 `funScoreV3`, `avgSpeedKmh` 필드 추가
2. `/score_route` 응답 파싱에서 `fun_score_v3`, `avg_speed_kmh` 추출
3. `windingScore`에 `funScoreV3` 사용 (현재 `funScoreV2`)

**이유**: `/score_route`는 이미 `fun_score_v3`를 계산하지만 Flutter가 받지 않음. v3는 교통량(speed) 20%를 포함해 더 현실적인 "재미" 지표.  
**회귀 위험**: 없음 — 표시 지표만 변경, 경로 자체 변경 없음  
**커밋 메시지**: `feat(scoring): expose fun_score_v3 + avg_speed in FunScoreResult`

---

## Phase 1: 정찰 — 현재 3코스의 실제 차이 확인

### Step 1-A: 로그 강화 커밋 (단일 파일 스코프)

**대상 파일**: `lib/services/routing_service.dart`  
**작업**: `_doFetch()`에서 3코스 응답의 `trip.summary.length` + `trip.summary.time` + 경로 첫 5 포인트를 dev.log로 출력  
**커밋 메시지**: `feat(routing): add per-course geometry debug log`

```dart
// routing_service.dart에 추가 (기존 L304-310 dev.log 확장)
dev.log(
  'Valhalla [${_courseNames[i]}] '
  'valhalla_time=${(trip['summary']?['time'] as num?)?.toInt()}s '
  'pts_preview=${pts.take(3).map((p) => '(${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)})').join(' ')}',
  name: 'RoutingService',
);
```

**폰에서 확인**: flutter run으로 목적지 설정 후 Android Studio Logcat에서 3코스 좌표 프리뷰 비교.  
**기대 결과**: 좌표가 완전히 동일 → 현재 동일 geometry 확인.  
**롤백**: 로그 라인 제거.

---

### Step 1-B: Valhalla alternates 정찰

**⚠️ 마스터 확인 필요**

검증 (마스터 수행):
```bash
curl -X POST https://valhalla.westinx.com/route \
  -H "Content-Type: application/json" \
  -d '{"locations":[{"lat":37.5,"lon":127.0},{"lat":37.7,"lon":127.3}],
       "costing":"motorcycle",
       "costing_options":{"motorcycle":{"use_highways":0.0}},
       "alternates":2}'
```

결과 확인:
- 응답에 `trip` + `alternates[0]`, `alternates[1]` 존재 여부
- 각 경로의 geometry 차이 (서로 다른 경로인지)

---

## Phase 2: 옵션B 적용 — costing_options 강화

### Step 2-A: 시골길 top_speed 강화 (단일 파일)

**대상 파일**: `lib/services/routing_service.dart`  
**변경**: 시골길 `top_speed: 40 → 30`  
**회귀 위험**: 낮음 — 기존보다 소로 선호 증가, 극단적 우회 가능성 있음  
**폰에서 확인**: 동일 OD에서 시골길 geometry가 지방도로와 달라지는지 확인  
**롤백**: `top_speed: 30 → 40`

```dart
// L143-159 시골길 opts 변경
{
  'use_highways': 0.0,
  'use_ferry': 0.0,
  'use_living_streets': 1.0,
  'use_tracks': 1.0,        // 0.8 → 1.0
  'top_speed': 30,          // 40 → 30
  'class_factors': {
    '1': 1000.0,            // 100.0 → 1000.0
    '2': 50.0,              // 5.0 → 50.0
    '3': 5.0,               // 2.5 → 5.0
    '4': 0.5,               // 1.0 → 0.5
    '5': 0.05,              // 0.2 → 0.05
  },
  'urban_penalty': 100.0,   // 50.0 → 100.0
}
```

**커밋 전 확인**: 1.3배 폴백이 시골길 강화 후에도 정상 작동하는지 (너무 강한 우회 방지).

---

### Step 2-B: 국도 class_factors 강화 (단일 파일)

**대상 파일**: `lib/services/routing_service.dart`  
**변경**: 국도 FC2 계수 `0.4 → 0.1`, FC5 계수 `10.0 → 100.0`  
**회귀 위험**: 낮음 — 국도가 더 직선화, 소도로 완전 차단  
**폰에서 확인**: 국도 경로가 시골길과 완전히 다른 geometry 사용하는지 확인

```dart
// L175-188 국도 opts 변경
{
  'use_highways': 0.0,
  'use_ferry': 0.0,
  'use_living_streets': 0.0,
  'use_tracks': 0.0,
  'shortest': true,
  'class_factors': {
    '1': 1000.0,  // 100.0 → 1000.0
    '2': 0.1,     // 0.4 → 0.1
    '3': 0.5,
    '4': 10.0,    // 2.0 → 10.0
    '5': 100.0,   // 10.0 → 100.0
  },
}
```

---

### Step 2-C: main.rs Rust 서버 동기화 (단일 파일)

**대상 파일**: `native/src/main.rs`  
**변경**: `rural_payload`, `natl_payload`의 costing_options를 Step 2-A/2-B와 동일하게 갱신  
**회귀 위험**: 낮음 — Rust 서버는 현재 앱에서 직접 사용되지 않음  
**롤백**: revert

---

## Phase 3: Valhalla alternates + Rust 재랭킹

> **⚠️ Phase 3 전체는 마스터 확인 후 진행 필요**

Phase 3는 구조를 바꾸는 변경이므로, Phase 2의 결과(3코스가 실제로 다른 경로를 반환하는지)를 먼저 평가 후 결정.

### Step 3-A: alternates 파라미터 추가 (routing_service.dart)

**대상 파일**: `lib/services/routing_service.dart`  
**변경**: `_doFetch()`에서 시골길/지방도로 요청에 `"alternates": 1` 추가  
**목적**: 각 코스마다 Valhalla 자체 대안 경로 1개 확보  
**회귀 위험**: 중간 — 응답 구조 변경 → 파싱 로직 수정 필요

```dart
body: jsonEncode({
  'locations': locations,
  'costing': 'motorcycle',
  'costing_options': {'motorcycle': opts},
  'alternates': i < 2 ? 1 : 0,  // 시골길/지방도로만 alternate 요청
}),
```

---

### Step 3-B: Rust fun_score 기반 코스 매핑

**대상 파일**: `lib/services/routing_service.dart` + `native/src/main.rs`  
**변경**:
1. alternates 경로까지 포함한 후보군 수집 (최대 6개)
2. 각 후보를 Rust `/score_route`에 보내 fun_score_v2 계산
3. fun_score 기준 정렬 → 1위=시골길, 중간=지방도로, 최하위=국도 매핑

**API 설계 (의사코드)**:
```dart
// 1. Valhalla에서 alternates 포함 최대 6경로 수집
final candidates = await _fetchWithAlternates(locations, costingOptions);

// 2. Rust fun_score 계산
final scores = await Future.wait(
  candidates.map((c) => NativeEngine.scoreFunV2(c.points)),
);

// 3. 점수 기준 정렬
final ranked = [...candidates]
    ..sort((a, b) => scores[candidates.indexOf(b)].funScoreV2
                       .compareTo(scores[candidates.indexOf(a)].funScoreV2));

// 4. 코스 매핑
return [
  ranked[0],  // 시골길 = fun_score 최고
  ranked[ranked.length ~/ 2],  // 지방도로 = 중간
  ranked.last,  // 국도 = fun_score 최저
];
```

**폰에서 확인**: 3카드 geometry가 서로 완전히 다른지, fun_score 수치가 예상대로 분포하는지.  
**롤백 포인트**: alternates 파라미터 제거 → 기존 3코스 요청으로 복귀.

---

## Phase 4: Rust fun_score_v4 (숲 데이터 연동)

> **⚠️ 장기 과제, 마스터 확인 필수**

### Step 4-A: OSM 숲 폴리곤 인덱스 구축

**대상**: 인프라 작업 (코드 외)  
**작업**: `korea.mbtiles`에서 `landuse=forest` / `natural=wood` 폴리곤 추출 → GeoJSON 또는 간소화 래스터 인덱스 생성  
**도구**: osmium, ogr2ogr, PostGIS  
**마스터 확인 포인트**: 인덱스 크기 / 쿼리 응답 속도 / 메모리 요구사항

### Step 4-B: Rust 서버 /score_route forest_proximity 계산 추가

**대상 파일**: `native/src/main.rs`  
**변경**: `handle_score_route`에서 경로 포인트 + 숲 인덱스 쿼리 → `forest_proximity` 계산 → `fun_score_v4` 사용  
**회귀 위험**: 높음 — 새 의존성(숲 인덱스) 추가, 처리 시간 증가

---

## 가장 작고 안전한 첫걸음 ← **명확히 지목**

```
Step 2-A: routing_service.dart L143-159 시골길 top_speed 30으로 변경 + class_factors 극단화
```

이유:
1. **단일 파일** 변경 (`routing_service.dart`만)
2. **가역적** — 숫자 몇 개를 원래대로 돌리면 완전 롤백
3. **즉각 확인 가능** — 폰에서 목적지 설정하면 바로 시골길 geometry 변화 확인
4. **위험 최소** — 기존 폴백 로직(1.3배 폴백)이 과도한 우회를 방지
5. **class_factors 적용 여부도 동시 검증** — geometry가 달라지면 적용됨, 같으면 다음 전략으로

커밋 전 체크리스트:
- [ ] `top_speed: 30` → 시골길 코스에서 서울-부산 같은 장거리에서 비현실적 경로 안 나오는지
- [ ] `class_factors['2']: 50.0` → 지방도로 코스와 겹치는 구간 비율 확인
- [ ] 1.3배 폴백이 여전히 트리거되는지 (`ruralMins / provMins >= 1.3` 조건)

---

## 단계별 요약표

| Step | 파일 | 작업 | 위험 | 마스터 확인 | 폰 확인 |
|---|---|---|---|---|---|
| 0-A | - | curl로 class_factors 검증 | - | **필수** | - |
| 0-B | - | alternates 파라미터 검증 | - | **필수** | - |
| 1-A | routing_service.dart | dev.log 강화 | 없음 | 불필요 | Logcat 비교 |
| **2-A** | routing_service.dart | top_speed + class_factors 강화 | 낮음 | 불필요 | 시골길 geometry 변화 |
| 2-B | routing_service.dart | 국도 FC 극단화 | 낮음 | 불필요 | 국도 직선화 |
| 2-C | native/src/main.rs | Rust 서버 동기화 | 없음 | 불필요 | - |
| 3-A | routing_service.dart | alternates 추가 | 중간 | **필수** | 후보 경로 풍부화 |
| 3-B | routing_service.dart + main.rs | fun_score 재랭킹 | 중간 | **필수** | 3코스 완전 차별화 |
| 4-A | 인프라 | 숲 인덱스 구축 | 높음 | **필수** | - |
| 4-B | native/src/main.rs | fun_score_v4 활성화 | 높음 | **필수** | 숲 경로 선호 |

---

## 마스터 확인 필수 단계 모음

1. **Step 0-A**: `class_factors`의 motorcycle costing 적용 여부 — 전략 전체가 여기에 달림
2. **Step 0-B**: Valhalla `alternates` 파라미터 지원 여부 — Phase 3 전제 조건
3. **Step 3-A**: alternates 추가 — API 파싱 구조 변경이므로 설계 검토 필요
4. **Step 3-B**: 재랭킹 로직 — 시골길/지방도로/국도의 "재미" 정의를 마스터가 결정해야 함
5. **Step 4-A/4-B**: 숲 데이터 인프라 — 서버 용량, 처리 시간 검토 필요

---

## 6. 긴급 버그 수정 — 코스 차별화와 별개 (마스터 재량)

NavScreen 재탐색 버그 (nav_screen.dart L311):

현재 코드:
```dart
if (mounted && routes.isNotEmpty)
  setState(() => _routePoints = routes[0].points);  // 항상 시골길!
```

수정 (2파일):
```dart
// nav_screen.dart: selectedRouteIdx 파라미터 추가
class NavScreen extends ConsumerStatefulWidget {
  final int selectedRouteIdx; // 추가
  // ...

// _reroute에서:
if (mounted && routes.isNotEmpty)
  setState(() => _routePoints = routes[widget.selectedRouteIdx.clamp(0, routes.length-1)].points);
```

```dart
// main_map_screen.dart: NavScreen 호출부에 selectedRouteIdx 전달
NavScreen(
  routePolyline: ...,
  maneuvers: ...,
  selectedRouteIdx: ref.read(mapInteractionProvider).selectedRouteIdx, // 추가
)
```

이 버그는 코스 차별화 구현보다 쉽고 즉각적 효과가 있다. Phase 1 이전에 수정 권장.

---

## 7. Valhalla alternates 파라미터 응답 구조 예시

(문서에서 확인 — Valhalla API Reference)

```json
{
  "trip": {
    "legs": [...],
    "summary": {"length": 45.3, "time": 3600}
  },
  "alternates": [
    {
      "trip": {
        "legs": [...],
        "summary": {"length": 52.1, "time": 4200}
      }
    },
    {
      "trip": {
        "legs": [...],
        "summary": {"length": 61.8, "time": 5100}
      }
    }
  ]
}
```

파싱 코드 수정 포인트 (routing_service.dart L275-317):
```dart
// 기존: data['trip']만 파싱
// 추가: data['alternates']도 파싱
final alternates = (data['alternates'] as List?) ?? [];
for (final alt in alternates) {
  final altTrip = alt['trip'] as Map<String, dynamic>?;
  if (altTrip != null) {
    // 동일한 파싱 로직으로 RouteResult 생성
  }
}
```

---

*작성: 2026-06-05 (분석 Round 1 + 심화)*
