# 유루나비 Valhalla 튜닝 대시보드 — 구현 작업 명세서 (Claude Code 전달용)

> 목적: 코드를 직접 수정하지 않고, 웹 화면에서 마우스로 motorcycle costing 가중치를
> 조절 → 즉시 Valhalla 라우팅 결과를 모바일 비율 지도에 시각화하는 로컬 튜닝 대시보드.

---

## ⭐ 이 도구가 하는 일 (사용자 관점 — 이 부분만 읽어도 됨)

화면 하나에서 가중치를 조절하고 [적용]을 누르면, 그 가중치로 계산된 경로를
유루나비와 똑같은 지도 위에 즉시 그려주는 도구다. 코드를 만지지 않고 숫자만 바꿔가며
경로를 반복해서 파인튜닝한다.

**화면 구성**

- 왼쪽: 유루나비와 동일한 세로(모바일) 비율 지도 + 동일 타일/룩. 위에 출발지·목적지 입력.
- 오른쪽: 가중치 조절 패널. + / − 버튼과 직접 숫자 입력 둘 다 가능.
- [적용] 버튼: 누르면 현재 가중치로 경로 계산 → 지도에 표시.
- 시골/지방도/국도 3개 경로를 색깔별로 겹쳐 표시 → 차이가 한눈에 보임.

**사용 흐름**: 출발/목적지 지정 → 가중치 조절 → [적용] → 지도 확인 → (반복).

**UI 라벨 원칙**: 슬라이더/입력 라벨은 기술 키명이 아니라 한국어 사람말로 표기.
예) `class_factors[2]` → "국도(일반국도) 선호도", `curvature_penalty` → "굽은길 선호도",
`long_tunnel_penalty` → "긴 터널 회피 정도". (내부 키 매핑은 PARAMS_MANIFEST.md 참조)

---

## 0. 아키텍처 (교정본 — 반드시 숙지)

```
[Streamlit Dashboard :8501]
   │  슬라이더/number_input → st.session_state 에 값 보관 (위젯 조작마다 호출 X)
   │  "경로 테스트" 버튼 클릭 시에만:
   ├─ 1) routing_config.yaml 저장 (대시보드 source-of-truth)
   ├─ 2) 값 → costing_options.motorcycle JSON 조립
   ├─ 3) HTTP POST → Valhalla /route (localhost:8002)
   ├─ 4) trip.legs[].shape 디코드  ★precision=6 (Valhalla는 1e6)
   ├─ 5) (선택) /trace_attributes 로 도로등급 분포 계산
   └─ 6) MapLibre GL JS 지도에 polyline 렌더 + 지표 패널
```

### 핵심 사실 (틀리면 전부 헛돈다)

- Valhalla 포크의 튜닝 파라미터(`class_factors`, curvature/bridge/tunnel penalty)는
  **요청 body의 `costing_options.motorcycle` 에 JSON으로** 들어간다. yaml에서 읽지 않는다.
- `valhalla.json` 은 **빌드/서비스 설정**(타일 경로 등). per-request 가중치 아님. **건드리지 말 것.**
- Valhalla 는 이미 **8002 HTTP 서비스**로 떠 있다. 바이너리를 exec 하지 않는다.
- Valhalla polyline 은 **precision 6**. precision 5로 디코드하면 좌표가 10배 어긋난다 (대표 버그).
- 3개 프로파일은 **각각 별도 호출** (단일 호출 + `alternates:2` 아님).

### 결정 기본값

| 항목      | 기본값                                 | 대안                         |
| ------- | ----------------------------------- | -------------------------- |
| 튜닝 대상   | **Valhalla 직통 8002** (코드 무수정, 최속)   | Rust 8003 경유 = Phase 9(선택) |
| 지도      | **MapLibre GL JS + tileserver 스타일** | folium(쉬움/저충실도)            |
| 프로파일 표시 | **3색 오버레이 기본 ON**                   | 단일 프로파일 토글                 |

---

## 1. 기술 스택 / 디렉토리

- Python 3.11+, Streamlit, requests, PyYAML
- MapLibre GL JS (CDN), st.components.v1.html 로 임베드
- Docker + docker-compose (Ubuntu headless `westinx`)

