# Valhalla 포크 motorcycle costing 파라미터 명세

소스: `/data/projects/valhalla-src/src/sif/motorcyclecost.cc`
Proto: `/data/projects/valhalla-src/proto/descriptors/options.proto` (field 97–100)

---

## costing_options.motorcycle 실제 파라미터 표

| param | json_key | type | min | max | default | 의미 |
|-------|----------|------|-----|-----|---------|------|
| class_factors | `class_factors` | `map<uint32, float>` | — | — | 모두 1.0 | RoadClass 0~7 각각의 비용 배율. **높을수록 해당 도로를 회피.** |
| curvature_penalty | `curvature_penalty` | float | 0.0 | 10.0 | 0.0 | 직선 도로에 페널티 → 높을수록 굽은길 선호. `factor *= (1 + penalty * straightness)` |
| long_bridge_factor | `long_bridge_factor` | float | 0.0 | 20.0 | 1.0 | span_min_length 초과 교량 비용 배율. 1.0=중립, >1=회피, <1=선호 |
| long_tunnel_factor | `long_tunnel_factor` | float | 0.0 | 20.0 | 1.0 | span_min_length 초과 터널 비용 배율. 1.0=중립, >1=회피, <1=선호 |
| span_min_length | `span_min_length` | uint32 | 0 | 5000 | 500 | 교량/터널 페널티 적용 최소 길이 (단위: 미터) |
| use_highways | `use_highways` | float | 0.0 | 1.0 | 0.5 | 고속도로 사용 선호도 (0=완전 회피, 1=적극 이용) |
| use_tolls | `use_tolls` | float | 0.0 | 1.0 | 0.5 | 유료도로 사용 선호도 |
| use_trails | `use_trails` | float | 0.0 | 1.0 | 0.0 | 비포장/트레일 사용 선호도 |

---

## class_factors 키 → RoadClass 매핑

| 키 (uint32) | RoadClass | OSM 태그 | 한국어 명칭 |
|-------------|-----------|----------|------------|
| 0 | kMotorway | motorway | 고속도로 |
| 1 | kTrunk | trunk | 고속화도로/국도(자동차전용) |
| 2 | kPrimary | primary | 일반국도 |
| 3 | kSecondary | secondary | 지방도 |
| 4 | kTertiary | tertiary | 시군도/시골길 |
| 5 | kUnclassified | unclassified | 미분류도로 |
| 6 | kResidential | residential | 주거도로 |
| 7 | kServiceOther | service | 서비스도로/기타 |

**의미**: `factor *= class_factor_[roadclass]` — 낮을수록 해당 등급 선호.

---

## 적용 로직 요약 (motorcyclecost.cc:470-478)

```cpp
factor *= class_factor_[static_cast<uint32_t>(edge->classification())];
if (curvature_penalty_ > 0.0f) {
    uint32_t cv = edge->curvature();
    float straight = (cv < 8) ? (8 - cv) / 8.0f : 0.0f;  // 0=곡선, 1=직선
    factor *= (1.0f + curvature_penalty_ * straight);
}
if (edge->length() > span_min_length_) {
    if (edge->bridge()) factor *= long_bridge_factor_;
    if (edge->tunnel()) factor *= long_tunnel_factor_;
}
```

---

## ⚠️ 초안 yaml vs 실제 키명 교정표

| routing_config.yaml 초안 (잘못된 키) | 실제 json_key | 비고 |
|--------------------------------------|---------------|------|
| `long_bridge_penalty` | `long_bridge_factor` | 이름 다름 |
| `long_tunnel_penalty` | `long_tunnel_factor` | 이름 다름 |
| `bridge_length_threshold_m` | `span_min_length` | 이름 + 용도 다름 (bridge/tunnel 공용) |

이 세 키는 잘못 쓰면 Valhalla가 조용히 무시 → 슬라이더 조작해도 경로 불변.
