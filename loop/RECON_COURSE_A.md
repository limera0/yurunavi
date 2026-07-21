# RECON: 코스 차별화 A안 설계 정찰

작성: 2026-06-06, 읽기 전용 정찰. 코드 수정 없음.

---

## 1. Valhalla 배포 실태

**이미지 / 태그**:
- `ghcr.io/valhalla/valhalla:latest` — `docker/docker-compose.yml:5`
- 태그 고정 없음 (`latest`). 스톡 공식 이미지. 커스텀 빌드 아님.

**기동 방식**:
- 컨테이너명: `yurunavi-valhalla` — `docker/docker-compose.yml:6`
- 포트: `8002:8002` — `docker/docker-compose.yml:9`
- 볼륨: `/data/valhalla/custom_files:/custom_files` — `docker/docker-compose.yml:11`
- 기동 커맨드: `valhalla_service /custom_files/valhalla.json 1` — `docker/docker-compose.yml:12`

**config.json 경로**:
- 컨테이너 내부: `/custom_files/valhalla.json`
- 호스트: `/data/valhalla/custom_files/valhalla.json`
- **repo 내에 이 파일 없음** — 내용(service_limits 등) 미확인.

**Valhalla 소스/빌드 파일**:
- **repo 내에 없음**. 공식 Docker 이미지 사용. A안 커스텀 costing을 C++ 소스로 구현하려면 별도 valhalla 소스 클론이 필요해짐.

**Dart vs Rust Valhalla URL**:
- Dart(`routing_service.dart`): `https://valhalla.westinx.com` (Cloudflare 터널 경유)
- Rust(`native/src/main.rs:8`): `const VALHALLA_URL: &str = "http://localhost:8002/route";`
- **동일한 Valhalla 인스턴스** — `MORNING_REPORT_COURSE.md:87`에서 확인: "Cloudflare 터널로 localhost:8002 포워딩"

---

## 2. 현재 라우팅 요청

**Costing 모델**: `"costing": "motorcycle"` — `lib/services/routing_service.dart:240`

**3코스 costing_options (verbatim)** — `routing_service.dart:143-188`:

```json
// 시골길 (idx 0) — L143-159
{
  "use_highways": 0.0,
  "use_ferry": 0.0,
  "use_living_streets": 1.0,
  "use_tracks": 0.8,
  "top_speed": 40,
  "class_factors": {
    "1": 100.0,
    "2": 5.0,
    "3": 2.5,
    "4": 1.0,
    "5": 0.2
  },
  "urban_penalty": 50.0
}

// 지방도로 (idx 1) — L161-173
{
  "use_highways": 0.0,
  "use_ferry": 0.0,
  "use_living_streets": 0.5,
  "use_tracks": 0.2,
  "class_factors": {
    "1": 100.0,
    "2": 2.0,
    "3": 0.5,
    "4": 0.7,
    "5": 1.5
  }
}

// 국도 (idx 2) — L175-188
{
  "use_highways": 0.0,
  "use_ferry": 0.0,
  "use_living_streets": 0.0,
  "use_tracks": 0.0,
  "shortest": true,
  "class_factors": {
    "1": 100.0,
    "2": 0.4,
    "3": 1.0,
    "4": 2.0,
    "5": 10.0
  }
}
```

**`alternates` 파라미터 사용 여부**: **없음** — `routing_service.dart:238-243` 요청 바디에 `locations`, `costing`, `costing_options` 3개만 있음. `alternates` 키 미존재.

**병렬 요청 구조**: `Future.wait` 로 3코스 동시 요청 — `routing_service.dart:233-245`

**ETA 계산**: Valhalla 응답의 `time` 필드 무시, `km / _courseSpeeds[i] * 60` 재계산 — `routing_service.dart:285-291`
- `_courseSpeeds` = [30, 36, 45] km/h (시골/지방/국도)

**시골길 1.3배 폴백**: `ruralMins / provMins >= 1.3` 이면 balanced costing으로 시골 재요청 — `routing_service.dart:320-388`

---

## 3. Rust 스코어링 레이어

### 함수 존재 여부 및 시그니처 (native/src/api.rs)

**`fun_score_v1`** — `api.rs:201-204`:
```rust
pub fn fun_score_v1(route: &[GpsPoint]) -> f64 {
    let tau = calc_tortuosity(route);
    ((tau - 1.0) * 50.0).clamp(0.0, 100.0)
}
```
입력: GPS 포인트 슬라이스. 반환: 곡률(τ) 단독 점수.