```
/data/projects/yurunavi/tools/tuning_dashboard/
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
├── .env                      # 엔드포인트/포트 (하드코딩 금지)
├── .env.example
├── routing_config.yaml       # 3 프로파일 × 파라미터 (source-of-truth)
├── PARAMS_MANIFEST.md         # Phase 0 산출물: 포크 실제 파라미터 명세
├── app.py                    # Streamlit 진입점 (레이아웃/이벤트)
├── core/
│   ├── config.py             # yaml 로드/저장
│   ├── valhalla_client.py    # costing_options 조립 + POST + polyline 디코드
│   └── metrics.py            # /trace_attributes 도로등급·curvature 분포(선택)
└── components/
    └── maplibre_map.html      # 지도 임베드 템플릿
```

---

## 2. 환경/설정 파일 예시

### .env.example

```env
VALHALLA_URL=http://localhost:8002
RUST_SERVER_URL=http://localhost:8003
TILESERVER_STYLE_URL=https://tiles.westinx.com/styles/osm_liberty_yurunavi/style.json
DASHBOARD_PORT=8501
# 기본 출발/목적지 (Seoul–Paldang 차별화 진단용)
DEFAULT_ORIGIN_LAT=37.5547
DEFAULT_ORIGIN_LON=126.9706
DEFAULT_DEST_LAT=37.5306
DEFAULT_DEST_LON=127.3214
```

### routing_config.yaml (초안 — Phase 0에서 키/범위 확정 후 갱신)

```yaml
# 주의: 아래 키 이름/범위는 추정값. Phase 0 grep 결과로 반드시 교정할 것.
profiles:
  rural:        # 시골길 우선
    color: "#e64980"
    class_factors: { "0": 5.0, "1": 5.0, "2": 1.5, "3": 0.9, "4": 0.7, "5": 0.8, "6": 1.0, "7": 1.2 }
    curvature_penalty: 0.2      # 낮을수록 굽은길 선호
    long_bridge_penalty: 1.0
    long_tunnel_penalty: 1.0
    bridge_length_threshold_m: 500
    use_highways: 0.0
    use_tolls: 0.0
  provincial:   # 지방도 우선
    color: "#4263eb"
    class_factors: { "0": 5.0, "1": 5.0, "2": 1.2, "3": 0.7, "4": 0.9, "5": 1.0, "6": 1.1, "7": 1.3 }
    curvature_penalty: 0.5
    long_bridge_penalty: 1.0
    long_tunnel_penalty: 1.0
    bridge_length_threshold_m: 500
    use_highways: 0.0
    use_tolls: 0.0
  national:     # 국도 우선
    color: "#2f9e44"
    class_factors: { "0": 3.0, "1": 3.0, "2": 0.8, "3": 1.0, "4": 1.2, "5": 1.3, "6": 1.4, "7": 1.5 }
    curvature_penalty: 1.0
    long_bridge_penalty: 1.0
    long_tunnel_penalty: 1.0
    bridge_length_threshold_m: 500
    use_highways: 0.0
    use_tolls: 0.2
hard_constraints:
  time_fallback_multiplier: 1.5   # 경로 수용 한계 (메모리: 1.3→1.5로 변경됨)
```

---

## 3. 단계별 작업 (체크리스트)

각 Phase는 **목표 / 파일 / 작업 / 검증 / 로그확인** 순서. **한 Phase = 한 커밋.**
앞 Phase 검증 통과 전까지 다음으로 넘어가지 말 것.

---

### ☐ Phase 0 — Recon: 포크 실제 파라미터 확정 (코드 작성 금지)

- **목표**: 포크가 실제로 받는 costing_options 키 이름·타입·유효범위를 확정. (추측 금지)
- **작업**:
  
  ```bash
  # 0) 포크 소스 위치 자동 탐색 (경로를 모르면 먼저 찾는다)
  find / -name options.proto -path "*valhalla*" 2>/dev/null
  find / -name motorcyclecost.cc 2>/dev/null
  # 위에서 나온 디렉토리로 이동
  # 정확한 파라미터 키 추출
  cd /data/projects/yurunavi   # 위 find 결과 경로로 조정
  grep -rn "class_factors\|curvature\|bridge\|tunnel" --include=*.proto
  grep -rn "ParseMotorcycleCostOptions\|kClassFactor\|class_factors" --include=*.cc
  # options.proto 에서 motorcycle costing 메시지 정의 전체 확인
  sed -n '/MotorcycleCostingOptions/,/}/p' <options.proto 경로>
  ```
