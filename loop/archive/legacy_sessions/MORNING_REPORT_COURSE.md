# MORNING_REPORT_COURSE — 코스 차별화 설계 분석 완료

날짜: 2026-06-05  
분석가: Claude Sonnet 4.6 (읽기 전용, 코드 수정 없음)

---

## 작성된 문서 목록 및 핵심 요약

### docs/course_analysis/00_open_questions.md — 미확인 의문 누적

- **Q1 해결**: `class_factors`는 motorcycle costing에 적용됨 (Night7 curl 검증으로 확인됨).
- Q12 신규: NavScreen 재탐색 시 선택된 코스를 무시하고 항상 `routes[0]`(시골길) 사용 — 별도 버그.
- Q14 신규: Rust 서버(localhost:8002)와 Dart(valhalla.westinx.com) Valhalla URL 차이 — 동일 인스턴스 추정.

---

### docs/course_analysis/01_current_state.md — 현황 진단

- **`class_factors` 적용됨**: Night7(2026-06-02) 검증으로 3코스가 수치상 다른 geometry(15.4/15.9/17.2km) 확인.
- **진짜 문제 재정의**: "수치 차이가 있지만 시골길다운 느낌이 없음" — Valhalla는 곡률을 제어할 수 없어 FC5 소도로를 경유해도 직선이면 시골길 느낌이 없음.
- **추가 버그 발견**: nav_screen.dart L311에서 재탐색 시 항상 routes[0](시골길) 사용 — selectedRouteIdx 미전달.

---

### docs/course_analysis/02_valhalla_costing.md — Valhalla costing 전수 조사

- 경로 형태를 바꾸는 핵심 파라미터: `class_factors`, `use_highways`, `use_living_streets`, `use_tracks`, `top_speed`, `shortest`, `urban_penalty`.
- **Valhalla가 절대 못 하는 것**: 곡률 선호, 숲 근접도, 교통량 기반 경로 선택 — 이 모두가 Rust fun-road 레이어의 영역.
- `top_speed: 30` 설정 시 60km/h 도로 비용이 2배 상승 → 간선도로 회피 강도 증가.

---

### docs/course_analysis/03_funroad_design.md — fun-road 설계안

- **이미 구현된 인프라**: fun_score_v1~v4, rank_candidates_v2 — 다만 미연결. fun_score_v3는 계산되지만 Flutter에 미전달.
- **Valhalla/Rust 경계**: Valhalla = 도로 등급·타입 필터링, Rust = 곡률·숲·교통량 기반 재랭킹.
- **권장 전략**: 옵션B(class_factors 극단화) + 옵션D1(alternates + rank_candidates_v2 연결). `rank_candidates_v2`는 즉시 투입 가능.

---

### docs/course_analysis/04_roadmap.md — 단계별 구현 로드맵

- **가장 먼저 칠 한 커밋**: routing_service.dart 시골길 `top_speed: 40→30`, `class_factors['2']: 5→50` 극단화 — 단일 파일, 즉각 확인 가능.
- **핵심 단계 (Phase 3-B)**: Valhalla alternates + Rust `rank_candidates_v2()` 연결 — 이것이 진짜 코스 차별화의 열쇠.
- **마스터 확인 필수**: alternates 지원 여부(curl 1회), 재랭킹 시 코스 매핑 기준(시골길=최고 fun_score 여부).

---

## 긴급 버그 (코스 차별화와 별개)

**nav_screen.dart L311**: 재탐색 시 항상 routes[0](시골길) 사용.
```dart
// 현재 (버그)
setState(() => _routePoints = routes[0].points);

// 수정 (2파일: nav_screen.dart + 호출부)
setState(() => _routePoints = routes[widget.selectedRouteIdx.clamp(0, routes.length-1)].points);
```

---

## 핵심 발견 요약 (3개)

1. **class_factors는 작동한다** — Night7에서 curl 검증 완료. 3코스가 이미 다른 거리/shape.
2. **문제는 "양"이 아니라 "질"** — 15.4vs17.2km 차이는 있지만 곡률 차이가 없어 "시골길스러움" 없음.
3. **rank_candidates_v2가 즉시 투입 가능** — api.rs에 이미 구현됨. alternates 파라미터 확인 후 연결만 하면 됨.

---

---

## 추가로 확인한 중요 사실들

### ROADMAP v2 item 1 현황
- **기초 완료**: Night6b (distinct 3경로), Night7 (class_factors), Night11+후속 (1.3배 폴백)
- **미완료**: fun_score 재랭킹 → 경로 선택 피드백, 곡률 기반 시골길 배정

### fun_score_v3의 가용 미사용 문제
- Rust `/score_route`는 `fun_score_v3`(교통량 포함), `avg_speed_kmh`, `curvature_tau` 모두 반환
- Dart `FunScoreResult`는 `funScoreV2`, `avgFc`, `curvatureTau` 만 파싱
- `fun_score_v3`는 계산되고 있지만 Flutter에서 버려지고 있음

### Rust/Dart Valhalla URL 차이
- Dart: `https://valhalla.westinx.com` (Cloudflare 터널 경유)
- Rust: `http://localhost:8002` (직접 접근)
- 동일한 Valhalla 인스턴스 (yurunavi_handoff.md 확인)

---

*분석 완료: 2026-06-05. 코드 수정 없음. 문서 5개(00~04) + MORNING_REPORT_COURSE.md 생성.*
