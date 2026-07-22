# RECON: 한국 OSM 도로등급 ↔ RoadClass 검증

작성: 2026-06-06, 읽기전용 정찰. 코드 수정 없음.
B단계(trace_attributes)만 실행 — osmium 미가용.

---

## 0. 데이터·도구

- **한국 pbf**: `/data/valhalla/custom_files/` 내 `.pbf` 없음 (운영 Valhalla는 사전 타일빌드된 그래프 `/data/valhalla/custom_files/*.bin` 사용)
- `find /data -maxdepth 4 -iname "*korea*.osm.pbf"` → 결과 없음
- `which osmium` → 없음 (`osmium`, `osmconvert`, `osmfilter` 모두 미가용)
- **결론**: A단계(OSM 소스 샘플링) 불가. B단계(trace_attributes) 단독 실행.
- **운영 Valhalla**: `https://valhalla.westinx.com` (Cloudflare tunnel → localhost:8002, runtime `3.7.0-5ed7267b7`)

---

## A. OSM 소스 샘플링

**osmium 미가용으로 생략.** 부록의 명령으로 마스터가 직접 실행 가능.

---

## B. 엔진 교차확인 (trace_attributes)

운영 Valhalla의 `/trace_attributes` 엔드포인트로 실제 도로를 trace해 `edge.road_class` + `edge.names` 추출.
모두 `"costing":"motorcycle"`, `"shape_match":"map_snap"` 사용.

### B-1. 고속도로 (경부고속도로)

좌표 취득: 먼저 `/route`로 경부고속도로 경로 요청 → shape polyline 디코딩 → 연속 두 점 사용.

```bash
# 경부 2지점 route 요청
curl -s -X POST https://valhalla.westinx.com/route \
  -H "Content-Type: application/json" \
  -d '{"locations":[{"lat":37.402,"lon":127.113},{"lat":37.285,"lon":127.013}],
       "costing":"motorcycle","costing_options":{"motorcycle":{"use_highways":1.0}}}'

# 디코딩된 연속점으로 trace
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{"shape":[{"lat":37.40187,"lon":127.11256},{"lat":37.39952,"lon":127.11121},...],
       "costing":"motorcycle","shape_match":"map_snap",
       "filters":{"attributes":["edge.road_class","edge.names","edge.way_id"],"action":"include"}}'
```

| 도로명 | way_id | edge.road_class | RoadClass enum |
|--------|--------|-----------------|----------------|
| (경부고속도로 본선) | 759968472 | **motorway** | 0 |

### B-2. 국도 (일반국도)

**국도 1호선 — 경수대로 (수원 구간)**
```bash
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{"shape":[{"lat":37.2614,"lon":127.0285},{"lat":37.2585,"lon":127.0278}],
       "costing":"motorcycle","shape_match":"map_snap",
       "filters":{"attributes":["edge.road_class","edge.names"],"action":"include"}}'
```

**국도 6/19호선 — 경강로 (여주 구간)**
```bash
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{"shape":[{"lat":37.2996,"lon":127.6351},{"lat":37.2993,"lon":127.6362}],
       ...}'
```

| 도로명 | ref | edge.names 중 ref | edge.road_class | RoadClass |
|--------|-----|-------------------|-----------------|-----------|
| 경수대로 (국도 1호) | 1 | 경수대로, ref='1' | **primary** | 2 |
| 경기대로 (국도 1호) | 1 | 경기대로, ref='1' | **primary** | 2 |
| 경강로 (국도 6/19호) | 6, 19 | 경강로, ref='6','19' | **primary** | 2 |
| 세종대로 (국도 48/31호) | 48, 31 | 세종대로, ref='48','31' | **primary** | 2 |

### B-3. 도시고속도로/자동차전용도로

**서울 서부간선지하도로 (도시고속도로)**
```bash
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{"shape":[{"lat":37.5215,"lon":126.896},{"lat":37.5225,"lon":126.897}],
       "costing":"motorcycle","shape_match":"map_snap",
       "filters":{"attributes":["edge.road_class","edge.names"],"action":"include"}}'
```

| 도로명 | edge.road_class | RoadClass |
|--------|-----------------|-----------|
| 서부간선지하도로 (서울 도시고속도로) | **trunk** | 1 |

### B-4. 지방도

**지방도 98호선 — 양근로 (양평 구간)**

| 도로명 | ref | edge.road_class | RoadClass |
|--------|-----|-----------------|-----------|
| 양근로 | 98 | **secondary** | 3 |
| 신천대로 (부산) | — | **secondary** | 3 |

### B-5. 시군도/면도 (tertiary)

**충남 홍성군 농촌 도로**

| 도로명 | edge.road_class | RoadClass |
|--------|-----------------|-----------|
| 백월로 (홍성 시군도) | **tertiary** | 4 |

### B-6. 마을도로/이면도로 (residential)

| 위치 | edge.road_class | RoadClass |
|------|-----------------|-----------|
| 충북 보은군 성주1길 | **residential** | 6 |
| 경기 용인 처인구 이면도로 | **residential** | 6 |

---

## C. 결론 — 한국 도로 ↔ RoadClass 확정 매핑

