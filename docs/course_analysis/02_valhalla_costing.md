# 02 — Valhalla Costing 전수 조사

> **코드에서 확인** / **문서에서 확인** / **추정** 구분 표기.
> 참조: https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/

---

## 1. Valhalla costing 모델 전체 목록

(문서에서 확인 — Valhalla API Reference, 2024 기준)

| costing | 설명 | 주요 특징 |
|---|---|---|
| `auto` | 일반 자동차 | 기본 모델, 가장 완성도 높음 |
| `auto_shorter` | 거리 최단 자동차 | `auto` + shortest=true 유사 |
| `bus` | 버스 | 버스 전용 도로 포함 |
| `truck` | 트럭 | 높이/중량 제한 준수 |
| `bicycle` | 자전거 | 자전거 전용 도로, 경사도 반영 |
| `motorcycle` | 오토바이 | `auto` 파생. 비포장도로 일부 허용 |
| `motor_scooter` | 스쿠터 | 저속, 소로 선호 |
| `pedestrian` | 도보 | 보행로, 계단 포함 |
| `multimodal` | 대중교통 복합 | 버스+지하철 연결 |

**유루나비 사용**: `motorcycle` — 전 코스 동일 (코드에서 확인, routing_service.dart L240).

### motorcycle vs auto 차이점 (문서에서 확인 + 추정)

- motorcycle은 `auto`에서 파생된 구현
- 기본적으로 고속도로(motorway) 이용 가능 (단, `use_highways: 0.0`으로 강제 배제)
- `surface` 태그 기반 비포장 허용 범위가 `auto`보다 약간 넓음
- `use_trails` 파라미터 지원 여부 불명확 (추정)

---

## 2. 경로 선택에 영향을 주는 costing_options 파라미터 전수 정리

### 2.1 공통 파라미터 (auto, motorcycle 모두 적용)

(문서에서 확인 — Valhalla API Reference)

| 파라미터 | 범위 | 기본값 | 경로 변화 | 설명 |
|---|---|---|---|---|
| `maneuver_penalty` | 0-43200 | 5 | 경로 | 회전 페널티 (초). 높일수록 직선 경로 선호 |
| `gate_cost` | 0-43200 | 30 | 경로 | 게이트/차단기 통과 비용 |
| `gate_penalty` | 0-43200 | 300 | 경로 | 게이트 회피 페널티 |
| `private_access_penalty` | 0-43200 | 450 | 경로 | 사유지 진입 페널티 |
| `country_crossing_cost` | 0-43200 | 600 | 경로 | 국경 통과 비용 |
| `country_crossing_penalty` | 0-43200 | 0 | 경로 | 국경 회피 페널티 |
| `shortest` | bool | false | **경로 형태** | true = 거리 최단 (시간 무시) |
| `use_highways` | 0.0-1.0 | 1.0 | **경로 형태** | 고속도로 선호도. 0=강한 회피 |
| `use_tolls` | 0.0-1.0 | 0.5 | 경로 | 유료도로 선호도 |
| `use_ferry` | 0.0-1.0 | 0.5 | 경로 | 페리 선호도 |
| `use_living_streets` | 0.0-1.0 | 0.5 | **경로 형태** | 생활도로 선호도 |
| `use_tracks` | 0.0-1.0 | 0.0 (auto) | **경로 형태** | 비포장 트랙 선호도 |
| `top_speed` | 10-252 (km/h) | 140 | **경로 형태** | 최대 주행속도 제한. 낮추면 고속도로 비용 증가 |
| `service_penalty` | 0-43200 | 15 | 경로 | 서비스 도로(주차장 등) 페널티 |
| `service_factor` | 0.0-1.0 | 1.0 | 경로 | 서비스 도로 비용 계수 |
| `ignore_closures` | bool | false | 경로 | 도로 폐쇄 무시 여부 |
| `urban_penalty` | 0-43200 | 0 | **경로 형태** | 도시 도로 페널티 |
| `class_factors` | map | {} | **경로 형태** | 도로 등급별 비용 계수 (아래 상세) |