- **산출물**: `PARAMS_MANIFEST.md` 에 표로 정리
  `| param | json_key | type | min | max | default | 의미 |`
- **검증**: RoadClass 0~7 키 8개가 실제로 매핑되는지, curvature/bridge/tunnel penalty의 정확한 키명 확인.
- **STOP**: 여기서 멈추고 PARAMS_MANIFEST.md 보고. yaml 키 교정 후 Phase 1.

---

### ☐ Phase 1 — 프로젝트 스캐폴드

- **목표**: 디렉토리/의존성/환경변수 골격.
- **작업**:
  
  ```bash
  mkdir -p /data/projects/yurunavi/tools/tuning_dashboard/{core,components}
  cd /data/projects/yurunavi/tools/tuning_dashboard
  cat > requirements.txt <<'EOF'
  streamlit==1.40.2
  requests==2.32.3
  PyYAML==6.0.2
  python-dotenv==1.0.1
  EOF
  cp .env.example .env   # 값 채우기
  ```
- **검증**: `python -c "import streamlit, requests, yaml, dotenv"` 무에러.
- **로그**: 없음(설치 단계).

---

### ☐ Phase 2 — 설정 로더 (core/config.py)

- **목표**: routing_config.yaml 안전 로드/저장.
- **작업**: `load_config()`, `save_config(cfg)` (atomic write: temp→os.replace), `.env` 로드.
- **검증**: `python -c "from core.config import load_config; print(load_config()['profiles'].keys())"`
  → `dict_keys(['rural','provincial','national'])`.
- **로그**: 저장 시 어떤 파일에 썼는지 stdout 1줄.

---

### ☐ Phase 3 — Valhalla 클라이언트 (core/valhalla_client.py)

- **목표**: 프로파일 1개 → costing_options 조립 → POST → polyline 좌표 리스트 반환.

- **핵심 코드 골격**:
  
  ```python
  import os, requests
  
  def build_costing_options(profile: dict) -> dict:
      m = {
          "class_factors": {k: float(v) for k, v in profile["class_factors"].items()},
          "use_highways": profile.get("use_highways", 0.0),
          "use_tolls": profile.get("use_tolls", 0.0),
      }
      # Phase 0 에서 확정한 정확한 키명으로 교체할 것
      for k in ("curvature_penalty", "long_bridge_penalty",
                "long_tunnel_penalty", "bridge_length_threshold_m"):
          if k in profile:
              m[k] = profile[k]
      return {"motorcycle": m}
  
  def route(origin, dest, profile, base_url=None):
      base_url = base_url or os.environ["VALHALLA_URL"]
      body = {
          "locations": [
              {"lat": origin[0], "lon": origin[1]},
              {"lat": dest[0],   "lon": dest[1]},
          ],
          "costing": "motorcycle",
          "costing_options": build_costing_options(profile),
      }
      r = requests.post(f"{base_url}/route", json=body, timeout=30)
      r.raise_for_status()
      data = r.json()
      leg = data["trip"]["legs"][0]
      coords = decode_polyline(leg["shape"], precision=6)   # ★ 6
      summary = data["trip"]["summary"]
      return {"coords": coords,
              "distance_km": summary["length"],
              "time_s": summary["time"]}
  
  def decode_polyline(encoded: str, precision: int = 6):
      # Valhalla 표준 디코더 (precision 6 = 1e6)
      inv = 10 ** precision
      decoded, prev = [], [0, 0]
      i = 0
      while i < len(encoded):
          for j in range(2):
              shift, result = 0, 0
              while True:
                  b = ord(encoded[i]) - 63; i += 1
                  result |= (b & 0x1f) << shift; shift += 5
                  if b < 0x20: break
              prev[j] += ~(result >> 1) if (result & 1) else (result >> 1)
          decoded.append([prev[0] / inv, prev[1] / inv])  # [lat, lon]
      return decoded
  ```

- **검증** (지도 연동 전, CLI로 먼저):
  
  ```bash
  python -c "from core.config import load_config; from core.valhalla_client import route; \
  c=load_config(); r=route((37.5547,126.9706),(37.5306,127.3214),c['profiles']['rural']); \
  print(r['distance_km'],'km', len(r['coords']),'pts'); print(r['coords'][0], r['coords'][-1])"
  ```
  
  → 좌표가 한국 영역(lat 37대, lon 126~127대)에 들어오면 precision 정상.

