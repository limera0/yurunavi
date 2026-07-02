# RECON — gate/access 태깅이 이 Valhalla 빌드에서 관통을 실제로 막는가 (격리 PoC)

목표: 평택 캠퍼스 관통 진입/출구 노드에 `barrier=gate`+`access=private`를 넣으면 Valhalla 3.7.0(`valhalla-fork:patch2-signals`, motorcycle/motor_scooter)이 실제로 회피/차단하는지 격리된 소형 타일로 검증. **프로덕션 pbf/tile_dir/valhalla.json 변경 없음** (아래 "격리 환경" 참조).

## 0. 베이스라인 재현 (정정 좌표, 프로덕션 서버 `localhost:8002`)

입구 `37.03529,127.05320` → 출구 `37.04051,127.05290`, `costing=motorcycle`:

- **관통 재현됨.** 694m, 64.4s, 전부 `highway=unclassified`, `road_class=unclassified`, **이름 없음(names: null)** 4개 엣지 (`edge.way_id`: 1195222150 → 1195222147 → 1195222146 → 773739945).
- `trace_attributes`로 way_id 확보 후 원본 `south-korea-latest.osm.pbf`에서 해당 way의 실제 노드/태그 대조:
  - 진입측 접점 노드 `11093304907` (37.0351566, 127.0528969) — 공용 3차도로 **삼성로**(`773692520`, tertiary)와 내부 `unclassified` way(`1195222150`)가 만나는 지점.
  - 출구측 접점 노드 `7222208930` (37.0407485, 127.0526016) — 공용 3차도로 **첨단대로/고덕여염3로**와 내부 `unclassified` way(`773739945`)가 만나는 지점.
  - 두 접점 모두 원본 pbf에 `access`/`barrier` 태그 **없음** (이전 tick `RECON_private_avoid.md`의 "(B) 데이터 부재" 결론과 일치).

## 1. 격리 환경 구성 (`/data/valhalla/poc_gate/`, 프로덕션과 완전 분리)

- `osmium extract`로 bbox `127.045,37.030,127.062,37.046`만 잘라 `small.osm.pbf` 생성 (원본 `south-korea-latest.osm.pbf` 불변, 읽기 전용 접근만).
- 오버레이는 `osmium apply-changes`로 적용 (tick이 제안한 `osmium merge`는 동일 ID 재정의 시 버전 충돌 위험이 있어, 표준 osmChange 방식인 `apply-changes`로 대체 — 노드/way `version+1`로 modify).
- `valhalla_build_tiles`는 프로덕션과 동일 `mjolnir.*` 파라미터(`include_driveways:true`, `reclassify_links:true`, `use_admin_db:true` 등, `/data/valhalla/custom_files/valhalla.json` 그대로 복제, `tile_dir`만 격리 경로로 교체)로 `valhalla-fork:patch2-signals` 이미지의 컨테이너에서 실행. `tile_extract` 등 존재하지 않는 admin/timezone 보조 파일은 프로덕션도 현재 없는 상태(확인함)라 조건 동일.
- 각 변형마다 격리 포트(18001~18005)의 임시 `valhalla_service` 컨테이너로 서비스, 테스트 후 전부 `docker rm -f`로 정리.

## 2. 검증 결과 (before/after)

| 변형 | 태그 | 결과 (동일 좌표, motorcycle) | 결과 (motor_scooter) |
|---|---|---|---|
| A. 게이트 없음 (격리 재현) | — | 0.694km, 64.4s (프로덕션과 동일) | 0.694km, 64.4s |
| B. **tick이 요청한 방식**: 진입/출구 노드에 `barrier=gate`+`access=private` | 노드 2개만 | **0.694km, 64.4s — 변화 없음** | **0.694km, 64.4s — 변화 없음** |
| C. way 4개 전체에 `access=private` | way-level | **0.694km — 변화 없음** | 미측정 (B/C 패턴 동일해서 생략) |
| D. way 4개에 `motor_vehicle=no`+`motorcycle=no` | way-level, 모드 특정 | **0.879km, 69.1s — 삼성로→첨단대로로 우회 확인** | **0.879km, 76.2s — 동일 우회** |
| E. way 4개에 `access=no` (private 대신 no) | way-level, 일반 | **0.879km — D와 동일하게 우회** | 미측정 |

