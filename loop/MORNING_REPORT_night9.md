# MORNING_REPORT — Night 9 (2026-06-03)

## 전체 결과: 4/4 PASS

모든 작업 구현(a) + code-auditor PASS(b) + git 커밋(c) 완료.

---

## Task 1 — Valhalla trace_attributes 자동 검증 하니스 (`7b41351`) ✅

**파일**: `scripts/validate_rural_route.py` (신규)

사람이 APK 화면을 보고 동탄 도심 우회를 확인하는 작업을 자동화.

**동작**:
1. Valhalla `/route` (시골길 프로필, 수원 영통구→평택) 호출
2. polyline6 디코드 후 서브샘플
3. Valhalla `/trace_attributes` 로 edge 도로등급 분류
4. 동탄 bbox(lat 37.19~37.25, lon 127.03~127.10) 내 엣지 필터
5. urban grid 비율(residential + service_other) 계산 → PASS/FAIL

**현재 결과**: 동탄 bbox 26개 엣지 전부 `tertiary`, urban grid 0.0% < 20% → **PASS**

```bash
# 사용법
python3 scripts/validate_rural_route.py
python3 scripts/validate_rural_route.py --urban-threshold 0.25
# exit 0=PASS, 1=FAIL, 2=오류
```

---

## Task 2 — Flutter 경로카드에 winding/fun score 표시 (`b92e0dd`) ✅

**파일**: `lib/services/routing_service.dart`, `lib/features/map/providers/map_providers.dart`, `lib/features/map/presentation/main_map_screen.dart`

**변경 내용**:
- `RouteResult.windingScore: double` 추가 (기본 0.0)
- `allRouteMeta` 레코드 타입: `({km, mins})` → `({km, mins, windingScore})`
- `_fetchAndStoreAllRoutes` + `_onRouteCardSelect` 양쪽에서 `NativeEngine.calcWindingScore()` 호출
- `_RouteCard`: 하단에 "재미 72" 배지 추가, 최고점 카드는 "★ 재미 72"

**보장**: `RoutingService.fetchRoutes()` Valhalla 3경로 distinct 로직 **완전 미수정**.

---

## Task 3 — systemd 서비스 점검 및 안전 재시작 (`9c7b726`) ✅

**발견**: 서비스 파일(`~/.config/systemd/user/yurunavi-rust.service`)이 이미 올바른 경로(`/data/projects/yurunavi/native/target/debug/yurunavi_server`)를 가리키고 있었음.

**수행**:
1. `cargo build --bin yurunavi_server` (Module 3 api.rs 포함 최신 빌드)
2. 수동 시작 프로세스(PID 1148803) 종료
3. `systemctl --user start yurunavi-rust.service`

**결과**: Active: running (PID 1439933), `/health` ok, `calc_route` route_type=0 → fallback 동작 확인(winding=48.9)

---

## Task 4 — fun_score에 도로등급(FC) 항 추가 (`7220697`) ✅

**파일**: `native/src/api.rs` (순수 가산)

**추가된 함수**:
| 함수 | 설명 |
|---|---|
| `road_class_score(avg_fc: f64) -> f64` | FC1→0pt, FC5→100pt (선형) |
| `fun_score_v2(route, avg_fc) -> f64` | τ 60% + FC 40%, 0~100 |
| `rank_candidates_v2(Vec<(route, avg_fc)>)` | fun_score_v2 기준 내림차순 |

**가중치 근거 (OSM 사양서)**:
- 곡률(τ)이 더 중요(60%): 와인딩 구조 자체가 핵심 fun 요소
- 도로등급(FC, 40%): FC5(소로) > FC2(국도), 시골길 다움 반영

**테스트**: 25/25 PASS (신규 4개 포함)

---

## git log

```
7220697 feat(rust): add road_class_score + fun_score_v2 (night9 task4)
9c7b726 chore(ops): verify + safe-restart yurunavi-rust systemd service (night9 task3)
b92e0dd feat(flutter): show winding/fun score on route cards (night9 task2)
7b41351 feat(scripts): trace_attributes auto-validation harness (night9 task1)
8a12cea checkpoint: before night9 task1 trace_attributes harness
3b30c80 docs: MORNING_REPORT night8 — 3 modules PASS
```

---

## 막힌 점 / 주의사항

1. **APK 빌드 상태 미확인**: Night 8에 걸어둔 APK 빌드(`build_HHMM.log`)가 성공했는지 확인 필요.

2. **windingScore Dart 구현**: Task 2에서 `NativeEngine.calcWindingScore()`를 사용했는데, 이것은 Dart 순수 구현(Rust FFI bridge가 아닌 fallback Dart 코드). Rust HTTP 서버의 `winding_score`와 동일 알고리즘이지만 Rust 바이너리 의존성 없이 동작함. 의도적 설계.

3. **fun_score_v2의 avg_fc 입력**: 현재 Valhalla `/route` 응답에는 avg_fc가 포함되지 않음. `rank_candidates_v2`는 Valhalla `trace_attributes`에서 도로등급을 분류한 후에야 실제로 연동 가능. 현재는 skeleton+테스트만 완성.

4. **ETA Valhalla 전환 보류**: `_speedCountrysideKmh` 등 Dart 후처리 상수와 이중보정 위험 — 계속 보류.

---

## 다음 세션 추천 1개

**trace_attributes → avg_fc 계산 → fun_score_v2 실제 연동**

`scripts/validate_rural_route.py` 에서 이미 trace_attributes를 호출하고 있음.
여기서 `avg_fc` (도로등급 평균)를 계산해 Rust `/calc_route` 응답에 포함시키면
Flutter `_RouteCard`에서 `windingScore` 대신 `fun_score_v2` 기반 점수를 보여줄 수 있음.

구체적으로:
1. Rust `/calc_route` 핸들러에서 route geometry 취득 후 `trace_attributes` 추가 호출
2. 도로등급 평균 `avg_fc` 계산
3. `fun_score_v2(pts, avg_fc)` 호출하여 응답에 포함
4. Flutter: `/calc_route` HTTP 응답의 `fun_score`를 route card에 표시