- **로그**: 실패 시 `r.status_code`, `r.text[:500]` 출력. (Valhalla 422 = costing_options 형식 오류)

---

### ☐ Phase 4 — Streamlit 레이아웃 골격 (app.py)

- **목표**: 좌(입력+모바일 비율 지도 placeholder) / 우(슬라이더 패널) 2단 레이아웃.
- **작업**:
  
  ```python
  import streamlit as st
  st.set_page_config(page_title="Yurunavi Tuning", layout="wide")
  left, right = st.columns([5, 4], gap="medium")
  with left:
      st.subheader("경로")
      # 출발/목적지 입력 (number_input lat/lon)
      st.markdown("---")
      st.subheader("지도")
      # 모바일 비율 컨테이너 (Phase 6에서 지도 삽입)
  with right:
      st.subheader("가중치")
      # Phase 5 파라미터 패널
  ```
- **모바일 비율**: 지도 컨테이너를 폰 비율로 고정 (예 9:19.5). components.html 의 height를
  width 대비 비율로 지정 (예 width 360 → height 780).
- **검증**: `streamlit run app.py` → 빈 2단 화면 렌더.
- **로그**: 브라우저 콘솔 + 터미널 streamlit 로그.

---

### ☐ Phase 5 — 파라미터 패널 (우측, +/- 와 직접입력)

- **목표**: 프로파일별 가중치를 +/- 와 직접입력으로 조절, 값은 session_state 보관.
- **위젯 선택**: `st.number_input` 사용 — **이미 +/- 스테퍼 + 직접 타이핑** 둘 다 제공.
  필요하면 coarse 조절용 `st.slider` 를 같은 키로 병행. (위젯 키 충돌 주의)
- **구조**:
  - `st.tabs(["rural","provincial","national"])` 로 프로파일 분리
  - 각 탭: RoadClass 0~7 `class_factors` 8개 + curvature/bridge/tunnel penalty number_input
  - 모든 값은 `st.session_state["params"]` (dict) 에 반영. **위젯 조작만으로 라우팅 호출하지 말 것.**
- **검증**: 값 바꾸면 session_state 갱신, "경로 테스트" 전까지 네트워크 호출 0.
- **로그**: (디버그) 현재 params dict를 expander로 표시.

---

### ☐ Phase 6 — MapLibre 지도 임베드 (components/maplibre_map.html)

- **목표**: 마스터 tileserver 스타일로 앱과 동일 룩, polyline GeoJSON 렌더, 경로에 fit-bounds.
- **작업**:
  - `maplibre_map.html`: CDN `maplibre-gl@4.x`, `style` = `TILESERVER_STYLE_URL`,
    sources 로 `routes` (GeoJSON FeatureCollection) 주입, `map.fitBounds(bbox)`.
  - app.py 에서 `st.components.v1.html(html_str, height=780)` 로 삽입.
  - 좌표는 `[lon, lat]` 순서 (GeoJSON 규약 — Valhalla 디코더는 [lat,lon] 반환하므로 **뒤집어야 함**).
- **검증**: 더미 polyline 1개를 한국 좌표로 넣고 화면에 선이 보이는지.
- **로그**: 브라우저 콘솔에서 MapLibre `error` 이벤트 listen → 스타일/타일 URL 도달 실패 확인.

---

### ☐ Phase 7 — 버튼 → 저장 → 라우팅 → 렌더 결선

- **목표**: "경로 테스트" 클릭 시 yaml 저장 + 선택 프로파일 라우팅 + 지도 갱신 + 지표 표시.
- **작업**:
  - `if st.button("경로 테스트"):` → `save_config()` → `route()` → GeoJSON 조립 → 지도 재렌더.
  - 지표 패널: 거리(km), 예상시간, (Phase 8) 도로등급 분포.
  - `time_fallback_multiplier` 위반 시 경고 배지 (hard_constraints).
- **검증**: 슬라이더 변경 → 버튼 → 지도 경로 갱신 확인. class_factors[2](primary) 크게 올리면
  경로가 국도를 회피하는지 육안 확인.
- **로그**: 호출한 costing_options 전체를 expander(JSON)로 출력 → A/B 비교 가능하게.

---

### ☐ Phase 8 — 3-프로파일 동시 오버레이 + 도로등급 지표