`costing_options.motorcycle.ignore_access:true`로 D 타일 재요청 → 0.694km로 복귀 (관통 경로 부활). 즉 이 파라미터가 정상적으로 오버라이드 스위치로 작동함을 확인.

### trace_attributes 실측 (B/C 타일)

`edge.destination_only`, `access_restrictions`, `traversability` 등 access 관련 필드가 태깅 후에도 **전혀 노출되지 않음** (`traversability: "both"` 그대로) — 즉 그래프 빌드 단계에서 `access=private` 값 자체가 주행 제약으로 변환되지 않았다. 반면 D/E 타일은 진입 엣지가 `773692520`(삼성로, 공용도로)로 바뀌어 있어 회피가 실제 그래프 레벨에서 일어남을 확인.

## 결론 (1줄)

**부분 실패 → 원인 규명됨.** tick이 요청한 `barrier=gate`+`access=private` (노드/way 불문)는 이 Valhalla 빌드(`valhalla-fork:patch2-signals`)에서 **motorcycle/motor_scooter 라우팅에 아무 영향을 주지 않는다** — `access=private` 값이 그래프 빌드 시 주행 제약으로 변환되지 않는 것으로 보인다(반면 `access=no`나 `motor_vehicle=no`/`motorcycle=no`는 정상적으로 회피를 유발함). 오버레이-병합 트랙 자체는 기술적으로 동작하지만(osmium apply-changes → 재빌드 → 즉시 반영 확인), **태그 값을 `access=private` 대신 `motor_vehicle=no`+`motorcycle=no`(또는 `access=no`)로 바꿔야 회피가 성립**한다.

## 다음 슬라이스 제안

1. **원인 심화조사(선택)**: 왜 `access=private`만 무효인지 — `valhalla-fork` 소스(`mjolnir/graphbuilder.cc` 또는 `osmaccess` 파싱부)에서 `private` 값 처리 로직을 직접 대조. 이번 tick 범위 밖(코드 열람만 필요, 격리 상태 유지 가능하면 다음 tick으로).
2. **실전 적용 시**: 알려진 사유지 진입/출구 접점 way에 `motor_vehicle=no`+`motorcycle=no` 오버레이 유지보수 구조 설계 — 이번에 검증된 `osmium apply-changes` 방식으로 오버레이 `.osc` 파일을 별도 관리하고, `south-korea-latest.osm.pbf` 갱신마다 재적용 → `valhalla_build_tiles` 재실행하는 파이프라인. `access=private`가 원래 목적(태그 시맨틱상 "사유지, 목적지 차량만 허용")과 맞지 않게 "완전 차단"(`no`)으로 우회해야 하는 점은 OSM 태그 시맨틱과 실제 동작이 어긋나는 것이므로 문서화 필요.
3. 이전 tick(`RECON_private_avoid.md`)에서 제안한 `exclude_polygons` 방식(클라이언트 코드 변경만으로 즉시 가능)이 이 오버레이-재빌드 파이프라인보다 훨씬 저비용 — 사유지 목록이 적다면 `exclude_polygons`가 여전히 더 실용적인 1순위 대안일 수 있음(마스터 판단 필요).

## 격리 산출물 (프로덕션 미영향, 참고용으로만 보존)

`/data/valhalla/poc_gate/` — `small.osm.pbf`, `gate.osc`/`gate_way*.osc`(오버레이), `small_*.osm.pbf`(변형본), `tiles_*/`(격리 빌드 타일), `valhalla_*.json`(격리 config). 이 디렉토리는 저장소 밖(`/data/valhalla/`)이라 git 추적 대상 아님 — 필요 없어지면 삭제해도 무방(마스터 확인 후).
