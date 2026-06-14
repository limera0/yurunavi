# 03 — fun-road costing 설계안: 경계 분석과 구현 옵션

> **목적**: Valhalla costing 노브만으로 가능한 차별화의 한계를 명확히 하고,  
> Rust fun-road 레이어가 필요한 지점을 정확히 지목한다.

---

## 1. Valhalla 노브만으로 가능한 차별화 범위

### 1.1 현재 상태에서 즉시 개선 가능한 것

다음 파라미터 조합은 Valhalla만으로 실제 다른 경로 geometry를 유도할 수 있다 (추정, 실측 검증 필요):

**(A) `top_speed` 차등 적용**
```
시골길: top_speed: 30   (현재 40 → 더 낮게)
지방도로: top_speed: 60  (현재 없음 → 추가)
국도: top_speed: 110    (현재 없음 → 추가)
```
효과: 시골길 코스에서 60km/h 이상 가능한 간선도로의 비용이 크게 상승 → 저속 소도로 선호 강화.

**(B) `class_factors` 극단값 강화**
- 시골길: FC5(소로/생활도로) 계수를 0.1로 낮춤, FC2(국도) 10.0으로 높임
- 국도: FC2 계수를 0.2로, FC5는 50.0으로

**(C) `shortest: false` + 거리 패딩**
- 현재 국도에만 `shortest: true` 적용
- 나머지 코스는 시간 기반이므로 이미 올바름

### 1.2 Valhalla 노브의 근본 한계

**한계 1: 곡률 선호 불가**
Valhalla는 "구불구불한 경로를 선호"하는 파라미터를 제공하지 않는다. 최단 시간/거리 최적화는 항상 직선 경로를 선호한다.

**한계 2: 숲 근접도 불가**
`landuse=forest`/`natural=wood` 폴리곤과 경로의 공간 교차를 Valhalla 내부에서 계산할 수 없다.

**한계 3: OSM 데이터 밀도 의존**
한국의 시골 지역 소로/임도 데이터가 OSM에 충분히 존재해야 대안 경로가 생성된다.

**한계 4: "재미"의 정의 부재**
Valhalla의 비용 모델은 이동 효율성(시간/거리)만 최적화한다. "오토바이로 달리기 즐거운 길"이라는 개념 자체가 Valhalla의 설계 범위 밖이다.

---

## 2. 구현 옵션 상세 분석

### 옵션 A: costing 자체를 다르게

**개념**: 시골길 = `bicycle` costing (또는 `motor_scooter`), 국도 = `auto`/`motorcycle`

```dart
// 시골길
'costing': 'motor_scooter'   // or 'bicycle'
// 지방도로
'costing': 'motorcycle'
// 국도
'costing': 'auto'
```

**가능성**:
- `bicycle`은 `use_hills`, `avoid_bad_surfaces`, `use_roads` 등 훨씬 더 세밀한 도로 선택 파라미터를 가짐
- `bicycle`의 `use_roads: 0.1`로 설정하면 차도 회피 + 비포장/소로 강한 선호
- `motor_scooter`는 `motorcycle`보다 소로 친화적

**부작용**:
- `bicycle` 라우팅은 오토바이가 달릴 수 없는 도로(자전거 전용도로)를 포함할 수 있음
- 속도 기준이 달라 ETA 계산 복잡
- 한국 OSM에서 bicycle network가 충분히 구축되지 않은 지역에서 비현실적 경로 출력 가능
- **회귀 위험 높음**: 전혀 다른 경로망을 사용하므로 예측 불가능

**구현 난이도**: 낮음 (costing 문자열 변경만)  
**결과 예측 가능성**: 낮음  
**권장**: 테스트 전용, 프로덕션 투입 전 실측 검증 필수

---

### 옵션 B: costing_options 극단 조정

**개념**: 현재 `motorcycle` costing을 유지하면서 파라미터를 더 극단적으로 설정

**개선 제안**:

시골길 강화안:
```json
{
  "costing": "motorcycle",
  "costing_options": {
    "motorcycle": {
      "use_highways": 0.0,
      "use_ferry": 0.0,
      "use_living_streets": 1.0,
      "use_tracks": 1.0,           // 0.8 → 1.0
      "top_speed": 30,             // 40 → 30
      "urban_penalty": 100.0,      // 50 → 100
      "class_factors": {
        "1": 1000.0,               // 사실상 차단
        "2": 50.0,                 // 강한 회피
        "3": 5.0,                  // 회피
        "4": 0.5,                  // 선호
        "5": 0.05                  // 강한 선호
      }
    }
  }
}
```