- **목표**: 시골/지방도/국도 3색 경로 동시 렌더 → Seoul–Paldang 차별화 육안 진단.
- **작업**:
  - 3개 프로파일을 **순차 3회** `route()` 호출 (병렬 호출 아님; 단순/안전 우선).
  - GeoJSON 에 profile별 color 속성, MapLibre `line-color: ["get","color"]`.
  - `core/metrics.py`: 각 경로 shape → `/trace_attributes` POST →
    edge별 `road_class` 집계 → primary/secondary/tertiary % 표.
    (메모리 기준: rural 경로는 primary 0% / tertiary ~70% 가 정상 신호)
- **검증**: 3색 경로가 시각적으로 분리되는지. rural vs provincial 이 동일 경로로 붙으면
  → 차별화 실패 → class_factors 조정 대상 식별.
- **로그**: 프로파일별 도로등급 % 를 chart/표로.

---

### ☐ Phase 9 (선택) — Rust 서버 프로덕션 패리티

- **목표**: 튜닝 결과를 실제 앱 경로에 반영.
- **주의**: 이건 **Rust 코드 1회 수정**이 필요 → 마스터의 "코드 무수정" 원칙과 충돌하므로
  **별도 결정 사항**. 대시보드 v1 검증 후에만 착수.
- **작업(개요)**: `yurunavi_server` 가 `routing_config.yaml` 을 읽어 3 프로파일 costing_options
  를 구성하도록 수정 → 대시보드 yaml = 프로덕션 single source-of-truth.
- **검증**: 동일 출발/목적지로 대시보드 결과 == Rust 8003 결과 (거리·shape 일치).
- **STOP**: 착수 전 마스터 승인 필요.

---

### ☐ Phase 10 — Docker 패키징

- **Dockerfile**:
  
  ```dockerfile
  FROM python:3.11-slim
  WORKDIR /app
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  COPY . .
  EXPOSE 8501
  CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
  ```
- **docker-compose.yml**:
  
  ```yaml
  services:
    tuning-dashboard:
      build: .
      container_name: yurunavi-tuning-dashboard
      env_file: .env
      network_mode: host        # localhost:8002(Valhalla) 직접 접근 위해
      volumes:
        - ./routing_config.yaml:/app/routing_config.yaml
      restart: unless-stopped
  ```
  
  > `network_mode: host` 로 컨테이너에서 `localhost:8002` 직통. (host 미지원 환경이면
  > VALHALLA_URL 을 `http://host.docker.internal:8002` 로, extra_hosts 추가.)
- **실행/검증**:
  
  ```bash
  docker compose up -d --build
  docker compose logs -f tuning-dashboard   # 부팅 로그
  curl -sI http://localhost:8501            # 200 확인
  ```

---

## 4. 흔한 함정 (반드시 점검)

- ☐ **polyline precision**: Valhalla=6. 5로 디코드 시 좌표 10배 어긋남.
- ☐ **GeoJSON 좌표 순서**: `[lon, lat]`. Valhalla 디코더는 `[lat, lon]` 반환 → 뒤집기.
- ☐ **Streamlit rerun 모델**: 위젯 조작마다 스크립트 전체 재실행. 라우팅은 **버튼 클릭 시에만**.
  
      값은 session_state, 위젯 key 와 session_state 동시 대입 시 예외 주의.
- ☐ **MapLibre 스타일 URL**: style.json 내부의 tiles/glyphs/sprite URL 이 **절대경로**이고
  
      브라우저에서 도달 가능해야 함 (tiles.westinx.com). 상대경로면 타일이 안 뜸.
- ☐ **costing_options 키명**: Phase 0 grep 결과로만 확정. 틀린 키는 fork가 조용히 무시 →
  
      슬라이더 움직여도 경로 불변 = 키명 오류 신호.
- ☐ **컨테이너→localhost**: docker bridge 네트워크면 localhost:8002 안 닿음. host 네트워크 사용.
- ☐ **422 응답**: costing_options 구조/타입 오류. 로그에 `r.text` 찍어 원인 확인.

---

## 5. 진행 규칙

- 한 Phase = 한 커밋, 단일 파일 스코프 우선.
- Phase 0 와 Phase 9 는 **STOP 게이트** — 마스터 확인 후 진행.
- 각 Phase 끝에 검증 명령 출력 + 통과 여부를 보고.
- 추측으로 파라미터 키/범위를 채우지 말 것 → Phase 0 산출물에 근거.