**`fun_score_v2`** — `api.rs:241-245`:
```rust
pub fn fun_score_v2(route: &[GpsPoint], avg_fc: f64) -> f64 {
    let tau_score = fun_score_v1(route);
    let fc_score  = road_class_score(avg_fc);
    (0.6 * tau_score + 0.4 * fc_score).clamp(0.0, 100.0)
}
```
입력: GPS 포인트 + FC 평균. 반환: τ 60% + FC 40%.

**`fun_score_v3`** — `api.rs:279-284`:
```rust
pub fn fun_score_v3(route: &[GpsPoint], avg_fc: f64, avg_speed_kmh: f64) -> f64 {
    let tau_score = fun_score_v1(route);
    let fc_score  = road_class_score(avg_fc);
    let t_score   = traffic_score(avg_speed_kmh);
    (0.5 * tau_score + 0.3 * fc_score + 0.2 * t_score).clamp(0.0, 100.0)
}
```
입력: GPS 포인트 + FC 평균 + 속도 평균(km/h). 반환: τ 50% + FC 30% + traffic 20%.

**`rank_candidates_v2`** — `api.rs:249-265`:
```rust
pub fn rank_candidates_v2(routes: Vec<(Vec<GpsPoint>, f64)>) -> Vec<RouteRank>
```
입력: `(경로 포인트, avg_fc)` 쌍 벡터. 반환: `fun_score_v2` 내림차순 정렬된 `Vec<RouteRank>`.
각 `RouteRank`에는 `original_index`, `fun_score`, `curvature_tau` 포함.

### 연결 여부 (파이프라인 추적)

**`/score_route` HTTP 엔드포인트** — `native/src/main.rs:311-343`:
- `trace_attributes_fc()` → Valhalla `/trace_attributes` 호출 → `edge.road_class` + `edge.speed` 취득
- `fun_score_v2` + `fun_score_v3` + `curvature_tau` 모두 계산
- 응답: `{ fun_score_v2, fun_score_v3, avg_fc, avg_speed_kmh, curvature_tau }` — `main.rs:336-342`

**Flutter에서 수신**: `lib/services/native_engine.dart:250-255`
```dart
return FunScoreResult(
  funScoreV2: (d['fun_score_v2'] as num?)?.toDouble() ?? 0.0,
  avgFc: (d['avg_fc'] as num?)?.toDouble() ?? 3.0,
  curvatureTau: (d['curvature_tau'] as num?)?.toDouble() ?? 1.0,
);
```
→ **`fun_score_v3`과 `avg_speed_kmh`는 응답에 있지만 Flutter가 파싱하지 않고 버림.**

**`rank_candidates_v2` 연결 상태**:
- `native/src/main.rs`에 `/rank_candidates` HTTP 엔드포인트 **없음** (grep 결과 0 hits)
- `rank_candidates_v2` 함수가 `main.rs`에서 **한 번도 호출되지 않음** (grep 결과 0 hits)
- flutter_rust_bridge codegen 미실행 → FFI 경로도 없음 (`native_engine.dart:272` 주석 확인)
- 결론: **`rank_candidates_v2`는 구현됐으나 라이브 파이프라인에 완전히 미연결**

---

## 4. 분석문서 주장 대조

### 주장 ①: "class_factors가 작동한다, 3코스가 다른 geometry"

**원문 출처** — `docs/course_analysis/00_open_questions.md:11`:
> "적용됨 — Night7 (2026-06-02) curl 검증으로 확인. 3경로 각각 다른 거리(17.2/15.9/15.4km) 반환. `class_factors`를 포함해도 400 에러 없음."
> "근거: git commit 10eab85 MORNING_REPORT_night7.md"

**근거가 된 테스트 좌표**:
- Night7 OD: "수원 영통구 → 용인 처인구" — `docs/course_analysis/01_current_state.md:107`
- Night6b OD: "서울강남 → 동탄" — `01_current_state.md:110`
- **구체적인 위경도(lat/lon) 숫자는 어떤 분석 문서에도 기록되지 않음.** `04_roadmap.md`의 curl 예시에 `lat:37.5, lon:127.0` 등이 있으나 이는 예시용 좌표이지 Night7 실제 테스트 좌표가 아님.

**04_roadmap의 "가장 먼저 칠 한 커밋" 권고 원문** — `04_roadmap.md:255-258`:
> "가장 작고 안전한 첫걸음 ← **명확히 지목**
> Step 2-A: routing_service.dart L143-159 시골길 top_speed 30으로 변경 + class_factors 극단화"

### 사실 vs 해석/추정 구분