국도 강화안:
```json
{
  "costing": "motorcycle",
  "costing_options": {
    "motorcycle": {
      "use_highways": 0.0,
      "use_ferry": 0.0,
      "use_living_streets": 0.0,
      "use_tracks": 0.0,
      "shortest": true,
      "class_factors": {
        "1": 1000.0,
        "2": 0.1,                  // 강한 선호
        "3": 0.5,
        "4": 10.0,                 // 회피
        "5": 100.0                 // 강한 회피
      }
    }
  }
}
```

**가능성**:
- 현재 동일한 geometry의 주 원인이 `class_factors`가 motorcycle costing에 적용되지 않는 것이라면, 이 옵션 자체가 효과 없을 수 있음 (Q1)
- `class_factors`가 적용된다면 FC2(국도) 극단 회피 + FC5(소로) 강한 선호로 실질적 다른 경로 가능

**가능성 시나리오 분기**:
1. `class_factors` 적용됨 → 옵션B로 3코스 분기 가능성 높음 (검증 필요)
2. `class_factors` 적용 안 됨 → 옵션B는 효과 없음 → 옵션D/E 필수

**구현 난이도**: 낮음 (파라미터 값 변경만)  
**회귀 위험**: 중간 (현재보다 극단적이라 예상치 못한 우회 발생 가능)

---

### 옵션 C: exclude_polygons / avoid 로 도로 등급 회피

**개념**: Valhalla의 `exclude_polygons`로 특정 도로 유형의 밀집 구간을 차단

**시나리오**:
- 고속도로 인근 지역 폴리곤을 동적으로 생성하여 시골길 코스에서 제외
- 또는, 국도 구간을 지오매트리로 추출하여 시골길 요청 시 avoid_edges로 전달

**한계**:
- `exclude_polygons`는 지역을 차단하는 것이지 도로 "등급"을 차단하는 것이 아님
- 도로 등급별 차단은 `class_factors`가 더 직접적
- 폴리곤을 동적으로 생성하려면 OD 분석 + 지오처리가 필요 → 복잡도 급등

**구현 난이도**: 높음 (동적 폴리곤 생성 로직 필요)  
**회귀 위험**: 높음  
**권장**: 보조적 수단으로 사용, 주 수단 아님

---

### 옵션 D: Rust fun-road 스코어링 — 후처리/재랭킹

**개념**: Valhalla에 여러 후보 경로를 요청하고, Rust에서 fun_score 기준으로 재정렬하여 코스별 "가장 재미있는 경로"를 반환

**현재 인프라**:
- `fun_score_v2`: τ 60% + FC 40% (api.rs L241-245) ← 이미 구현됨
- `fun_score_v3`: τ 50% + FC 30% + 속도 20% (api.rs L279-284) ← 이미 구현됨
- `fun_score_v4`: τ 40% + FC 25% + 속도 15% + 숲 20% (api.rs L329-340) ← 구현됨, 숲 데이터 미연결
- `rank_candidates_v2()`: (경로, FC) 쌍을 받아 fun_score 기준 정렬 ← 이미 구현됨

**후처리 방식의 작동 원리**:

현재:
```
1개 OD → 3 costing 요청 → 3 geometry → UI 표시
```

제안 (D1: Valhalla alternative routes + re-ranking):
```
1개 OD → 1 costing + alternatives 요청 → N개 geometry
        → Rust fun_score 계산 → fun score 기준 상위 3개 선택
        → 시골길 = 1위, 지방도 = 2위, 국도 = 3위 매핑
        → UI 표시
```

Valhalla는 `"alternates": N` 파라미터로 대안 경로를 반환한다:
```json
{
  "locations": [...],
  "costing": "motorcycle",
  "alternates": 3
}
```

**제안 (D2: 현재 구조 유지 + 표시 로직 개선)**:
```
현재처럼 3 costing으로 요청 → 3 geometry
→ 각 geometry의 fun_score_v2 계산 (이미 됨)
→ 3카드에 fun_score 점수 표시 (이미 됨)
→ 사용자가 직접 "가장 재미있는 경로"를 선택
```

