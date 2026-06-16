# RECON: Valhalla 차선(lanes) 데이터 실제 출력 확인

실행 일시: 2026-06-15  
서버: `yurunavi-valhalla` (localhost:8002) / 이미지: `valhalla-fork:patch2-signals` / 버전: 3.7.0  
타일: `/custom_files/valhalla_tiles.tar` (2021 타일, south-korea-latest.osm.pbf 기반)

---

## [1] 사용 좌표

마스터 당일 주행 좌표 미상. 아래 3개 구간으로 대체 테스트:
- **광화문→강남역** (37.5759,126.9769 → 37.4979,127.0276) — 도심 간선도로 10 maneuver
- **강남대로 단구간** (37.5012,127.0262 → 37.4979,127.0276) — lane_count=8 구간 포함
- **한강로→강변북로** (37.5385,126.9675 → 37.5340,126.9710) — 7 maneuver

※ 마스터 실제 좌표로 재검증 시에도 결론은 동일할 가능성 높음 (구조 문제이므로).

---

## [2] lanes/intersections/active_indication grep 결과

### route API 응답 (`/tmp/route_lanes.json`, 광화문→강남역)

| 키 | 출현 횟수 |
|----|-----------|
| `"lanes"` | **0** |
| `"intersections"` | **0** |
| `"active_indication"` | **0** |
| `"begin_shape_index"` | 10 (maneuver 수만큼) |
| `"end_shape_index"` | 10 |
| `"sign"` | 1 |

### 모든 경로 테스트 합산
3개 경로 전부 동일: `lanes`, `intersections`, `active_indication` 키 = **0**.

---

## [3] maneuver 샘플 구조

```json
{
  "type": 15,
  "instruction": "세종대로/48/31에서 좌회전 후 세종대로/31 방향으로 계속 진행",
  "verbal_transition_alert_instruction": "세종대로에서 좌회전",
  "verbal_succinct_transition_instruction": "좌회전",
  "verbal_pre_transition_instruction": "세종대로, 48에서 좌회전",
  "verbal_post_transition_instruction": "1km 동안 세종대로, 31 따라 계속",
  "street_names": ["세종대로", "31"],
  "begin_street_names": ["세종대로", "48", "31"],
  "bearing_before": 255,
  "bearing_after": 178,
  "time": 77.954,
  "length": 1.152,
  "cost": 193.982,
  "begin_shape_index": 4,
  "end_shape_index": 30,
  "travel_mode": "drive",
  "travel_type": "car"
}
```

**maneuver 키 집합 전체:**  
`bearing_after`, `bearing_before`, `begin_shape_index`, `begin_street_names`, `cost`,  
`end_shape_index`, `instruction`, `length`, `sign`, `street_names`, `time`, `toll`,  
`travel_mode`, `travel_type`, `type`, `verbal_*` 5종  

→ `lanes`, `turn_lanes`, `intersecting_edges`, `active_indication` **전부 없음.**

---

## [4] locate API 에서 edge 필드 확인

```
강남역 (lane_count=8 도로):
  lane_count: 8      ← 차선 수는 있음
  turn_lanes: None   ← 키 자체 없음 (.get() 반환값 None)
  has_sign: False
  cycle_lane: "none"

강남역 (lane_count=1 도로):
  lane_count: 1
  turn_lanes: None
```

locate 응답 전체에서 `lane` 포함 키 경로:
- `edges[0].edge.cycle_lane`
- `edges[0].edge.lane_count`

→ `turn_lanes` 필드 **부재** (Python `.get()` None = 키 없음).

---

## [5] Valhalla 빌드 설정 확인

`/custom_files/valhalla.json` → `mjolnir.data_processing`:
```json
{
  "infer_internal_intersections": true,
  "infer_turn_channels": true,
  "apply_country_overrides": true,
  ...
}
```

- `infer_turn_channels: true` → 슬립레인(진입로 분기) 추론 활성화. **turn:lanes 방향 데이터와 무관.**
- turn lane 직접 처리 설정 항목 **없음.**

CHANGELOG 확인 (valhalla 3.7.0):  
`ADDED: Turn lane information for valhalla serializer [#5078]`  
→ 3.7.0은 turn lane serializer 코드를 포함하지만, **타일에 데이터가 없으면 출력 없음.**

---

## [6] 원인 분석

### 원인 A: OSM 데이터에 `turn:lanes` 태그 희소

`osmium`은 컨테이너 미설치(호스트에서 컨테이너 내 PBF 직접 접근 불가).  
호스트 osmium으로 마운트된 경로 필터 시도 → PBF 호스트 미공개로 0 결과.

한국 OSM 데이터의 `turn:lanes` 태그 커버리지는 낮은 것으로 알려져 있음.  
(주요 간선도로 일부에만 존재, 지방도로·시군도 거의 없음)

### 원인 B: 타일 빌드 시 turn lane 처리 누락 가능성

Valhalla 타일 빌드 시 `turn:lanes` 태그를 edge에 저장하는 처리가 실행됐는지  
직접 확인 불가 (빌드 로그 없음). `valhalla_ways_to_edges` 실행 결과:  
`Finished with 9909229 ways` — turn lane 관련 로그 없음.

---

## 판정

**(C) 아예 없음** — route maneuver 응답에 `lanes`, `intersections`, `active_indication`  
키가 전혀 존재하지 않으며, locate edge에도 `turn_lanes` 필드가 없다.  
`lane_count`(차선 수 정수)와 `cycle_lane`(자전거 차선)만 타일에 존재.  
차선 유도(어느 차선에 서야 하는지) 기능 구현을 위해서는  
① 한국 OSM `turn:lanes` 태그 커버리지 확인 및 ② 타일 재빌드가 선행되어야 한다.
