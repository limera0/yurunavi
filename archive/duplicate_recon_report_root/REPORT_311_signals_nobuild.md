# REPORT: 311번 동부대로 신호 검증 (무빌드)

작성: 2026-06-07
검증 환경: valhalla-fork:5ed7267b-classfactors (포트 8012), 운영 타일 읽기전용 공유

---

## 목적

311번 지방도 "동부대로"(팔당 남쪽, 고속 직진 고가 구간)의 실제 엣지 속성을 확인하고,
현재 포크(class_factors)로 회피가 되는지, speed_penalty_factor/bridge/tunnel 페널티가 추가로 필요한지 판단.

---

## STEP A — 311번 동부대로 실제 속성

검증 구간: (37.211684, 127.088534) → (37.261063, 127.092697)
API: `/locate` verbose=true, 7개 샘플 포인트

| lat | classification | bridge | tunnel | speed(kph) | curvature | length(m) |
|-----|---------------|--------|--------|------------|-----------|-----------|
| 37.2117 | **trunk** | False | False | 73 | **0** | 346 |
| 37.218  | **trunk** | **True**  | False | 90 | **0** | 1400 |
| 37.225  | **trunk** | **True**  | False | 90 | **0** | 1400 |
| 37.232  | **trunk** | False | False | 90 | **0** | 383 |
| 37.240  | **trunk** | False | **True**  | 90 | **0** | 813 |
| 37.250  | **trunk** | **True**  | False | 90 | **0** | 1122 |
| 37.2611 | **trunk** | False | False | 73 | **0** | 157 |

OSM 이름: `['311', '동부대로']`, way_id 예시: 170308140

### 속성별 판독

- **classification = trunk(RoadClass=1) 전 구간 공통**
  - 동부대로는 secondary가 아닌 trunk로 태깅됨.
  - 현재 포크 `class_factors '1':100`이 이미 전 구간에 100배 페널티 적용 중.
  - → 동부대로 문제는 포크 배포 시점에 이미 해결됨.

- **curvature = 0 전 구간**
  - 완전 직선. 곡률 페널티 신호로 잡힘.
  - secondary급 직진 고속 도로(trunk 미태깅)까지 잡으려면 curvature 페널티 유효.

- **bridge = True**: 37.218(1.4km), 37.225(1.4km), 37.250(1.1km) — 고가 3구간
- **tunnel = True**: 37.240(0.8km) — 지하화(지중화) 구간 1곳
  - `tunnel=True`는 OSM `tunnel=yes` 태깅에서 유래. 동부대로 지하차도 확인됨.

---

## STEP B — 속도 페널티 효과 비교 (평택→팔당 OD)

출발: (37.073216, 127.047574) / 도착: (37.555107, 127.236398)
코스: 시골길 class_factors 공통 적용

| 프로필 | 거리 | 시간 | 비고 |
|--------|------|------|------|
| B1 기준 (class_factors만) | 84.69km | 108min | 현재 앱 시골길 |
| B2 top_speed=60 + spf=0.5 | 87.58km | 113min | +2.89km |
| B3 top_speed=50 + spf=1.0 | 96.52km | 137min | +11.83km |

- B2/B3 모두 B1과 거리·경로 달라짐 → speed_penalty_factor 효과 있음.
- 단, 동부대로는 이미 trunk 페널티로 B1에서도 회피 중이므로, B2/B3의 추가 거리는 다른 고속 도로 회피에 기인.

## STEP C — 동부대로 전용 OD (class_factors 유무 비교)

출발: (37.136103, 127.078254) / 도착: (37.261063, 127.092697)

| 프로필 | 거리 | 비고 |
|--------|------|------|
| C1 시골길 (`'1':100` 적용) | **16.01km** | 동부대로 회피 |
| C2 스톡 (class_factors 없음) | 14.81km | 동부대로 경유 추정 |

- C1 > C2 (+1.2km): `class_factors '1':100`이 trunk인 동부대로를 실제로 우회시키고 있음 확인.
- **동부대로 회피는 현재 포크로 이미 해결.**

