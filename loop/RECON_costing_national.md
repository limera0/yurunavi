# RECON — 국도 코스(index 2) 고속도로/자동차전용도로 미배제 원인

작성: 2026-07-11, read-only 정찰 후 실측.

## 요청 배경 (핸드오프 §3.3, 마스터 확정)

국도 코스(index 2)만 일반 내비 수준으로 빠르고 효율적이어야 함:
- 국도(primary) 최우선, 지방도(secondary)는 보조.
- 고속도로·유료도로·자동차전용도로(motorway/trunk) 전면 배제.
- 고가·터널 회피 로직 불필요(정속 허용).

## 발견 — 근본 원인: `shortest: true`가 모든 커스텀 costing을 무력화

`lib/services/routing_service.dart:206` — index 2 costing_options에 `'shortest': true`가 있음.

`valhalla-src/src/sif/motorcyclecost.cc:444`:
```cpp
if (shortest_) {
  return Cost(edge->length(), sec);
}
```
`EdgeCost()`가 `shortest_`일 때 **순수 거리비용만 반환하고 즉시 return** — 이 줄 아래에 있는
`class_factor_`(474줄, motorway/trunk=100 배제), `highway_factor_`(455줄, `use_highways` 반영),
`toll_factor_`(458-460줄, `use_tolls` 반영), `curvature_penalty_`/`long_bridge_factor_`/
`long_tunnel_factor_`(475-483줄)가 **전부 도달 불가 dead code**가 됨.

즉 index 2는 `class_factors`에 `"1": 100`(trunk 배제)을 적어놨어도 실제로는 **완전 무시되고
순수 최단거리 라우팅**을 하고 있었음.

## 실측 (curl, 용인 남부→팔당댐 인근, 37.19,127.08 → 37.55,127.20)

| 조건 | trunk% | primary% | 거리 | 시간 |
|---|---|---|---|---|
| 현재 배포값(`shortest:true`) | **36.3%** | 31.7% | 46.68km | 51min |
| `shortest` 제거 + `use_tolls:0.0` 추가 | **0%** | **96.3%** | 63.75km | 65min |

`cost`/`length` 비율이 정확히 1000(순수 거리) — `shortest:true`가 정말 factor 전부를
건너뛴다는 것을 수치로 확인.

## 결론 / 조치

1. **`'shortest': true` 제거** — 이거 하나가 핵심 원인. 기존 `class_factors`(2:0.5 국도 선호,
   1:100 trunk 배제 등)는 이미 적절히 설계되어 있었음(실측 결과 96.3% primary로 확인) — 값
   재튜닝 불필요, 그냥 죽어있던 코드를 살리기만 하면 됨.
2. **`'use_tolls': 0.0` 추가** — 기존엔 아예 없던 키. `motorcyclecost.cc:339-343`가
   `use_tolls=0`일 때 `toll_factor_=2.0`(최대 회피)을 계산하는데, 이 역시 `shortest:true`
   때문에 안 먹고 있었음. 이번 OD엔 유료도로 후보가 없어 `has_toll` 차이는 직접 관측 못했지만,
   메커니즘 자체는 기존 Valhalla 표준 파라미터라 재빌드 불필요 — JSON 값만 추가.
3. **`motorroad=yes` 태그**: mjolnir 그래프빌드 단계에서 접근권한(ped/bike/moped 제거)에만
   쓰이고 RoadClass는 안 바꿈(`countryaccess.cc:118-120`) — 모터사이클 access는 안 막힘, 별도
   런타임 처리 불필요. 이 앱의 기존 RoadClass 매핑(`RECON_KR_ROADCLASS.md`)에서 이미
   trunk=자동차전용도로로 취급 중이라 `class_factors['1']` 배제로 충분.
4. **고가/터널 회피**: index 2는 원래도 `curvature_penalty:0.0`, `long_bridge_factor:1.0`,
   `long_tunnel_factor:1.0`로 이미 중립(회피 없음) 설정이었음 — `shortest:true` 제거와
   무관하게 추가 조치 불필요.

## 영향 범위

- 시골길(0)/지방도(1) 코스는 `shortest` 옵션 자체가 없어 미영향.
- 순수 클라이언트(Dart) JSON 값 변경 — valhalla-src 재빌드 불필요.
- 거리/시간이 눈에 띄게 늘어남(+36%/+27%, 이번 실측 기준) — 트렁크/유료도로를 실제로 피하기
  시작해서 생기는 정상적인 트레이드오프. `_speedNationalKmh=45`로 ETA는 별도 재계산되므로
  화면 표시 로직엔 추가 변경 불필요.