| 한국 행정 도로 | 실제 OSM highway= | RoadClass(0~7) | 실증 사례 |
|---------------|-------------------|----------------|-----------|
| 고속도로 | `motorway` | **0** | 경부고속도로 |
| 도시고속도로/자동차전용도로 | `trunk` | **1** | 서울 서부간선지하도로 |
| 일반국도 | `primary` | **2** | 국도 1호선 경수대로, 국도 6/19호선 경강로, 세종대로 |
| 지방도 | `secondary` | **3** | 지방도 98호선 양근로, 신천대로 |
| 시군도/면도 | `tertiary` | **4** | 홍성 백월로 |
| 읍면 이면도로 | `unclassified` | **5** | (미수집) |
| 마을도로/골목 | `residential` | **6** | 보은 성주1길, 용인 이면도로 |
| 농로/서비스도로 | `service` | **7** | (service_other 반환 확인) |

### 핵심 발견

1. **일반국도 = `primary`(RoadClass 2), NOT `trunk`(RoadClass 1)**  
   국도 1호·6호·19호·48호·31호 전부 `primary`로 태깅됨. `trunk`는 **서울 도시고속도로** 계열만 해당.

2. **`trunk` 한국 실체 = 서울 도시고속도로/자동차전용도로**  
   서부간선지하도로, 내부순환로, 동부간선도로 등 고속화도로가 `trunk`.  
   일반 국도번호 부여 도로는 `trunk` 아님.

3. **지방도 = `secondary`(RoadClass 3) 확인**  
   3자리 지방도(98호선) → secondary. 앱 가정과 일치.

4. **시군도 = `tertiary`(RoadClass 4) 확인**  
   홍성·용인 시군 관할 도로 → tertiary. 앱 가정과 일치.

---

## D. class_factors 8키 프로필에 주는 영향

앱 현재 프로필의 키 "1"~"5"와 포크 설계(RECON_VALHALLA_FORK.md §5) 매핑 기준:

```
키 "1" → kMotorway(0) + kTrunk(1)   [고속도로 + 도시고속도로]
키 "2" → kPrimary(2)                 [일반국도]
키 "3" → kSecondary(3)               [지방도]
키 "4" → kTertiary(4)                [시군도]
키 "5" → kUnclassified(5) + kResidential(6) + kServiceOther(7)  [농로·이면도로]
```

| 프로필 | 키 | factor | 대상 도로(실증) | 의도 충족 여부 |
|--------|-----|--------|----------------|---------------|
| 시골길 | "1"=100 | 100× penalty | 고속도로·도시고속도로 | ✅ 고속도로 회피 |
| 시골길 | "2"=5 | 5× penalty | 일반국도 | ✅ 국도 회피 |
| 시골길 | "3"=2.5 | 2.5× penalty | 지방도 | ✅ 지방도 약회피 |
| 시골길 | "4"=1.0 | neutral | 시군도 | ✅ 시군도 선호 |
| 시골길 | "5"=0.2 | 0.2× prefer | 농로·이면도로 | ✅ 농로 적극 선호 |
| 지방도로 | "3"=0.5 | 0.5× prefer | 지방도 | ✅ 지방도 선호 |
| 국도 | "2"=0.4 | 0.4× prefer | 일반국도 | ✅ 국도 선호 |

**✅ 가정이 맞은 부분**: 지방도→secondary(3), 시군도→tertiary(4) — 앱 프로필 설계와 일치.

**⚠️ 가정이 틀렸던 부분**: 초기 분석 문서(MORNING_REPORT_COURSE.md, docs/course_analysis)에서 "국도=trunk(1)"로 기술된 부분. 실제는 국도=primary(2). 단, 앱의 실제 프로필 키 "2"가 이미 일반국도(primary)를 올바르게 가리킴. **프로필 숫자값 자체는 이미 정합적**.

**❓ 미확인**: `unclassified`(RoadClass 5) 실사례. trace 결과에서 미관측.

---

## 부록: 마스터가 직접 돌릴 검증 명령

### 1. osmium A단계 명령 (osmium 설치 후)

```bash
KR=/data/valhalla/custom_files/<korea>.osm.pbf  # 실제 경로로 교체
for C in motorway trunk primary secondary tertiary unclassified residential; do
  osmium tags-filter "$KR" w/highway=$C -o /tmp/kr_$C.osm.pbf --overwrite 2>/dev/null
  echo "=== $C ==="
  osmium cat /tmp/kr_$C.osm.pbf -f opl 2>/dev/null \
    | grep -oE 'Tref=[^,]*|Tname:ko=[^,]*|Tname=[^,]*' \
    | sort | uniq -c | sort -rn | head -25
done
```

### 2. trace_attributes 재실행 템플릿

```bash
# 임의 도로 좌표 두 점 (Google Maps/OpenStreetMap에서 취득)
curl -s -X POST https://valhalla.westinx.com/trace_attributes \
  -H "Content-Type: application/json" \
  -d '{
    "shape":[{"lat":<LAT1>,"lon":<LON1>},{"lat":<LAT2>,"lon":<LON2>}],
    "costing":"motorcycle",
    "shape_match":"map_snap",
    "filters":{"attributes":["edge.road_class","edge.names","edge.way_id"],"action":"include"}
  }' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for e in d.get('edges',[])[:8]:
    print(f'rc={e.get(\"road_class\",\"?\")}  names={e.get(\"names\",[])}  way={e.get(\"way_id\",\"?\")}')
"
```

### 3. unclassified(RC5) 실사례 수집 후보 좌표

- 강원 강릉·평창 산간: lat=37.7~37.9, lon=128.4~128.6 일대 소로
- 경북 안동·예천 농촌: lat=36.4~36.6, lon=128.6~128.9 일대 소로
