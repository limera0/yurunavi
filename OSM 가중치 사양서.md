# 유루나비(YuruNavi) 라우팅 엔진 구축을 위한 OSM 태그 및 가중치 사양서

기존 내비게이션의 최단 거리/최단 시간 알고리즘(Dijkstra/A*)을 그대로 사용할 경우, 동탄신도시 사례처럼 "거리상 가깝고 태그 등급이 낮은 도시 내부 이면도로"를 시골길로 오인하여 진입시키는 논리적 오류가 발생합니다.

오토바이 투어러의 감성적 요구(숲길, 와인딩, 여유로움)를 수치화하고 제어하기 위한 OpenStreetMap(OSM) 기반의 라우팅 필터링 및 가중치(Weighting) 설계 매트릭스입니다.

## 1. 글로벌 진입 금지 필터 (이륜차 제한 적용)

라우팅 계산 전, 국내 도로법 및 이륜차 통행 제한을 고려하여 아래 태그를 가진 세그먼트는 라우팅 그래프에서 완전히 배제(Hard Exclusion)합니다.

YAML

```
# 고속도로 및 자동차전용도로 배제
highway: motorway
highway: motorway_link
motorroad: yes

# 자전거 전용도로 및 보행자 전용도로 배제 (네이버 자전거길 보완)
highway: cycleway
bicycle: designated
footway: designated
motor_vehicle: no
vehicle: no
```

## 2. 세부 코스별 OSM 태그 매핑 및 가중치(Weight) 매트릭스

> **가중치 원칙:** 가중치 값이 **1.0 미만이면 선호(비용 감소)**, **1.0 초과면 기피(비용 증가)**로 연산합니다. 속도 대신 '주행 경험 비용'을 기준으로 산정합니다.

### 1) 시골길로 느긋하게 (Rural Profile)

- **목적:** 숲속길, 좁은 길, 교통량이 적은 리도/농도 중심 구성. 도시 격자형 도로 차단.

- **핵심 로직:** `tertiary` 이하 도로 우대, `trunk` 극단적 기피. 곡률(Curvature) 가중치 대폭 반영.

### 2) 지방도로 여유롭게 (Provincial Profile)

- **목적:** 와인딩이 포함된 한적한 지방도 중심.

- **핵심 로직:** `primary`(지방도 범위), `secondary` 우대. 직선 위주 대형 국도 기피.

### 3) 국도로 빠르게 (National Profile)

- **목적:** 흐름이 빠른 일반국도 중심의 쾌적한 주행. 지방도는 연결 용도로만 최소한으로 혼용.

- **핵심 로직:** `trunk`(일반국도) 우대, 신호등 및 교차로 패널티 최소화.

| **OSM Highway Tag**            | **도로 종류 (한국 기준)**   | **시골길로 느긋하게**          | **지방도로 여유롭게**          | **국도로 빠르게**            |
| ------------------------------ | ------------------- | ---------------------- | ---------------------- | ---------------------- |
| `trunk` / `trunk_link`         | **일반국도** (1~2자리)    | 패널티 최고 ($W = 5.0$)     | 패널티 높음 ($W = 2.0$)     | **최우선 선호 ($W = 0.5$)** |
| `primary` / `primary_link`     | **지방도/국지도** (3~4자리) | 국지도 기피 ($W = 1.5$)     | **최우선 선호 ($W = 0.7$)** | 조건부 허용 ($W = 1.0$)     |
| `secondary`                    | **시군도** (주요 간선)     | 조건부 허용 ($W = 1.0$)     | 선호 ($W = 0.8$)         | 패널티 ($W = 1.5$)        |
| `tertiary`                     | **집산도로** (면도/이동로)   | **선호 ($W = 0.6$)**     | 패널티 ($W = 1.2$)        | 패널티 높음 ($W = 2.5$)     |
| `unclassified` / `residential` | **소로/시골길/농도**       | **최우선 선호 ($W = 0.4$)** | 패널티 높음 ($W = 2.0$)     | 진입 금지 수준 ($W = 10.0$)  |

## 3. 핵심 가치 구현을 위한 공간 데이터 연산 로직

### 1) 신도시/도심지 관통 방지 논리 (동탄신도시 오류 해결)