### 2.2 bicycle 전용 파라미터

(문서에서 확인)

| 파라미터 | 범위 | 기본값 | 경로 변화 | 설명 |
|---|---|---|---|---|
| `use_roads` | 0.0-1.0 | 0.5 | **경로 형태** | 일반 차도 사용 선호도. 낮으면 자전거 전용도로/소로 선호 |
| `use_hills` | 0.0-1.0 | 0.5 | **경로 형태** | 경사도 허용 수준. 0=평지 선호 |
| `avoid_bad_surfaces` | 0.0-1.0 | 0.25 | **경로 형태** | 비포장/열악한 도로 회피 |
| `bicycle_type` | str | Road | 경로 | Road/Hybrid/City/Mountain |

### 2.3 class_factors 상세

(문서에서 확인 + 추정)

```json
"class_factors": {
  "1": 100.0,   // FC1: motorway (고속국도)
  "2": 5.0,     // FC2: trunk (국도/일반국도)
  "3": 2.5,     // FC3: primary (지방도)
  "4": 1.0,     // FC4: secondary (군도)
  "5": 0.2      // FC5: tertiary/residential (소로/생활도로)
}
```

- 기본값(=1.0)은 해당 도로 등급을 "중립"으로 취급
- **1.0보다 크면**: 해당 도로를 사용할 때 비용이 높아짐 → 회피
- **1.0보다 작으면**: 해당 도로를 사용할 때 비용이 낮아짐 → 선호
- 100.0 = 사실상 해당 등급 도로 완전 차단 (비용이 100배 → 우회 강제)

**[추정]** `class_factors`가 `motorcycle` costing에서 실제로 적용되는지 Valhalla 소스코드 레벨에서 확인 필요. 공식 API 문서에서 motorcycle 전용 항목으로 명시하지 않음.

### 2.4 "속도만 바꾸나 vs 경로를 바꾸나" 핵심 분류표

| 파라미터 | 속도/ETA | 경로 geometry | 비고 |
|---|---|---|---|
| `shortest=true` | 예 | **예** | 거리 기반으로 완전 전환 |
| `use_highways=0.0` | 예 | **예** | 고속도로 제거 → 다른 경로 |
| `use_living_streets=1.0` | 약간 | **약간** | 대안 생활도로 있을 때만 |
| `use_tracks=0.8` | 약간 | **약간** | 비포장 대안 있을 때만 |
| `top_speed=40` | 예 | **간접적** | 고속도로 비용 상승 → 우회 유도 가능 |
| `urban_penalty=50` | 예 | **예** | 도시 도로를 상당히 회피 |
| `class_factors` | 예 | **예(추정)** | 등급별 비용 계수 조정 |
| `maneuver_penalty` | 예 | 약간 | 회전 페널티 → 직선 선호 |
| `service_factor` | 약간 | 약간 | 주차장 등 서비스 도로 |
| `top_speed` (ETA only) | **예** | 아니오 | 경로 변화 없이 ETA만 변경 |

---

## 3. 곡선 많은 길 / 숲길 / 저교통 도로를 선호할 수 있는 파라미터

### 3.1 Valhalla에서 가능한 것

**(1) `use_tracks: 0.8~1.0`** (문서에서 확인)
- 비포장 트랙(highway=track) 선호 강화
- 시골 오솔길/임도를 포함한 경로 유도 가능
- **한계**: track 데이터가 OSM에 충분히 있어야 효과 있음

**(2) `top_speed: 40`** (문서에서 확인)
- 상한 속도 40km/h 설정 → 60km/h 이상 가능한 도로의 비용이 상승
- 직접 결과: 간선도로(FC2-3) 이용 시 비용 계산에서 불리해짐
- 간접 결과: 저속 도로(생활도로, 소로)가 상대적으로 유리해짐

**(3) `urban_penalty: 50`** (문서에서 확인)
- 도시 지역 도로 페널티 → 도시 우회 유도
- 시골길 진입을 강제하는 효과는 제한적

