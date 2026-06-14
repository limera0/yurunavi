# RECON: 포크 패치 #2 신호

작성: 2026-06-07, 읽기전용. 소스: /data/projects/valhalla-src HEAD 72f459fc5 (3.7.0)

---

## 1. 곡률 신호

**`curvature()` 존재함.**

```cpp
// valhalla/baldr/directededge.h:224-230
/**
 * Get the road curvature factor.
 * @return  Returns the curvature factor (0-15).
 */
uint32_t curvature() const {
  return curvature_;
}
```

- 저장: `uint64_t curvature_ : 4;` — directededge.h:1279 (4비트, 0~15)
- 반환 타입: `uint32_t`

**값 범위·의미** (`src/mjolnir/util.cc:476-504`):
- 계산: 형상점 3개씩 슬라이딩하여 곡률반경 `radius` 산출 → `score = 1500 / radius` (radius > 1000m이면 0), 최대 25로 cap → 평균 → 0~15로 클램프
- **0 = 직선** (형상점 2개 or radius > 1000m 전부)
- **15 = 매우 굽음** (반경 100m 수준 연속 커브)
- 고속 직진 도로(317번 구간) = curvature 0~2 예상
- 시골길/임도 = curvature 8~15 예상

→ **직진 페널티 구현 가능**: `edge->curvature()`를 직접 사용해 "직선(0~N) → 페널티, 곡선(M~15) → 보너스" 형태로 구현 가능.

---

## 2. bridge / tunnel / length

```cpp
// valhalla/baldr/directededge.h:166-168
uint32_t length() const {
  return length_;
}
// 단위: 미터

// valhalla/baldr/directededge.h:309-311
bool tunnel() const {
  return tunnel_;
}

// valhalla/baldr/directededge.h:323-325
bool bridge() const {
  return bridge_;
}
```

- `length()` 반환 타입: `uint32_t` (미터)
- `bridge()` 반환 타입: `bool`
- `tunnel()` 반환 타입: `bool`

→ **고가 페널티**: `edge->bridge() == true`이면 `factor *= bridge_penalty_` 패턴으로 직접 구현 가능.
→ `edge->length()`는 EdgeCost 내부에서 이미 `sec` 계산에 사용 중(L423). 동일 스코프에서 접근 가능.

---

## 3. 속도

### EdgeCost의 속도 취득 (`src/sif/motorcyclecost.cc:416-423`)

```cpp
auto edge_speed = fixed_speed_ == baldr::kDisableFixedSpeed
                      ? tile->GetSpeed(edge, flow_mask_, time_info.second_of_week, false,
                                       &flow_sources, time_info.seconds_from_now)
                      : fixed_speed_;

auto final_speed = std::min(edge_speed, top_speed_);

float sec = (edge->length() * kSpeedFactor[final_speed]);
```

- `edge_speed`: 타일에서 실제/예측 속도 취득 (uint8_t, kph 단위)
- `final_speed`: `min(edge_speed, top_speed_)` → 시간 계산에 사용
- `kSpeedFactor[s] = (3600 * 0.001) / s` → 초/미터 단위 (dynamiccost.h:210-219)

### SpeedPenalty 로직 (`valhalla/sif/dynamiccost.h:1162-1180`)

```cpp
float SpeedPenalty(const baldr::DirectedEdge* edge,
                   const baldr::graph_tile_ptr& tile,
                   const baldr::TimeInfo& time_info,
                   uint8_t flow_sources,
                   float edge_speed) const {
  float average_edge_speed = edge_speed;
  // 현재 속도 레이어는 페널티 제외, 평활화된 속도 사용
  if (top_speed_ != baldr::kMaxAssumedSpeed && (flow_sources & baldr::kCurrentFlowMask)) {
    average_edge_speed =
        tile->GetSpeed(edge, flow_mask_ & (~baldr::kCurrentFlowMask), time_info.second_of_week);
  }
  float speed_penalty = (average_edge_speed > top_speed_)
                            ? (average_edge_speed - top_speed_) * speed_penalty_factor_
                            : 0.0f;
  return speed_penalty;
}
```

- **의미**: `edge_speed > top_speed_` 일 때 초과분 × `speed_penalty_factor_`(기본 0.05)를 `factor`에 **가산**
- 기본값(`speed_penalty_factor_ = 0.05`)에서 효과 미미: 120kph 도로에서 top_speed=80이면 페널티 = (120-80)×0.05 = 2.0 — 무시 못 할 수준이나 실제 라우팅 영향은 작음
- **top_speed의 이중 효과**:
  - 시간(sec): `final_speed = min(edge_speed, top_speed_)` → 고속 도로라도 top_speed로 캡핑된 시간 계산
  - 비용(factor): SpeedPenalty로 가산 페널티 → `factor`에 영향, 즉 **경로 선택에 영향**
  - ⚠️ 단, SpeedPenalty는 top_speed가 `kMaxAssumedSpeed`(=253)일 때 완전 비활성화

### top_speed가 비용에 영향하는가?

