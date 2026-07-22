# 무빌드 검증 — 317번 실제 속성 + 기존 speed_penalty_factor 효과

> 환경: 마스터 직접(또는 Claude Code) 실행. 운영/8012에 읽기 요청만. 빌드 없음.
> 목표: ① 317번 "고속 직진 고가" 구간의 실제 curvature/bridge/speed 값 확인(페널티가 걸릴 신호인지) ② top_speed+speed_penalty_factor만으로 317 회피가 되는지(포크 없이 가능한지) 확인.

## 사전: 317번 구간 좌표 2점

PPT slide의 317번 고속 직진 고가 구간(팔당 남쪽, 차들 120km/h 구간)에서 **이어지는 두 점**의 lat/lon을 지도에서 취득해 아래 <L1><O1>,<L2><O2>에 기입. (마스터가 길을 아니까 직접 찍는 게 정확.)

## STEP A — 317의 실제 속성 (curvature/bridge/speed)

```bash
curl -s -X POST http://localhost:8012/trace_attributes -H "Content-Type: application/json" -d '{
  "shape":[{"lat":<L1>,"lon":<O1>},{"lat":<L2>,"lon":<O2>}],
  "costing":"motorcycle","shape_match":"map_snap",
  "filters":{"attributes":["edge.road_class","edge.curvature","edge.use","edge.bridge","edge.tunnel","edge.length","edge.speed","edge.names"],"action":"include"}
}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for e in d.get('edges',[])[:12]:
    print(f\"rc={e.get('road_class','?'):9} curv={e.get('curvature','?'):>2} bridge={str(e.get('bridge',False)):5} spd={e.get('speed','?'):>3} len={e.get('length','?'):>5} {e.get('names',[])}\")
"
```

**판독:**

- `curv`(곡률)이 0~2면 → 곡률 페널티로 잡힌다 ✅
- `bridge=True`면 → bridge 페널티로 잡힌다 ✅ / `False`면 그 고가가 OSM에 bridge 태깅 안 된 것 → bridge 페널티 무효 ⚠️
- `spd`가 90~120이면 → 속도 페널티로 잡힌다 ✅
- 세 신호 중 **어떤 게 317을 실제로 식별하는지** 확인 = 어떤 페널티를 만들지 결정

## STEP B — 포크 없이 speed_penalty_factor만으로 회피되나

같은 OD(평택→팔당, slide와 동일)에 시골길 class_factors + **top_speed 낮춤 + speed_penalty_factor 대폭 상향**만 추가. (둘 다 기존 파라미터라 8012 포크가 이미 지원.)

```bash
# B1: 현재 시골길 (속도 페널티 없음) — 기준
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":<출발L>,"lon":<출발O>},{"lat":<도착L>,"lon":<도착O>}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0,"class_factors":{"0":100,"1":100,"2":6,"3":2,"4":0.6,"5":0.8,"6":0.9,"7":1.0}}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('B1 기준 km:',d['trip']['summary']['length'])"

# B2: + top_speed 60 + speed_penalty_factor 0.5 (기본 0.05의 10배)
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":<출발L>,"lon":<출발O>},{"lat":<도착L>,"lon":<도착O>}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0,"top_speed":60,"speed_penalty_factor":0.5,"class_factors":{"0":100,"1":100,"2":6,"3":2,"4":0.6,"5":0.8,"6":0.9,"7":1.0}}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('B2 속도페널티 km:',d['trip']['summary']['length'])"

# B3: top_speed 50 + speed_penalty_factor 1.0 (더 강하게)
curl -s -X POST http://localhost:8012/route -H "Content-Type: application/json" -d '{
  "locations":[{"lat":<출발L>,"lon":<출발O>},{"lat":<도착L>,"lon":<도착O>}],
  "costing":"motorcycle",
  "costing_options":{"motorcycle":{"use_highways":0.0,"top_speed":50,"speed_penalty_factor":1.0,"class_factors":{"0":100,"1":100,"2":6,"3":2,"4":0.6,"5":0.8,"6":0.9,"7":1.0}}}
}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('B3 강한페널티 km:',d['trip']['summary']['length'])"
```

추가로 B2/B3 경로를 trace해서 317 구간(고curv/highspeed)을 실제로 피했는지 등급+속도 분포 확인하면 확실(STEP A 스크립트의 OD를 B2 경로로).

**판정:**

- B2/B3가 B1과 **거리/경로가 달라지고 317을 피하면** → 속도 부분은 **포크 불필요**, 앱 파라미터만으로 해결.
- 거의 안 변하면 → 기존 speed_penalty_factor가 약한 것. 그땐 곡률 페널티(포크)가 본命.
  
  ```
  
  ```

작성/실행 후, STEP A 표 + B1/B2/B3 거리값 보고.
