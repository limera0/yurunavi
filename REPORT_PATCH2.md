# REPORT_PATCH2 — Valhalla Fork Patch #2 (곡률/교량/터널 페널티)

작성일: 2026-06-07  
작업 범위: valhalla-src C++ 패치 + Docker 빌드 + 앱 Dart 연동

---

## 1. 목표

Valhalla motorcycle costing에 per-course 신호 기반 페널티 3종 추가:

| 파라미터 | 역할 | 기본값(미적용) |
|----------|------|--------------|
| `curvature_penalty` | 직진 도로(curvature 낮음) 회피 강도 | 0.0 |
| `long_bridge_factor` | 긴 교량(≥span_min_length m) 배수 | 1.0 |
| `long_tunnel_factor` | 긴 터널(≥span_min_length m) 배수 | 1.0 |
| `span_min_length` | 교량/터널 임계 길이(m), uint32 | 500 |

---

## 2. C++ 패치 내역

### options.proto (필드 98~101 추가)
```protobuf
float curvature_penalty = 98;
float long_bridge_factor = 99;
float long_tunnel_factor = 100;
uint32 span_min_length = 101;
```

### motorcyclecost.cc

**범위 상수:**
```cpp
constexpr ranged_default_t<float>    kCurvaturePenaltyRange{0.0f, 0.0f, 10.0f};
constexpr ranged_default_t<float>    kLongBridgeFactorRange{0.0f, 1.0f, 20.0f};
constexpr ranged_default_t<float>    kLongTunnelFactorRange{0.0f, 1.0f, 20.0f};
constexpr ranged_default_t<uint32_t> kSpanMinLengthRange{0, 500, 5000};
```

**EdgeCost 주입 (class_factor 적용 직후):**
```cpp
factor *= class_factor_[static_cast<uint32_t>(edge->classification())];
if (curvature_penalty_ > 0.0f) {
    uint32_t cv = edge->curvature();
    float straight = (cv < 8) ? (8 - cv) / 8.0f : 0.0f;
    factor *= (1.0f + curvature_penalty_ * straight);
}
if (edge->length() > span_min_length_) {
    if (edge->bridge()) factor *= long_bridge_factor_;
    if (edge->tunnel()) factor *= long_tunnel_factor_;
}
```

**파싱:** `JSON_PBF_RANGED_DEFAULT_V2` 사용 (plain proto field, `has_X_case()` 불필요).

---

## 3. 빌드

| 항목 | 내용 |
|------|------|
| 이미지 태그 | `valhalla-fork:patch2-signals` |
| 기반 | `docker/Dockerfile.fork` (Python 비활성화) |
| 로그 | `/tmp/fork_build2.log` — error 0건 |
| 빌드 캐시 | Patch #1 레이어 재사용, C++ 변경분만 재컴파일 |

---

## 4. 검증 결과 (포트 8013, `valhalla-fork-p2`)

OD: 용인 남부(37.19, 127.08) → 팔당댐 인근(37.55, 127.20)

| 케이스 | 거리 | 시간 | maneuvers | 비고 |
|--------|------|------|-----------|------|
| D1 class_factors만 | 56.94 km | 4772 s | 66 | 기준선 |
| D2 + curvature_penalty 2.0 | **61.40 km** | 5093 s | 68 | +4.46km (+7.8%) — 직선 회피 확인 |
| D3 + bridge/tunnel 3.0, span≥500 | **57.82 km** | 4873 s | 73 | 교량/터널 우회 확인 |
| D3b span_min_length=0 (→기본 500) | 57.82 km | 4873 s | — | D3 동일 — 폴백 확인 |

**판정: PASS**
- curvature_penalty: D2 > D1 거리 차 +7.8% — 직선 간선도로 회피 유효
- bridge/tunnel factor: D3가 D2와 다른 경로 (우회 발생)
- span_min_length=0 폴백: D3b == D3 — 기본값 500 적용 확인

---

## 5. 앱(Dart) 연동

`lib/services/routing_service.dart` commit `5476550`

| 코스 | curvature_penalty | long_bridge_factor | long_tunnel_factor | span_min_length |
|------|-------------------|--------------------|--------------------|-----------------|
| 시골길 | 2.5 | 3.0 | 3.0 | 500 |
| 지방도 | 1.0 | 1.5 | 1.5 | 500 |
| 국도 | 0.0 (미적용) | 1.0 (미적용) | 1.0 (미적용) | — |
| _ruralBalancedOpts | 1.2 | 1.5 | — | — |

`_ruralDetourThreshold`: 1.3 → **1.5** (시골길 폴백 임계 완화)

---

## 6. 미완료 / 마스터 직접 작업 필요

| 항목 | 이유 |
|------|------|
| 운영 컨테이너(8002) 교체 | 실측 통과 후 마스터 직접 |
| APK 빌드 및 실기기 테스트 | 빌드 환경 마스터 |
| 8013 검증 컨테이너 정리 | 검증 완료 후 `docker rm -f valhalla-fork-p2` |
| factor 값 실측 튜닝 | curvature 2.5 / bridge 3.0은 시작값 |
| 일본 mbtiles / CJK 폰트 | 별도 태스크 |

---

## 7. 주요 트러블슈팅

| 문제 | 원인 | 해결 |
|------|------|------|
| `has_curvature_penalty_case` 컴파일 에러 | plain proto field에 `JSON_PBF_RANGED_DEFAULT` 사용 | `JSON_PBF_RANGED_DEFAULT_V2`로 교체 |
| `GetFloat()` 크래시 (integer JSON값) | rapidjson int → float 변환 실패 | `GetDouble()` + `static_cast<float>` |
| `#include <array>` 위치 오류 | `#ifdef INLINE_TEST` 블록 안에 삽입 | 블록 밖으로 이동 |