**(4) `class_factors`로 FC2-3 회피, FC4-5 선호**
- FC4(secondary/군도), FC5(tertiary/residential) 비용을 낮추면 해당 도로망 선호
- FC2(trunk/일반국도)를 높이면 국도 우회 강제
- **[추정]** motorcycle costing 적용 여부 확인 필요

### 3.2 Valhalla에서 불가능한 것 (설계적 부재)

**(1) 곡률(curviness) 선호** — 없음
- Valhalla에는 "굽이진 도로를 선호"하는 파라미터가 없다 (문서에서 확인)
- 최적화 기준이 항상 "비용 최소화"이기 때문에, 구조적으로 직선이 곡선보다 유리함
- OsmAnd의 "스릴 넘치는 경로" 같은 curviness 파라미터가 Valhalla에는 없음

**(2) 숲 근접도** — 없음
- Valhalla costing에 `landuse=forest` 근처를 선호하는 파라미터 없음
- OSM의 숲 폴리곤과 경로의 공간적 관계는 Valhalla 내부에서 계산하지 않음

**(3) 교통량 기반 선호** — 제한적
- `top_speed`를 도로 제한속도의 대리지표로 사용 가능 (낮은 속도 = 한적한 도로)
- 실시간 교통 데이터는 Valhalla 기본 구성에서 지원 않음

**(4) 해발 고도/산악성** — 없음
- 자전거 costing의 `use_hills`가 유사하나, motorcycle costing에는 없음

---

## 4. 경로 형태에 영향 주는 고급 파라미터

### 4.1 exclude_polygons (문서에서 확인)

```json
{
  "locations": [...],
  "costing": "motorcycle",
  "exclude_polygons": [
    [{"lat": 37.0, "lon": 127.0}, {"lat": 37.1, "lon": 127.0}, ...]
  ]
}
```

- 특정 지역(폴리곤 내부)의 도로를 완전 차단
- 예: 고속도로 IC 주변 폴리곤 → 고속도로 진입 차단
- **한계**: 폴리곤을 동적으로 생성해야 하며, 코스마다 다른 폴리곤 필요

### 4.2 avoid_locations (문서에서 확인)

```json
{
  "avoid_locations": [{"lat": 37.0, "lon": 127.0}]
}
```

- 특정 노드/위치 회피
- 교차로 등 특정 포인트 수준 제어

### 4.3 `heading` / `search_cutoff` (문서에서 확인)

- 출발/도착 방향 제약
- 경로 형태 자체보다는 시작/끝 처리에 영향

---

## 5. Valhalla Functional Class (FC) 매핑

(문서에서 확인 — Valhalla는 OSM highway=* 태그를 내부적으로 FC 등급으로 변환)

| FC | Valhalla road_class | OSM highway=* | 한국 도로 예시 |
|---|---|---|---|
| FC1 | motorway | motorway, motorway_link | 경부고속도로 |
| FC2 | trunk | trunk, primary | 국도 1호선 |
| FC3 | primary | secondary | 지방도 614호 |
| FC4 | secondary | tertiary | 군도, 면도 |
| FC5 | tertiary+ | unclassified, residential, service, track | 농도, 임도, 생활도로 |

**주의**: Valhalla의 `class_factors` 키("1"~"5")는 FC 등급이 아니라 내부 `RoadClass` enum에 대응. 정확한 매핑은 소스코드 확인 필요 (추정).

---

## 6. motorcycle costing 고유 특징 정리

(문서에서 확인 + 추정)

**확인된 사항**:
- `use_highways`: 지원 (고속도로 포함 여부)
- `use_ferry`: 지원
- `use_living_streets`: 지원 (생활도로)
- `use_tracks`: 지원 (비포장 트랙)
- `top_speed`: 지원
- `shortest`: 지원

**불확실한 사항** (추정):
- `class_factors`: auto에서는 명시되지만 motorcycle에서는 공식 문서에 언급 없음
- `use_hills`: bicycle에만 명시, motorcycle 지원 여부 불명
- `avoid_bad_surfaces`: auto 계열 일부에서 지원하나 motorcycle 명시 없음