→ D2는 이미 구현되어 있고, 단지 costing이 실제로 다른 경로를 만들지 못하는 것이 문제.

**구현 난이도**: 중간 (기존 fun_score 인프라 활용)  
**회귀 위험**: 낮음 (기존 요청 구조에 후처리만 추가)  
**권장**: 핵심 전략으로 채택 가능

---

### 옵션 E: 조합 전략 (권장)

**최적 조합**: B (costing_options 강화) + D1 (Valhalla alternates + re-ranking)

단계 1 (즉각 효과 기대, 낮은 리스크):
- `class_factors`의 motorcycle 적용 여부를 먼저 검증
- 검증 방법: 같은 OD에서 `class_factors: {"2": 0.1}` vs `class_factors: {"2": 10.0}`의 경로 비교

단계 2 (중기, 구조 개선):
- Valhalla `alternates` 파라미터로 여러 후보 경로 요청
- Rust `rank_candidates_v2()`로 fun_score 기준 정렬
- 시골길 = 가장 높은 fun_score 경로, 국도 = 가장 낮은 fun_score 경로

단계 3 (장기, 숲 데이터 연동):
- OSM 숲 폴리곤 전처리 인덱스 구축
- `fun_score_v4` 활성화 (forest_proximity 계산)

---

## 3. OSM 데이터 관점 분석: 곡률, 숲, 도로 등급 계산

### 3.1 도로 등급 (OSM highway=*)

**[OSM 데이터에서 확인 가능]**

```
highway=motorway         → FC1 고속국도
highway=trunk            → FC2 일반국도 (1호선 등)
highway=primary          → FC3 지방도
highway=secondary        → FC4 군도/면도
highway=tertiary         → FC5 소로
highway=unclassified     → FC5
highway=residential      → FC5 생활도로
highway=track            → FC5 농도/임도
highway=service          → FC5 서비스도로
```

현재 코드의 `road_class_to_fc()` (main.rs L92-99):
```rust
"motorway"  => 1.0,
"trunk"     => 2.0,
"primary"   => 3.0,
"secondary" => 4.0,
_ => 5.0,  // tertiary, unclassified, residential, service_other
```

→ Valhalla trace_attributes의 `road_class` 필드에서 직접 취득 가능.

### 3.2 곡률(curviness) 계산

**방법 1: τ (Tortuosity) — 현재 구현됨** (api.rs L185-195)
```
τ = 경로 전체 길이(Σ haversine 구간) / 출발~도착 직선 거리
```
- 단순하고 빠름
- 경유지가 많으면 직선거리가 달라질 수 있음
- 반환: 1.0 (직선) ~ 무한대 (이론상)

**방법 2: 방위각 변화율 — 현재 구현됨** (api.rs L111-165)
```
winding_score = Σ |bearing(p[i-1]→p[i]) - bearing(p[i]→p[i+1])| / (total_km)
```
단위: 도/km. 높을수록 꼬불꼬불.

**방법 3: Valhalla heading_curvature — 현재 구현됨** (api.rs L287-296)
```
avg = Σ |edge.end_heading - edge.begin_heading| / edge_count
```
엣지 단위 커브 밀도. 0도/엣지 = 직선, 90도/엣지 = 급커브 연속.

**방법 4: 구간별 최대 곡률 (미구현)**
- 각 구간의 최대 방위각 변화로 "코너 밀도" 계산
- 다리/터널 구간 필터링 필요

**OSM 태그에서 직접 취득 가능한 관련 정보**:
- `highway=track` → 농도/임도 (자연적으로 구불구불함)
- `highway=unclassified` + 좌표 패턴 → 소로 곡률 추정
- Valhalla 엣지 `geometry` 필드에서 노드 간 각도 계산 가능

### 3.3 숲 근접도 계산

**방법 1: 경로 버퍼와 숲 폴리곤 교차 (권장)**
```python
# 전처리 단계 (오프라인)
osm_forests = load_polygons("landuse=forest OR natural=wood")
forest_index = RTree(osm_forests)

# 런타임 단계
route_buffer = buffer(route_polyline, radius=200m)
forest_coverage = intersection_area(route_buffer, forest_index) / buffer_area
# 0.0 (숲 없음) ~ 1.0 (전체 경로가 숲 속)
```