| 항목 | 출처 | 분류 |
|---|---|---|
| class_factors가 motorcycle costing에 적용됨 | Night7 curl 검증 (commit 10eab85) | **사실** (검증됨) |
| 3코스가 수치상 다른 거리 반환 (15.4/15.9/17.2km) | `01_current_state.md:107-113` | **사실** (검증됨) |
| 장거리 OD에서 간선 구간 공유로 시각적으로 같아 보임 | `01_current_state.md:122-132` `[코드에서 확인 + 추정]` 표기 | **해석/추정** (폴리라인 교차 비율 미측정) |
| Dart(westinx.com)와 Rust(localhost:8002)가 동일 Valhalla | `MORNING_REPORT_COURSE.md:87` | **사실** (Cloudflare 터널 확인) |
| `use_living_streets: 1.0`이 "선호"로 작동 | `02_valhalla_costing.md:363-370` | **해석** (Valhalla 문서 기반, 실측 미수행) |
| top_speed: 30 시 60km/h 도로 비용 2-3배 상승 | `02_valhalla_costing.md:329-337` | **추정** (Valhalla 내부 계산 로직 가정) |
| class_factors의 정확한 RoadClass enum 매핑 | `02_valhalla_costing.md:202` | **추정** ("소스코드 확인 필요"로 명시됨) |
| alternates 파라미터로 다른 geometry 보장 | `02_valhalla_costing.md:311` | **추정** (Valhalla 버전 의존, 미검증) |

---

## 5. 경로 응답 등급 정보

### Dart routing_service.dart — Valhalla route 응답 파싱

파싱 코드: `routing_service.dart:275-318`

파싱되는 필드:
- `trip['legs']` — polyline (shape 디코딩)
- `leg['summary']['length']` — 거리(km)
- `trip['summary']['time']` — **파싱되나 ETA에는 사용 안 함**
- `leg['maneuvers']` — type, instruction, length

**파싱되지 않는 필드**: `road_class`, `surface`, `use`, 엣지 속도, FC 등급 — **없음**

### Rust main.rs — trace_attributes로 등급 취득

`trace_attributes_fc()` 함수 — `native/src/main.rs:150` 호출:
```json
// Valhalla /trace_attributes 요청 (main.rs 내부)
{
  "filters": {
    "attributes": ["edge.road_class", "edge.length", "edge.speed"],
    "action": "include"
  }
}
```
- `edge.road_class` → `road_class_to_fc()` 변환 → `avg_fc` — `docs/course_analysis/03_funroad_design.md:251-259`
- `edge.speed` → `avg_speed_kmh`
- 이 결과는 `/score_route` 응답(`fun_score_v2/v3`)에만 사용 — **라우팅 경로 선택에 피드백 없음**

**결론**: 도로 등급 정보는 Rust `/score_route` 경로에서만 취득 가능. Dart는 Valhalla route 응답에서 직접 파싱하지 않음. A안에서 FC 기반 재랭킹을 하려면 이 `/score_route` 흐름을 활용해야 함.

---

## 6. 종합

### ✅ 확인된 사실

1. Valhalla = `ghcr.io/valhalla/valhalla:latest`, 포트 8002, config 호스트경로 `/data/valhalla/custom_files/valhalla.json` (내용 미확인)
2. `class_factors`는 motorcycle costing에 실제 적용됨 (Night7 curl 검증, commit 10eab85)
3. 3코스 costing_options는 `routing_service.dart:143-188`에 이미 상당히 차별화된 파라미터로 설정됨
4. `alternates` 파라미터는 현재 요청에 없음 — 3코스 각각 독립 요청
5. `fun_score_v2`, `fun_score_v3`, `rank_candidates_v2`가 `native/src/api.rs`에 구현 완료
6. Rust `/score_route`는 `fun_score_v3` + `avg_speed_kmh`를 이미 계산해 응답에 포함 — Flutter는 v2만 사용
7. `rank_candidates_v2`는 main.rs에서 호출되지 않음, HTTP 엔드포인트도 없음 — **완전 미연결**
8. Dart/Rust Valhalla URL이 다르나 동일 인스턴스 (Cloudflare 터널)
9. 재탐색 버그(`routes[0]` 하드코딩)는 commit `d0f16bb`에서 이미 수정됨

### ❓ 미확인 (코드에서 못 찾음)

1. `/data/valhalla/custom_files/valhalla.json` 실제 내용 (service_limits, custom_costing 설정 여부) — repo 외부
2. Valhalla `alternates` 파라미터 실제 지원 여부 — 현재 이미지에서 테스트 필요
3. `class_factors` 수치 효과의 실제 "폴리라인 교차 비율" — Night7 검증은 거리 비교만, 중복 구간 비율 미측정
4. Night7/Night6b 검증에 사용된 정확한 위경도 좌표 — 분석 문서에 지명만 있고 좌표 없음