---

## 7. trace_attributes로 경로 정보 취득 — 현황

(코드에서 확인 — native/src/main.rs L89-158)

Rust 서버의 `trace_attributes_fc()` 함수:
```
POST /trace_attributes
{
  "shape": [...],
  "costing": "motorcycle",
  "shape_match": "map_snap",
  "filters": {
    "attributes": ["edge.road_class", "edge.length", "edge.speed"],
    "action": "include"
  }
}
```

- `edge.road_class` → FC 등급 추출 → `avg_fc` 계산
- `edge.speed` → 제한속도 추출 → `avg_speed` 계산
- `edge.begin_heading` / `edge.end_heading` → `heading_curvature()` 계산 (api.rs L286-296)

이 데이터는 현재 **fun_score 계산에만 사용** (표시용). 라우팅 자체에는 피드백되지 않음.

---

## 8. 곡률 계산 — 현재 구현 vs 최적

### 8.1 현재 구현 (코드에서 확인, api.rs)

**`calc_winding_score`** (api.rs L135-165):
```
score = sum(bearing_change(p[i-1], p[i], p[i+1])) / (total_dist_m / 1000)
score_normalized = min(score / 200.0, 1.0) * 100
```
→ 방위각 변화량 / km = 도/km. 200도/km 상한.

**`calc_tortuosity`** (api.rs L185-195):
```
τ = path_length / straight_line_distance
```
→ 경로 구불구불함 비율. 1.0=직선, 높을수록 꼬불꼬불.

**`heading_curvature`** (api.rs L287-296):
```
avg_heading_change = sum(|end_heading - begin_heading| per edge) / edge_count
```
→ Valhalla trace_attributes의 엣지 헤딩 변화량 평균.

### 8.2 이 지표들이 경로 선택에 활용되지 않는 이유

현재 구조에서 곡률 계산은 항상 **경로가 결정된 이후**에 수행된다:
1. Valhalla → 경로 geometry 결정
2. geometry → `calc_tortuosity`, `calc_winding_score` 계산
3. 계산 결과 → UI 표시 (fun_score 뱃지)

즉, 곡률이 높은 경로를 "선택"하는 것이 아니라, 선택된 경로의 곡률을 "측정"하고 있다. 이 순서를 역전시켜야 한다.

---

## 8B. alternates 파라미터 — 경로 후보군 확장

(문서에서 확인 — Valhalla API Reference)

```json
{
  "locations": [...],
  "costing": "motorcycle",
  "costing_options": {"motorcycle": {...}},
  "alternates": 2
}
```

응답 구조:
```json
{
  "trip": {"legs": [...], "summary": {"length": 40.6, "time": 3000}},
  "alternates": [
    {"trip": {"legs": [...], "summary": {"length": 45.2, "time": 3600}}},
    {"trip": {"legs": [...], "summary": {"length": 52.1, "time": 4200}}}
  ]
}
```

- `"alternates": N`: 0 = 대안 없음 (현재 설정), 1~3 = 대안 N개 추가 요청
- 대안 경로는 메인 경로와 일정 이상 다른 geometry를 보장
- **`use_highways: 0.0`을 공통으로 적용하더라도 alternates는 생성됨** (추정)
- Valhalla 버전에 따라 지원 여부 다를 수 있음 (확인 필요)

**활용 전략**: 단일 "최적" costing으로 alternates 2-3개를 받아 Rust가 fun_score 기준으로 재정렬 → 시골길=가장 구불구불한 것, 국도=가장 직선인 것 매핑.

---

## 9. costing_options 실제 효과 시뮬레이션 — 의사코드 및 계산 예시

### 9.1 top_speed 효과 계산

Valhalla 내부 동작 (문서 기반 추정):

```
// edge.speed가 top_speed를 초과하면 비용 증가
edge_cost = edge_length / min(edge.speed, top_speed)
```

