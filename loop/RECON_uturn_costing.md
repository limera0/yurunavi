# RECON — U턴 강요 근원 (thor 패치 A 타당성)
대상 소스: /data/projects/valhalla-src (stock 3.7.0 + motorcyclecost.cc diff)
모드: READ-ONLY (코드변경 0, 커밋 0)

## Q1. motorcyclecost.cc에 U턴/전환비용 코드 존재?
있음. 단, **독자적인 U턴 오버라이드가 아니라 부모 클래스(DynamicCost)의 `AddUturnPenalty`를 호출하는 정도**.

- `MotorcycleCost::TransitionCost` — src/sif/motorcyclecost.cc:486
  - `turntype == baldr::Turn::Type::kReverse` 판정 — motorcyclecost.cc:522
  - `AddUturnPenalty(...)` 호출 — motorcyclecost.cc:532 (penalize_internal_uturns=`false` 고정 인자)
- `MotorcycleCost::TransitionCostReverse` — motorcyclecost.cc:551
  - 주석(motorcyclecost.cc:562): "Motorcycles should be able to make uturns on short internal edges" → **오토바이 costing은 짧은 내부 엣지에서의 U턴을 의도적으로 페널티 없이 허용**하도록 설계되어 있음 (`penalize_internal_uturns=false`).
  - `AddUturnPenalty(...)` 호출 — motorcyclecost.cc:606
- `AllowedReverse` (역방향 접근 허용 판정, U턴과 별개의 access 체크) — motorcyclecost.cc:399-421

→ **U턴을 "금지"하는 코드는 없음. 오직 시간비용(penalty, 초 단위)을 더하거나 안 더하는 수준**이며, 짧은 내부엣지 U턴은 명시적으로 페널티 면제.

## Q2. 부모 DynamicCost의 U턴 페널티 기본 구현
- 상수 정의 — valhalla/sif/dynamiccost.h:191-193
  - `kTCUnfavorablePencilPointUturn = 15.f` (배율)
  - `kTCUnfavorableUturn = 600.f` (기본 U턴 페널티, 초)
  - `kTCNameInconsistentUturn = 10.f`
- `AddUturnPenalty(...)` 인라인 구현 — dynamiccost.h:883-914
  - 내부 짧은 엣지 U턴 vs 노드에서의 U턴(`has_reverse`) vs pencil-point U턴을 구분해 가산 (914 부근에서 `*= kTCUnfavorablePencilPointUturn`)
  - **`penalize_uturns_` 플래그가 꺼져 있으면(`!penalize_uturns_ || !edge->internal()`, dynamiccost.h:854) 내부 엣지 U턴 페널티 로직 자체가 스킵**
- `penalize_uturns_` 멤버 — dynamiccost.h:1370, 생성자 파라미터 기본값 `false` (dynamiccost.h:189, 261)
  - MotorcycleCost가 이 값을 `true`로 넘기지 않는 한 내부-엣지 U턴은 사실상 무료(0초 추가)

→ **U턴은 "금지 불가능한 구조"다. Valhalla costing 모델 자체가 U턴을 완전히 막는 메커니즘을 제공하지 않고, 오직 초 단위 페널티(가산)로만 억제한다.** 페널티를 아무리 올려도 다른 경로가 없거나(막다른 길) 다른 경로가 더 비싸면 U턴이 선택된다.

## Q3. thor 경로탐색에서 반대방향 edge 허용 지점 — ★ 핵심 근원
**진짜 강제 지점은 costing이 아니라 thor의 그래프 탐색 순서 로직**이다.

- `UnidirectionalAStar::Expand` — src/thor/unidirectional_astar.cc:60-157
  - 95-111행: 노드의 모든 엣지를 순회하며, **U턴에 해당하는 엣지(`pred.opp_local_idx() == meta.edge->localedgeidx()`)는 즉시 확장하지 않고 `uturn_meta`에 보류** (100-104행 주석: "wait with evaluating this edge until last")
  - 142-154행: **U턴이 아닌 다른 모든 엣지 확장이 전부 실패(`disable_uturn == false`, 즉 막다른 길)했을 때만 U턴 엣지를 실제로 확장** (141행 주석: "means we're at a deadend so lets go back and re-evaluate a potential u-turn")
  - 즉, **정책상 U턴은 "다른 도리가 없을 때"만 확장되도록 설계됨** — 이건 정상적인 deadend 처리이지 버그가 아님.