단순히 태그 등급만 낮추면 도시 내부 이면도로를 시골길로 판단합니다. 이를 방지하기 위해 **교차로 밀도 패널티** 또는 **Landuse 필터**를 결합해야 합니다.

- **교차로 밀도 연산:** 단위 거리(예: 500m) 내에 `highway=traffic_signals` 또는 다른 도로와의 교차점(`junction`)이 3개 이상 존재할 경우, 해당 세그먼트의 가중치를 무조건 $W \times 3.0$배 적용하여 우회시킵니다.

- **토지 피복 적용:** OSM의 `landuse=residential`, `landuse=commercial` 영역 내부에 존재하는 소로는 시골길 프로필에서 제외합니다.

### 2) 숲속길 및 경치 좋은 길 검출 (`natural=wood` 시각화 연산)

- 알고리즘 내부적으로 도로 세그먼트 좌우 50m 이내에 OSM `natural=wood`(숲), `landuse=forest`(산림), `natural=water`(강/호수) 폴리곤이 인접해 있는지 공간 연산(Spatial Join)을 수행합니다.

- 인접한 경우, 시골길 및 지방도 프로필에서 해당 세그먼트 비용을 추가로 **20% 감면($W \times 0.8$)** 처리하여 숲길로 경로를 유도합니다.

### 3) 와인딩(곡률) 계수 산정

도로의 실제 궤적 길이($L$)와 시작점-끝점의 직선거리($C$)를 비교하여 곡률 수치(Tortuosity)를 계산합니다.

$$\text{곡률 계수} (\tau) = \frac{L}{C}$$

- **지방도로 여유롭게:** $\tau \ge 1.3$ 이상인 구불구불한 `primary`, `secondary` 도로에 가중치 인센티브를 부여합니다.

- **국도로 빠르게:** $\tau \approx 1.0$에 가까운 직선형 구조를 최우선합니다.

## 4. 동적 배합 및 현실적 ETA 보정 알고리즘

### 1) 시골길 1.3배 초과 시 지방도 동적 배합 루틴 (Dynamic Fallback)

1. 최초에 **'시골길로 느긋하게'** 가중치 맵을 기준으로 최적 경로($R_{\text{rural}}$)와 예상 소요 시간($T_{\text{rural}}$)을 계산합니다.

2. 동일 구간의 **'지방도로 여유롭게'** 경로의 시간($T_{\text{prov}}$)을 가져와 비교합니다.

3. 조건 검증:
   
   $$\frac{T_{\text{rural}}}{T_{\text{prov}}} \ge 1.3$$

4. 위 조건이 성립할 경우, 알고리즘은 전체 경로 중 이동 효율이 가장 떨어지는 하위 30%의 시골길 세그먼트를 탐색하여, 해당 구간만 `primary` 또는 `secondary` 도로 가중치를 완화($W = 1.0$)하여 다시 라우팅을 수행합니다. 이 루틴을 비율이 1.3 미만으로 떨어질 때까지 반복 피드백합니다.

### 2) 이륜차 전용 현실적 ETA 보정

현재 유루나비 화면상의 ETA(79km에 1시간 26분 $\rightarrow$ 평속 약 55km/h)는 신호 대기 및 시골길의 좁은 도로 폭이 반영되지 않은 자동차 기준 표준 속도 데이터 파싱 오류입니다.

- **보정 메커니즘:** 라우팅 엔진(Valhalla 또는 OSRM)의 `maxspeed` 기본값을 무시하고, 이륜차 주행 특성을 반영한 프로필별 기본 실효 평속(Default Effective Speed)을 강제 지정합니다.
  
  - `unclassified` / `residential` (시골길 구간): 30km/h 고정
  
  - `tertiary` / `secondary` (소형 도로): 45km/h 고정
  
  - `primary` (지방도 구간): 55km/h 고정
  
  - `trunk` (국도 구간): 70km/h 고정

- 이 실효 평속 플랫값을 기준으로 소요 시간을 재산출하면, 네이버 지도와 유사한 현실적인 오토바이 투어링 시간(71km 기준 약 1시간 50분~2시간)이 산출됩니다.





## Rust 레이어에서 전송하는 JSON `costing_options`의 튜닝