- **YES, 비용(경로 선택)에 영향**: `factor += SpeedPenalty(...)` (motorcyclecost.cc:438) — factor는 최종 Cost의 비용 부분(time × factor)에 곱해짐
- **YES, 시간에도 영향**: `sec = length * kSpeedFactor[final_speed]` (L423) — final_speed가 top_speed로 캡핑됨
- 결론: top_speed를 낮추면 고속 도로에 SpeedPenalty가 추가되어 **우회 유도 가능**. 단 기본 speed_penalty_factor(0.05)가 작으므로 강한 우회를 원하면 factor 자체를 직접 건드리는 게 확실.

---

## 4. 주입 지점

**`class_factor_` 주입 줄 현재 위치**: `src/sif/motorcyclecost.cc:455`

```cpp
// motorcyclecost.cc:455-458
  factor *= class_factor_[static_cast<uint32_t>(edge->classification())];
  factor *= EdgeFactor(edgeid);

  return {sec * factor, sec};
```

**같은 스코프(EdgeCost 함수 내)에서 접근 가능한 속성**:

| 속성 | 접근 방법 | 확인 줄 |
|------|----------|--------|
| `classification()` | `edge->classification()` | L436, L455 (사용 중) |
| `curvature()` | `edge->curvature()` | 접근자 존재, EdgeCost 내 미사용 |
| `bridge()` | `edge->bridge()` | 접근자 존재, EdgeCost 내 미사용 |
| `tunnel()` | `edge->tunnel()` | 접근자 존재, EdgeCost 내 미사용 |
| `length()` | `edge->length()` | L423 (sec 계산에서 이미 사용) |
| `edge_speed` | L416-419 취득된 지역변수 | L438에서 SpeedPenalty 인자로 전달 |

→ **모든 신호가 동일 스코프에서 접근 가능**. 새 페널티(bridge/curvature/속도)를 L455 인근에 같은 패턴으로 추가 가능.

---

## 5. proto 다음 필드번호

현재 `Costing.Options` 마지막 필드: `map<uint32, float> class_factors = 97;` (우리가 추가, options.proto:360)

→ **다음 가용 필드번호: 98~**

새 파라미터 예시:
- `float curvature_factor = 98;` — 직진 페널티 강도
- `float bridge_factor = 99;` — 고가도로 배수
- 등

---

## 6. 종합

### ✅ 직진 페널티 구현 경로

`edge->curvature()` (uint32_t 0~15) 직접 사용 가능.

구현 예시:
```cpp
// curvature 0(직선)=페널티, 15(곡선)=보너스
// ex: factor *= (1.0 + curvature_weight_ * (8 - edge->curvature()) / 8.0f)
// → curvature=0 직선: 최대 페널티, curvature=8: 중립, curvature=15: 보너스
```

- 속도 대리지표도 가능(edge_speed > 임계값 → 직진 판단)이나 curvature 직접 접근이 더 정확.

### ✅ 고가 페널티 구현 경로

`edge->bridge()` (bool) 직접 사용 가능.

구현 예시:
```cpp
if (edge->bridge()) {
  factor *= bridge_factor_;  // 생성자에서 proto bridge_factor 읽어 초기화
}
```

- 단순 bool이므로 `factor *=` 또는 `factor +=` 둘 다 가능.
- `edge->length()`와 조합해 "짧은 교량은 허용, 긴 고가(>300m)만 페널티" 로직도 가능.

### ✅ 속도 페널티 구현 경로

기존 `SpeedPenalty()`가 이미 `top_speed` 초과분을 factor에 가산하므로 **중복 없이 별도 추가 가능**.

- 기존 SpeedPenalty는 `edge_speed > top_speed_` 조건부, 새 속도 페널티는 절대값(예: edge_speed > 80kph) 기준으로 분리 가능.
- 충돌 없음. L438 SpeedPenalty 직후, L455 class_factor 주입 직전 인근에 추가.

### ❓ 미확인 / ⚠️ 주의점

1. **curvature 실제 분포 미확인**: 한국 OSM 타일에서 317번 국도의 curvature 실값 미검증. `/trace_attributes` API로 실제 엣지 curvature를 사전 확인 권장.
2. **bridge vs 고가도로**: Valhalla의 `bridge()` 플래그가 OSM `bridge=yes`에서 온다면 한국 317번 고가 구간이 실제로 `bridge=yes`로 태깅됐는지 확인 필요. 미태깅 시 bridge 페널티 무효.
3. **speed_penalty_factor 파라미터화**: 기존 `speed_penalty_factor_`는 `DynamicCost`의 proto 필드 `speed_penalty_factor = 95` 에 이미 존재 (`Costing.Options:354-356`). Motorcycle costing에서도 `ParseBaseCostOptions()`를 통해 이미 파싱됨 — 앱에서 `speed_penalty_factor` 값만 올려도 기존 코드로 속도 페널티 강화 가능. **신규 C++ 구현 없이 앱 파라미터 조정만으로 시험해볼 수 있음.**
4. **top_speed 현재 동작 재확인**: 국도 코스에서 `shortest: true`가 켜져 있으면 `factor`가 아예 무시됨(motorcyclecost.cc:425-427). speed_penalty/curvature 페널티도 shortest 모드에서는 효과 없음.