**방법 2: 경로 포인트별 최근 숲까지 거리 평균**
```python
for point in route:
    nearest_forest = forest_index.nearest(point)
    dist = geodesic(point, nearest_forest)
forest_proximity = clamp(1 - avg_dist / 500m, 0, 1)
```

**OSM 데이터 가용성**: 한국 OSM에서 `landuse=forest`, `natural=wood` 폴리곤은 비교적 잘 등록되어 있음 (추정 — 실제 확인 필요).

**자가호스팅 제약**:
- PostGIS + ST_Buffer + ST_Intersection: 런타임 계산 가능하나 느림
- 전처리된 래스터 타일(숲 밀도 격자): 빠름, 구축 공수 필요
- korea.mbtiles에 숲 데이터 포함 여부: OpenMapTiles 스키마는 landuse 레이어 포함 (확인 필요)

### 3.4 해발고도/경사도

**OSM 데이터 가용성**:
- OSM에는 도로 높이 데이터가 있는 경우도 있지만 한국에서는 불완전
- SRTM(Shuttle Radar Topography Mission) 오픈 데이터로 보완 가능
- Valhalla는 SRTM 통합을 지원하나, 자가호스팅 환경에서 별도 데이터 처리 필요

---

## 4. "Valhalla 노브 vs Rust fun-road" 경계 정의

```
┌──────────────────────────────────────────────────────────────┐
│                 Valhalla costing 노브로 가능                  │
├──────────────────────────────────────────────────────────────┤
│ ✓ 고속도로 배제 (use_highways=0)                             │
│ ✓ 도로 등급 선호/회피 (class_factors, 검증 필요)             │
│ ✓ 비포장 트랙 선호/회피 (use_tracks)                         │
│ ✓ 생활도로 선호/회피 (use_living_streets)                    │
│ ✓ 도시 지역 회피 (urban_penalty)                             │
│ ✓ 속도 제한으로 간선도로 간접 회피 (top_speed)               │
│ ✓ 거리 최단 경로 (shortest=true)                             │
└──────────────────────────────────────────────────────────────┘
           │
           │ 이 경계를 넘으면 Valhalla 불가
           ▼
┌──────────────────────────────────────────────────────────────┐
│              Rust fun-road 레이어가 필요한 것                  │
├──────────────────────────────────────────────────────────────┤
│ ✗ 곡률 최대화 (가장 구불구불한 경로 선택)                    │
│ ✗ 숲 근접도 기반 경로 선택                                   │
│ ✗ 여러 후보 중 "재미" 기준 재랭킹                            │
│ ✗ 경사도/산악성 기반 선호                                    │
│ ✗ 실시간 교통량 회피                                         │
└──────────────────────────────────────────────────────────────┘
```

---

## 5. 권장 구현 전략 요약

**단기 (1-2 커밋, 낮은 위험)**:
1. `class_factors`의 motorcycle 적용 여부 검증 (외부 curl 테스트 또는 로그 분석)
2. `top_speed` 코스별 차등 강화 (시골길 30, 지방도로 없음, 국도 없음)
3. `class_factors` 극단값 강화 (FC2: 50→시골길, FC5: 0.05→시골길)

**중기 (3-5 커밋, 중간 위험)**:
1. Valhalla `alternates: 2` 파라미터로 대안 경로 요청
2. Rust `rank_candidates_v2()`로 fun_score 기준 재정렬
3. 시골길 = 가장 높은 fun_score, 국도 = 가장 낮은 fun_score 매핑

**장기 (5+ 커밋, 구조 변경)**:
1. OSM 숲 폴리곤 전처리 인덱스 구축
2. `fun_score_v4` 활성화 (forest_proximity 연결)
3. 경사도 데이터 연동

---

## 3B. fun_score 인프라 현황 — 이미 구현된 것과 미연결된 것

(코드에서 확인 — native/src/api.rs + native/src/main.rs)