데스크탑 PC의 우분투 환경에서 Valhalla와 Rust 조합을 선택한 것은 로컬 인프라의 처리 성능을 극대화하고, C++ 기반 엔진의 가벼운 메모리 풋프린트를 활용할 수 있는 가장 직관적이고 강력한 엔지니어링 접근입니다.

Valhalla는 **Dynamic Costing(런타임 가중치 연산)** 방식을 취하므로, 타일 데이터를 매번 새로 구울 필요 없이 Rust 레이어에서 전송하는 JSON `costing_options`를 정교하게 튜닝하는 것만으로 핵심 로직을 온전히 구현할 수 있습니다.

## 1. Valhalla 내부 매핑 구조 이해

Valhalla는 OSM의 `highway` 태그를 파싱할 때 내부적으로 Functional Class (FC1 ~ FC5)라는 5단계 도로 계층 구조로 변환하여 타일에 저장합니다.

- **FC1:** `motorway` (대한민국 고속도로)

- **FC2:** `trunk` (일반 국도)

- **FC3:** `primary` (지방도 및 주요 국지도)

- **FC4:** `secondary` (시군도 및 주요 간선)

- **FC5:** `tertiary`, `unclassified`, `residential` (시골길, 이면도로, 농도)

우리가 설계한 사양서를 구현하려면 Valhalla의 `motorcycle` 또는 `auto` 프로필을 기반으로 이 FC 등급별 `class_factor`를 동적으로 제어해야 합니다.

## 2. 프로필별 Valhalla JSON `costing_options` 사양

Rust 어플리케이션에서 Valhalla API(또는 FFI 라이브러리)로 경로를 요청할 때 컨텍스트에 따라 아래 JSON 페이로드를 바인딩하여 요청합니다.

### 1) 시골길로 느긋하게 (Rural Profile)

국도 및 지방도를 극도로 기피하고, 곡률이 높으며 도심지가 아닌 지역의 소로(FC5)를 최우선으로 탐색하도록 유도합니다.

JSON

```
{
  "costing": "motorcycle",
  "costing_options": {
    "motorcycle": {
      "use_highways": 0.0,
      "use_living_streets": 0.5,
      "use_tracks": 1.0,
      "curviness": 1.0,
      "class_factors": {
        "1": 100.0,
        "2": 5.0,
        "3": 2.5,
        "4": 1.0,
        "5": 0.2
      },
      "urban_penalty": 50.0
    }
  }
}
```

> `urban_penalty` 값을 높이면 Valhalla가 타일 내 노드 밀도가 높은 도심지(동탄신도시 내부 등)를 통과할 때 막대한 비용을 부과하여 자동으로 외곽 시골길로 우회시킵니다.

### 2) 지방도로 여유롭게 (Provincial Profile)

지방도(FC3)와 시군도(FC4)를 선호하며, 적당한 곡률을 가진 와인딩 코스를 찾아가도록 세팅합니다.

JSON

```
{
  "costing": "motorcycle",
  "costing_options": {
    "motorcycle": {
      "use_highways": 0.0,
      "curviness": 0.8,
      "class_factors": {
        "1": 100.0,
        "2": 2.0,
        "3": 0.5,
        "4": 0.7,
        "5": 1.5
      }
    }
  }
}
```

### 3) 국도로 빠르게 (National Profile)

흐름이 빠른 일반국도(FC2)를 쾌적하게 타되, 대한민국 법상의 오토바이 고속도로 진입 금지 규칙(FC1 제한)을 엄격히 고수합니다.

JSON

```
{
  "costing": "motorcycle",
  "costing_options": {
    "motorcycle": {
      "use_highways": 0.0,
      "curviness": 0.1,
      "class_factors": {
        "1": 100.0,
        "2": 0.4,
        "3": 1.0,
        "4": 2.0,
        "5": 10.0
      }
    }
  }
}
```

## 3. 고급 요구사항의 기술적 해결책 (숲속길 & ETA 보정)

### 1) 숲속길 (`natural=wood`) 탐색 방식의 한계와 극복

Valhalla의 런타임 다이내믹 코스팅 엔진은 연산 속도를 위해 도로 에지 주변의 폴리곤(숲, 호수 등)을 실시간으로 공간 연산(Spatial Join)하지 않습니다.