### ⚠️ 분석문서가 추측이었던 것

1. "장거리에서 간선 구간 공유로 시각적으로 같아 보임" — `[코드에서 확인 + 추정]` 표기 (`01_current_state.md:122`)
2. `top_speed`의 비용 증가 공식 (`edge_cost = length / min(speed, top_speed)`) — Valhalla 소스 미확인 (`02_valhalla_costing.md:323`)
3. `class_factors`의 `"1"~"5"` 키가 Valhalla 내부 RoadClass enum에 정확히 대응하는지 — "소스코드 확인 필요" 명시 (`02_valhalla_costing.md:202`)
4. `use_living_streets: 1.0`이 진짜 "선호"로 작동하는지 (factor=0.5이 중립이면 1.0이 선호) — 공식 문서 기반 해석, 실측 미수행
5. `alternates` 파라미터로 실제 다른 geometry가 보장되는지 — "Valhalla 버전에 따라 다를 수 있음" 명시 (`02_valhalla_costing.md:312`)

### 🔧 A안 진행 시 추가로 필요한 것

1. **Valhalla alternates 지원 확인** (Phase 3 전제): 부록 curl #1 실행 → `alternates` 키 존재 여부
2. **valhalla.json 내용 확인**: `custom_costing` 확장 여부 — A안이 커스텀 costing C++ 구현을 포함할 경우 소스 클론 위치 결정에 영향
3. **`/rank_candidates` HTTP 엔드포인트 추가**: `rank_candidates_v2`를 파이프라인에 연결하려면 `native/src/main.rs`에 새 핸들러 필요 (현재 없음)
4. **`FunScoreResult` 확장**: `funScoreV3`, `avgSpeedKmh` 필드 추가 시 2파일 수정 (`native_engine.dart` + `main_map_screen.dart`) — 즉시 가능, 위험 없음
5. **Night7 검증 좌표 확보**: 폴리라인 교차 비율 측정을 위해 실제 테스트 OD 좌표 필요 (분석 문서에 없음, MORNING_REPORT_night7.md 또는 직접 실측 필요)

---

## 부록: 마스터가 직접 실행할 검증 (자동 실행 금지)

```bash
# 1. Valhalla alternates 파라미터 지원 여부 확인 (Phase 3 전제)
# 기대: 응답에 "alternates" 배열이 있으면 Phase 3 가능
curl -s -X POST https://valhalla.westinx.com/route \
  -H "Content-Type: application/json" \
  -d '{
    "locations":[{"lat":37.5,"lon":127.0},{"lat":37.7,"lon":127.3}],
    "costing":"motorcycle",
    "costing_options":{"motorcycle":{"use_highways":0.0}},
    "alternates":2
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('alternates:', len(d.get('alternates',[])), 'trip_km:', d.get('trip',{}).get('summary',{}).get('length'))"

# 2. valhalla.json 내용 확인 (서버 직접 접근)
cat /data/valhalla/custom_files/valhalla.json | python3 -m json.tool | head -80

# 3. Night7 검증 재현 — class_factors 실제 적용 확인
# (수원 영통구 → 용인 처인구 근사 좌표)
curl -s -X POST https://valhalla.westinx.com/route \
  -H "Content-Type: application/json" \
  -d '{
    "locations":[{"lat":37.2793,"lon":127.0431},{"lat":37.2394,"lon":127.1999}],
    "costing":"motorcycle",
    "costing_options":{"motorcycle":{"use_highways":0.0,"use_living_streets":1.0,"use_tracks":0.8,"top_speed":40,"class_factors":{"1":100,"2":5,"3":2.5,"4":1,"5":0.2},"urban_penalty":50}}
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('시골길 km:', d.get('trip',{}).get('summary',{}).get('length'))"

# 4. /rank_candidates 엔드포인트 존재 여부 확인 (Rust 서버)
curl -s https://navi.westinx.com:8003/rank_candidates -X POST \
  -H "Content-Type: application/json" \
  -d '{"routes":[]}' | head -5
# 404 또는 422 반환 → 엔드포인트 없음 확인

# 5. /score_route 응답에서 fun_score_v3 필드 확인
curl -s https://navi.westinx.com:8003/score_route -X POST \
  -H "Content-Type: application/json" \
  -d '{"points":[{"lat":37.5,"lng":127.0},{"lat":37.6,"lng":127.1},{"lat":37.7,"lng":127.2}]}' \
  | python3 -m json.tool
# 기대: fun_score_v2, fun_score_v3, avg_fc, avg_speed_kmh, curvature_tau 모두 존재

# 6. Valhalla 버전 확인
curl -s https://valhalla.westinx.com/status | python3 -m json.tool
```