예시: 100km/h 국도 100km 구간
- top_speed 없음 (기본): cost = 100 / 100 = 1.0 시간단위
- top_speed = 40: cost = 100 / 40 = 2.5 시간단위 (2.5배 비싸짐)
- top_speed = 30: cost = 100 / 30 = 3.33 시간단위 (3.33배 비싸짐)

반면 30km/h 소도로 100km 구간:
- top_speed = 30: cost = 100 / 30 = 3.33 시간단위 (top_speed와 동일 → 페널티 없음)

**결론**: `top_speed: 30` 설정 시, 30km/h 이하 도로는 비용 중립, 60km/h 이상 도로는 2-3배 비용 상승 → 간선도로 자연 회피 강도가 현재보다 훨씬 강해짐.

### 9.2 class_factors 효과 계산

```
edge_cost *= class_factors[fc_class]
```

예시: 시골길 요청, FC2(국도) 100km 구간 vs FC5(소로) 120km 구간:
- 현재: FC2 cost = 100km × 5.0 = 500 단위, FC5 cost = 120km × 0.2 = 24 단위
  → FC5 선택 (24 < 500)
- class_factors가 무효일 때: FC2 cost = 100km × 1.0 = 100, FC5 cost = 120km × 1.0 = 120
  → FC2 선택 (100 < 120) ← 현재 동일 경로가 나오는 이유

**결론**: class_factors가 실제로 적용된다면 극단적 차별화가 발생한다. 미적용이라면 지금과 동일.

### 9.3 `use_living_streets: 1.0`의 한계

```
// Valhalla 내부 동작 추정
if highway == 'living_street':
    edge_cost *= (2.0 - use_living_streets)  // 1.0 → 계수 1.0 = 중립
    // 또는
    edge_cost /= use_living_streets           // 1.0 → 비용 동일
```

생활도로(living_street)를 1.0으로 설정해도 "선호"가 아니라 "중립"일 가능성이 있음. 0.0으로 설정하면 회피, 1.0으로 설정하면 원래 비용 그대로. "선호"가 되려면 1.0이 아닌 0.0이 회피, 1.0이 최대 선호일 경우에만 효과가 있음.

Valhalla 문서의 기본값이 0.5인 점을 고려하면:
- 0.0 = 강한 회피
- 0.5 = 중립 (기본)
- 1.0 = 강한 선호

이 해석이라면 `use_living_streets: 1.0`은 생활도로를 강하게 선호하므로 효과가 있음. (문서에서 확인)

---

## 10. OSM 데이터와 Valhalla 매핑 — 한국 도로 맥락

### 10.1 한국 주요 도로의 OSM 태그

(OSM 위키 + 한국 OSM 커뮤니티 관행 — 추정 포함)

| 한국 도로 | OSM highway= | Valhalla FC | 예시 |
|---|---|---|---|
| 고속국도 | motorway | FC1 | 경부고속도로 |
| 고속화도로 | trunk | FC2 | 수도권 제1순환고속도로 일부 |
| 일반국도 | primary | FC2-3 | 국도 1호선 |
| 지방도 | secondary | FC3-4 | 경기 614호선 |
| 군도/면도 | tertiary | FC4-5 | 군 단위 도로 |
| 농도/임도 | track | FC5 | 논밭 사이 길 |
| 마을 내부 | residential | FC5 | 동네 골목 |
| 생활도로 | living_street | FC5 | 보행자 우선구역 |

### 10.2 한국 OSM의 track 데이터 현황

**[추정]** 한국의 `highway=track`(농도/임도) 데이터는 도시 지역보다 농촌 지역에서 더 충실히 등록되어 있으나, 전국 단위로는 여전히 불완전. 특히:
- 산악 임도: 등산 커뮤니티가 적극 등록
- 농업용 도로: 지역에 따라 등록 밀도 큰 차이
- 군 훈련지역 내 도로: 대부분 미등록

따라서 `use_tracks: 1.0`의 효과는 지역에 따라 크게 달라질 수 있음.

---

*작성: 2026-06-05 (분석 Round 1 + 심화)*