| 함수 | 구현 | main.rs 사용 | Flutter 사용 | 비고 |
|---|---|---|---|---|
| `fun_score_v1` | ✅ api.rs L201 | ❌ | ❌ | τ 전용, 내부 유틸 |
| `fun_score_v2` | ✅ api.rs L241 | ✅ /score_route | ✅ scoreFunV2() | **현재 UI 표시 기준** |
| `fun_score_v3` | ✅ api.rs L279 | ✅ /score_route | ❌ | 계산되지만 Flutter에 미전달 |
| `fun_score_v4` | ✅ api.rs L329 | ❌ | ❌ | forest_proximity=0 고정 |
| `rank_candidates` | ✅ api.rs L210 | ❌ | ❌ | v1 기반, 미연결 |
| `rank_candidates_v2` | ✅ api.rs L249 | ❌ | ❌ | v2 기반, **즉시 활용 가능** |
| `road_class_score_v2` | ✅ api.rs L303 | ❌ | ❌ | 비선형 FC 점수 |
| `heading_curvature` | ✅ api.rs L290 | ❌ | ❌ | trace_attributes begin/end_heading 미취득 |
| `forest_score` | ✅ api.rs L322 | ❌ | ❌ | 숲 인덱스 연결 필요 |
| `traffic_score` | ✅ api.rs L271 | 간접(v3내) | ❌ | avg_speed는 이미 취득됨 |

**핵심 발견**: `fun_score_v3`는 Rust 서버에서 이미 계산되어 `/score_route` 응답에 포함되지만, Flutter `NativeEngine.scoreFunV2()`는 `fun_score_v2`만 받고 `fun_score_v3`를 버린다 (native_engine.dart L250-254).

**즉시 가능한 개선**: `FunScoreResult`에 `funScoreV3` 필드 추가 → UI에서 v3 기반 뱃지 표시 가능 (단 코드 수정, 본 분석에서 실행 금지).

**`rank_candidates_v2` 즉시 활용 가능**: 이 함수는 `(Vec<GpsPoint>, avg_fc)` 쌍 리스트를 입력으로 받아 fun_score_v2 기준으로 정렬한다. Phase 3-B 구현 시 핵심 빌딩 블록으로 바로 사용 가능.

---

## 4. 의사코드: Alternates + 재랭킹 파이프라인 (권장 경로)

```
/// Phase 3-B 구현 의사코드

// Step 1: Valhalla alternates 요청 (routing_service.dart)
Future<List<RouteResult>> _fetchWithAlternates(
  List<Map<String, dynamic>> locations,
) async {
  // 시골길 costing + alternates 2개 = 최대 3 후보 경로
  final ruralResp = await valhalla.post({
    'locations': locations,
    'costing': 'motorcycle',
    'costing_options': {'motorcycle': _ruralOpts},
    'alternates': 2,
  });
  
  // 국도 costing은 alternates 없이 단일 요청 (이미 다른 네트워크)
  final nationalResp = await valhalla.post({
    'locations': locations,
    'costing': 'motorcycle',
    'costing_options': {'motorcycle': _nationalOpts},
  });

  // 응답 파싱: trip + alternates[0..1]
  final candidates = [
    parse(ruralResp['trip']),           // 후보 0
    parse(ruralResp['alternates'][0]),  // 후보 1 (있으면)
    parse(ruralResp['alternates'][1]),  // 후보 2 (있으면)
    parse(nationalResp['trip']),        // 후보 3 (국도 기준)
  ];
  
  return candidates.where((r) => r.points.isNotEmpty).toList();
}

// Step 2: fun_score 계산 후 재랭킹 (native_engine.dart)
Future<List<RouteResult>> rankByCourseType(
  List<RouteResult> candidates,
) async {
  // 각 후보의 fun_score_v2 계산
  final scores = await Future.wait(
    candidates.map((c) => NativeEngine.scoreFunV2(c.points)),
  );
  
  // 점수 기준 정렬
  final indexed = List.generate(candidates.length, (i) => (
    route: candidates[i],
    score: scores[i].funScoreV2,
  ));
  indexed.sort((a, b) => b.score.compareTo(a.score));
  
  // 코스 매핑
  return [
    indexed.first.route,                       // 시골길: 최고 fun_score
    indexed[indexed.length ~/ 2].route,        // 지방도로: 중간
    indexed.last.route,                        // 국도: 최저 fun_score
  ];
}
```

---

## 4B. fun_score_v3 활성화 — 즉시 가능한 작은 개선

(코드에서 확인 — native_engine.dart L233-265, native/src/main.rs L192-197)