---

## Underpass(지하화 도로) 탐색 결과

### 신호 확인

| 항목 | 결과 |
|------|------|
| OSM 태깅 | 동부대로 37.240 구간 `tunnel=True` 확인 (0.8km) |
| Valhalla 속성 | `edge->tunnel()` → `bool`, `directededge.h:309` |
| 전용 Use enum | **없음** — `Use::kRoad` + `tunnel=true` 조합으로만 식별 |
| 현재 motorcycle costing 반영 여부 | **미반영** (src/sif/ 전체 grep 0 hits) |
| bridge도 동일 | `edge->bridge()` 존재, 현재 미사용 |

### 포크 추가 구현 경로

```cpp
// motorcyclecost.cc EdgeCost() — class_factor_ 주입 인근 (L455)
if (edge->tunnel())
    factor *= tunnel_factor_;   // proto field = 98
if (edge->bridge())
    factor *= bridge_factor_;   // proto field = 99
```

- 생성자에서 proto map → float 초기화 (기본값 1.0 = 미적용 시 스톡 동일).
- `tunnel=true`는 OSM `tunnel=yes` 매핑. 한국 지하차도(지중화) 구간이 실제로 태깅돼 있음을 확인.
- `bridge=true`도 동일 패턴으로 고가도로 회피 가능.

---

## 종합 판정

### ✅ 동부대로(311번) 문제 — 현재 포크로 해결됨

동부대로 전 구간이 `trunk`(RoadClass=1)로 태깅됨.
`class_factors '1':100`이 이미 적용 중 → 포크 배포만으로 해결.
추가 C++ 패치 불필요.

### ✅ speed_penalty_factor — 앱 파라미터만으로 효과 확인

기존 proto 필드(`speed_penalty_factor=95`)가 이미 존재.
C++ 수정 없이 앱에서 값 조정만으로 고속 도로 추가 회피 가능.
단, 동부대로 자체는 trunk 페널티가 주 원인이므로 우선순위 낮음.

### ✅ curvature 페널티 — 포크 추가 시 유효

동부대로 `curvature=0` 확인. secondary급 직진 고속 도로(trunk 미태깅 케이스)까지 잡으려면 유효.
단, 현재 문제(동부대로)는 이미 해결됐으므로 우선순위 중간.

### ✅ tunnel/bridge 페널티 — 포크 2줄로 구현 가능

`edge->tunnel()`, `edge->bridge()` 모두 존재, 현재 motorcycle costing 미사용.
동부대로 지하구간(0.8km) `tunnel=True` 실 확인. 고가 3구간 `bridge=True` 실 확인.
구현 비용 낮음(EdgCost에 if 2개 + 생성자 초기화 + proto 필드 2개).

### ❓ 미확인 / ⚠️ 주의

- secondary급 직진 도로(trunk 미태깅)가 실제로 문제인지 미검증. 현재 앱 불만이 동부대로뿐이라면 추가 패치 불필요.
- `bridge=True` 교량 중 단순 소교량(하천 위 소로)도 포함될 수 있음 — bridge_factor를 너무 높이면 시골 소교량도 회피.
- `tunnel=True` = 지하차도뿐 아니라 산악 터널도 포함. 터널 회피가 오토바이 라이더에게 항상 바람직하지 않을 수 있음(우천 시 터널 선호 경우).

---

## 다음 단계 권고 (우선순위 순)

1. **포크 이미지 운영 교체** — 동부대로 문제는 현재 포크로 해결됨. 스쿠터 실측 후 교체.
2. **tunnel/bridge 페널티 포크 추가** — 구현 비용 낮음. 지하차도·고가 회피 옵션 추가.
3. **curvature 페널티** — secondary 미태깅 직진 도로 대비. 실측에서 문제 재현 시 추가.
4. **speed_penalty_factor 앱 파라미터 조정** — C++ 수정 없이 시험 가능. 실측 후 결정.
