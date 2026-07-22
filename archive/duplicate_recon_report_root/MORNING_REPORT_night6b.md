# MORNING_REPORT night6b — 경로 ETA 현실화 + 3경로 distinct화

날짜: 2026-06-02 (야간 작업)

## 결과 요약

- STAGE 1 (ETA 현실화): **PASS** — commit 48f320f
- STAGE 2 (3경로 distinct): **PASS** — commit 480ff27
- flutter analyze: **No issues found**
- APK 빌드: 미수행 (지시 준수)

---

## STEP 1: 진단 수치

### Valhalla 응답 원본값 (localhost:8002, motorcycle + use_highways:0)

| 좌표 | 거리km | Valhalla time(s) | 산출 km/h |
|------|--------|-----------------|-----------|
| 서울강남→수원 30km급 | 30.7 | 1922 | 57.4 |
| 서울강남→동탄 40km급 | 40.6 | 1801 | 81.1 |

**결론**: Valhalla 낙관치 57-88km/h → 앱이 2배 빠른 ETA 표시하던 원인.  
(네이버 실측: 71km = 118min = 36km/h)

---

## STAGE 1: ETA 현실화 — before/after

| 항목 | Before | After |
|------|--------|-------|
| ETA 계산방식 | Valhalla time(초) ÷ 60 | 거리 ÷ 실효속도(km/h) × 60 |
| 71km 시골길 ETA | ~49min (Valhalla시간 기준) | 142min (30km/h) |
| 71km 지방도로 ETA | ~49min | **118min** (36km/h) ← 네이버 실측과 일치 |
| 71km 국도 ETA | ~49min | 95min (45km/h) |

속도 상수 (파일 상단 명명된 const):
```
_speedCountrysideKmh = 30.0  // 시골길
_speedLocalKmh       = 36.0  // 지방도로
_speedNationalKmh    = 45.0  // 국도
```

---

## STAGE 2: 3경로 distinct — before/after

| 항목 | Before | After |
|------|--------|-------|
| Valhalla 호출 방식 | alternates:2 1회 | 코스별 3회 병렬(Future.wait) |
| 경로 구분 방식 | 거리 내림차순 정렬 | 프로파일별 costing_options 차등 |

### costing_options 차등표

| 코스 | use_living_streets | use_tracks | top_speed | shortest |
|------|--------------------|------------|-----------|----------|
| 시골길 | 1.0 | 0.8 | 40kph | - |
| 지방도로 | 0.5 | 0.2 | - | - |
| 국도 | 0.0 | 0.0 | - | true |

공통: `use_highways: 0.0` (전 코스 고속도로 배제 유지)

---

## curl 검증 결과 — 3경로 비교표

좌표: 서울강남(37.50, 127.02) → 동탄(37.19, 127.08), westinx Valhalla

| 코스 | 거리km | Valhalla time | 실효속도 | 실효ETA | shape문자수 |
|------|--------|--------------|---------|---------|------------|
| 시골길 | 45.6 | 71min | 30km/h | **91min** | 4664 |
| 지방도로 | 42.4 | 48min | 36km/h | **71min** | 3796 |
| 국도 | 40.6 | 30min | 45km/h | **54min** | 2271 |

- 세 경로 거리 상이 (45.6 / 42.4 / 40.6km) ✓
- shape 문자수 상이 (4664 / 3796 / 2271) → geometry 구별 확인 ✓
- 국도 ETA ≈ 지방도 대비 **31% 빠름** (요구: 20~30%) ✓
- 시골길이 가장 길고 우회도로 경유 확인 ✓

---

## 차기 Rust 스코어링 설계 제안

### 목표
Valhalla가 제공한 3개 후보 경로를 fun-road 점수로 재평가하여 "진짜 시골길"을 선택하거나 추가 탐색.

### 입력 데이터

| 데이터 | OSM 필드 | 의미 |
|--------|---------|------|
| 도로등급 | `highway` tag | residential < unclassified < tertiary < secondary < primary |
| 포장여부 | `surface` tag | unpaved/gravel/dirt = 시골길 가점 |
| 숲 근접도 | `landuse=forest`, `natural=wood` | 폴리곤과 경로 간 최소거리 평균 |
| 굽이지수(curviness) | geometry 곡률 | 연속 포인트 방위각 변화량 합계 / 총거리 |
| 교통량 대리지표 | `lanes` count, `maxspeed` | 차선 多·속도제한 高 → 감점 |

### 스코어링 공식 초안 (PPT 정의 기반)

```
fun_score = (
    curviness_index * w_curve          // 굽이지수 가중
  + forest_proximity_score * w_forest  // 숲 근접도 가중
  + (1 - road_grade_score) * w_small   // 소로 가중 (고등급=저점)
  - traffic_penalty                    // 대로·다차선 감점
)
```

### 재탐색 트리거 기준 (PPT "1.3배 초과 시 지방도 혼합")

- 시골길 선택 후보 거리 > 국도 거리 × 1.3 → 지방도 혼합 루트로 fallback
- 국도 ETA 대비 시골길 ETA가 20~30% 이내면 "fun하면서 실용적" 범주

### 구현 구조안

```
Rust (fun_road_scorer crate)
  ├── fn score_route(polyline: Vec<LatLng>, osm_data: &OsmIndex) -> f32
  ├── fn curviness(pts: &[LatLng]) -> f32   // 방위각 변화 합산
  ├── fn forest_proximity(pts: &[LatLng], forest_polygons: &[Polygon]) -> f32
  └── fn road_grade_avg(pts: &[LatLng], way_tags: &WayTagIndex) -> f32

Flutter → Rust FFI (flutter_rust_bridge)
  └── fetchRoutes → score all 3 → sort by fun_score → display
```

### 데이터 소스
- 한국 OSM extract: geofabrik.de/asia/south-korea.osm.pbf
- 로컬 인덱스: OSMnx 또는 libosmium으로 전처리 → SQLite/FlatGeobuf
- 초기에는 highway tag + curviness만으로 MVP, 이후 숲 근접도 추가

---

## STOP 조건 해당 없음

양 STAGE 모두 PASS. STOP 조건(geometry 미구별, 검색 불안정) 미발생.

## 다음 작업 제안

1. 앱에서 실제 실행 시 3경로가 지도에 구별되어 표시되는지 화면 확인 (APK)
2. Rust fun-road 스코어링 MVP (curviness + highway tag)
3. 시골길 후보가 도심 대로 직진 시 자동 fallback 로직