현재 `/score_route` 응답:
```json
{
  "fun_score_v2": 35.2,
  "fun_score_v3": 38.5,  ← 이미 계산되지만 Flutter가 사용 안 함!
  "avg_fc": 3.8,
  "avg_speed_kmh": 42.3,
  "curvature_tau": 1.45
}
```

Flutter `FunScoreResult` (native_engine.dart L51-58):
```dart
class FunScoreResult {
  final double funScoreV2;
  final double avgFc;
  final double curvatureTau;
  // funScoreV3 없음! avg_speed_kmh 없음!
}
```

**2파일 수정으로 fun_score_v3 UI 표시 가능**:
1. `native_engine.dart`: `FunScoreResult`에 `funScoreV3`, `avgSpeedKmh` 필드 추가
2. `main_map_screen.dart`: `windingScore`에 `funScoreV3` 사용 (현재 v2)

이 변경은 경로 자체를 바꾸지 않고 표시 지표만 개선 — 회귀 위험 매우 낮음.

---

## 5. OSM 곡률 계산 예시: 실제 수치로 이해하기

### 5.1 방위각 변화율 계산 예시

경로 A (직선 국도, 서울 → 수원):
```
포인트: (37.566, 127.0), (37.45, 127.05), (37.32, 127.1)
구간1 bearing: atan2(sin(0.05°)*cos(37.45°), cos(37.566°)*sin(37.45°) - sin(37.566°)*cos(37.45°)*cos(0.05°))
             ≈ 180.5° (남쪽)
구간2 bearing ≈ 181.2° (거의 동일)
방위각 변화: 0.7° / 25km ≈ 0.028 도/km
winding_score ≈ 0.028 / 200 × 100 ≈ 0.01점 (거의 직선)
```

경로 B (지방도 + 산악 구간, 가평 → 양평):
```
포인트 예시 (100개 이상):
구간별 방위각 변화 합 ≈ 1800°
총 거리 ≈ 30km
방위각 변화율 = 1800 / 30 = 60 도/km
winding_score = min(60/200, 1.0) × 100 = 30점 (provincial 분류)
```

경로 C (강원 31번 국도 산악 구간):
```
구간별 방위각 변화 합 ≈ 3200°
총 거리 ≈ 20km
방위각 변화율 = 3200 / 20 = 160 도/km
winding_score = min(160/200, 1.0) × 100 = 80점 (country 분류)
```

### 5.2 Tortuosity τ 계산 예시

```
경로 A (직선): path_length=100km, straight=98km → τ = 100/98 ≈ 1.02
경로 B (보통): path_length=35km, straight=25km → τ = 35/25 = 1.40
경로 C (극심): path_length=25km, straight=12km → τ = 25/12 ≈ 2.08

fun_score_v1:
A: (1.02-1.0)×50 = 1.0점
B: (1.40-1.0)×50 = 20.0점
C: min((2.08-1.0)×50, 100) = 54.0점
```

### 5.3 fun_score_v2 계산 예시 (현재 구현)

서울-부산 3코스 가상 시나리오 (추정 수치):

| 코스 | path_km | straight_km | τ | avg_fc | tau_score | fc_score | fun_v2 |
|---|---|---|---|---|---|---|---|
| 시골길 | 580 | 320 | 1.81 | 4.2 | 40.5 | 80.0 | 56.3 |
| 지방도로 | 510 | 320 | 1.59 | 3.5 | 29.5 | 62.5 | 42.7 |
| 국도 | 420 | 320 | 1.31 | 2.8 | 15.5 | 45.0 | 27.3 |

→ 시골길 fun_v2 56.3 > 지방도로 42.7 > 국도 27.3 (올바른 순서)

**문제**: 현재는 geometry가 같아서 위 표가 실제로는:

| 코스 | path_km | τ | avg_fc | fun_v2 |
|---|---|---|---|---|
| 시골길 | 400 (같음) | 1.25 | 2.9 | 23.8 |
| 지방도로 | 400 (같음) | 1.25 | 2.9 | 23.8 |
| 국도 | 400 (같음) | 1.25 | 2.9 | 23.8 |

→ 세 코스 모두 같은 fun_score → 차별화 없음.

---

*작성: 2026-06-05 (분석 Round 1 + 심화)*