- `BidirectionalAStar::ExpandForward/ExpandReverse` (거의 동일 로직) — src/thor/bidirectional_astar.cc:439-502 (`disable_uturn`, `uturn_meta` 동일 패턴)
  - 163-166행 주석: "Returns false if uturns are allowed... In that case we disallow uturns... to connect the forward and reverse paths."
- `AllowedReverse` 사용 지점 (반대편 엣지 access 허용 여부, U턴 여부와 무관한 access 체크) — bidirectional_astar.cc:268, unidirectional_astar.cc:245,352 / costmatrix.cc:553 / dijkstras.cc:164,175

→ **결론: "제자리 U턴 강요"가 재현되는 코드 경로는 이 deadend-fallback U턴 확장 로직 자체가 아니라, 이 로직에 도달하기 전 단계 — 즉 origin(재탐색 시작점) 엣지 선택이 이미 "반대방향" 엣지로 고정되어 들어오는 경우**다. 이 로직만 봐서는 정상 상황에서 U턴이 강제될 이유가 없다 (다른 엣지가 있으면 그쪽을 먼저 씀). → Q4로 원인 이전.

## Q4. heading/search_filter 무시 근원 (loki) — ★ 진짜 원인 후보
- `heading_filter` — src/loki/search.cc:84-98
  - **86-88행: `if (!location.has_heading_case()) { return false; }` → heading이 요청(Location)에 세팅되어 있지 않으면 필터링을 전혀 하지 않음 (모든 방향의 엣지를 후보로 허용)**
- heading 적용 지점 — search.cc:337,369,445,472 (`heading_filter(location, angle) || layer_filter(...)` 조건으로 후보 PathEdge 제외)
- `default_heading_tolerance` — src/loki/worker.cc:55-56, 348 (`config.get<unsigned int>("loki.service_defaults.heading_tolerance")`)
  - **location에 heading 자체가 없으면 tolerance 설정과 무관하게 필터가 통째로 우회됨** (has_heading_case 체크가 우선)
- `search_filter`(도로등급/터널/다리 등, heading과 무관) — search.cc:30-50, PathLocation 구성 — search.cc:766 이하

→ **원인 가설: 재탐색(reroute) 요청 시 origin Location에 `heading` 필드를 채우지 않으면, loki가 차량 진행방향과 반대인 엣지(주행 중인 도로의 "뒤쪽" 방향 엣지)를 최근접 후보로 그대로 채택할 수 있다.** 이 경우 origin이 이미 "반대편 엣지"로 스냅되므로, thor 입장에서는 Q3의 deadend-fallback이 아니라 **정상 경로 탐색의 첫 스텝부터 실제로 왔던 길을 되짚어가는 것이 "합리적인" 최소비용 경로가 되어버림** → 사용자 체감상 "제자리 U턴 강요".

## Q5. 재빌드 필요 판정
- Q1: sif (런타임 costing)
- Q2: sif (런타임 costing, 상수/플래그)
- Q3: thor (런타임 그래프 탐색 순서)
- Q4: loki (런타임 요청 파싱/후보 필터링)
- mjolnir 관련 유일 히트: `not_thru` 플래그가 그래프빌드 시(mjolnir/graphenhancer.cc:1319-1324) 타일에 굽혀짐. 하지만 이는 **U턴 강제 로직과 무관한 별도의 pruning 메커니즘**(막다른 길 아닌 관통 경로 억제용)이며, Q1-Q4의 U턴 강제 경로 자체는 이 플래그를 조건으로 쓰지 않음.

**결론: 재빌드 불필요.** Q1~Q4 모두 런타임 레이어(sif/thor/loki)에서만 발생하는 문제이며, 그래프 타일(mjolnir 산출물)의 속성 변경이 필요하지 않다. thor 패치 A(가칭, origin heading 강제/보정 또는 costing penalize_uturns 활성화)는 **컨테이너 재시작만으로 적용 가능**한 런타임 수정 범위다.

### 다음 검증 포인트 (본 recon 범위 밖)
- yurunavi가 재탐색(reroute) 요청 시 실제로 `location.heading()`을 채워 보내는지 (Flutter/Rust 클라이언트 측 확인 필요 — 이건 valhalla-src가 아니라 yurunavi 레포 쪽 코드).
- `penalize_uturns_`를 MotorcycleCost 생성자에서 `true`로 넘기는 것이 패치 A의 대안이 될 수 있는지 (다만 Q2에서 확인했듯 이건 "내부 짧은 엣지" U턴에만 적용되고, 노드 U턴(has_reverse)에는 이미 항상 kTCUnfavorableUturn이 적용됨 — dynamiccost.h:908-910).