- **해결책:** 타일을 빌드하는 `mjolnir` 단계에서 **Lua 프로필 스크립트를 수정**해야 합니다. OSM 데이터 파싱 시 주변에 `natural=wood`나 `landuse=forest`가 인접한 도로 세그먼트가 발견되면, 해당 에지에 Valhalla가 인식할 수 있는 커스텀 플래그나 속성(예: 특정 `surface` 태그 유도 또는 드물게 사용되는 주행 특성 변수)을 강제로 인코딩해 넣은 뒤, 런타임에 이를 저비용으로 읽어와 가중치를 감면 처리합니다.

### 2) 이륜차 현실적 ETA 보정

Valhalla 엔진 내부 C++ 코드(`sif/motorcyclecost.cc`) 혹은 JSON 옵션 내에서 각 도로 등급별 최대 허용 속도(`top_speed`)를 강제로 하향 조정해야 비현실적인 도착 예정 시간이 현실화됩니다.

JSON

```
// 각 등급별 평속 상한선을 물리적으로 제한하여 ETA 현실화
"top_speed": 60,
"fixed_speed_class": {
  "2": 65,
  "3": 50,
  "4": 40,
  "5": 25
}
```

## 4. Rust 레이어에서의 동적 배합 및 1.3배 알고리즘 구현

"시골길로 느긋하게 가되, 시간이 1.3배 이상 늘어지면 지방도를 섞는다"는 논리는 Valhalla 내부가 아닌 **Rust 비즈니스 로직 레이어**에서 제어해야 가장 깔끔합니다. Rust의 비동기 런타임(`tokio`)을 활용해 두 경로를 동시에 연산한 뒤 피드백 루프를 돌리는 아키텍처입니다.

Rust

```
use serde_json::json;
use reqwest::Client;

async fn calculate_yurunavi_route(client: &Client, start: (f64, f64), end: (f64, f64)) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let url = "http://localhost:8002/route";

    // 1. 시골길 프로필과 지방도 프로필 경로를 동시에 비동기로 요청 (Concurrency 확보)
    let rural_payload = json!({ "locations": [{"lat": start.0, "lon": start.1}, {"lat": end.0, "lon": end.1}], "costing": "motorcycle", "costing_options": { "motorcycle": { "class_factors": { "2": 5.0, "3": 2.5, "5": 0.2 } } } });
    let prov_payload = json!({ "locations": [{"lat": start.0, "lon": start.1}, {"lat": end.0, "lon": end.1}], "costing": "motorcycle", "costing_options": { "motorcycle": { "class_factors": { "2": 2.0, "3": 0.5, "5": 1.5 } } } });

    let rural_fut = client.post(url).json(&rural_payload).send();
    let prov_fut = client.post(url).json(&prov_payload).send();

    let (rural_res, prov_res) = tokio::try_join!(rural_fut, prov_fut)?;

    let rural_json: serde_json::Value = rural_res.json().await?;
    let prov_json: serde_json::Value = prov_res.json().await?;

    let t_rural = rural_json["trip"]["summary"]["time"].as_f64().unwrap_or(1.0);
    let t_prov = prov_json["trip"]["summary"]["time"].as_f64().unwrap_or(1.0);

    // 2. 조건 검증: 시골길이 지방도보다 1.3배 이상 느린가?
    if t_rural / t_prov >= 1.3 {
        // 3. 밸런스 조정 루틴 트리거: 시골길 가중치를 살짝 강화하여 지방도를 일부 혼용하도록 재수행
        let balanced_payload = json!({
            "locations": [{"lat": start.0, "lon": start.1}, {"lat": end.0, "lon": end.1}],
            "costing": "motorcycle",
            "costing_options": {
                "motorcycle": {
                    "class_factors": {
                        "2": 4.0, 
                        "3": 1.2, // 지방도 페널티를 완화하여 자연스럽게 간선도로로 합류 유도
                        "5": 0.5  
                    }
                }
            }
        });
        let balanced_res = client.post(url).json(&balanced_payload).send().await?;
        return Ok(balanced_res.json().await?);
    }

    Ok(rural_json)
}
```

현재 우분투 서버 환경에서 Valhalla 타일 데이터를 빌드할 때 별도의 커스텀 Lua 스크립트를 사용하고 계신가요, 아니면 기본 제공되는 `mjolnir` 인프라를 그대로 사용 중이신가요?
