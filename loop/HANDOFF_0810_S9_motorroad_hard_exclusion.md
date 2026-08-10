GOAL: 자동차전용도로(motorway/trunk 등급 + `motorroad=yes` 태그 도로) 전부를 오토바이 경로에서 하드 배제한다 — 대안 경로가 없어도 절대 진입하지 않아야 한다(법적 절대 원칙, memory `project_motorcycle_legal_constraints`).

# HANDOFF — S9 · 자동차전용도로 하드 배제

- 작성 2026-08-10 · 브랜치 `verify/ride-0711` · 기준 HEAD `283a0b9`
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S9
- 원 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md) §4-9
- 순서: 오늘 마스터 결정으로 잔여 5건(S1b·S9·S11·S13·S14) 중 **S1b는 코드 완료
  (실기기 검증 대기 상태로 전환, `283a0b9`), S9이 다음 착수 항목**. P3(기능개선) 트랙은
  이 5건 전부 끝난 뒤 착수(memory `project_p3_priority_plan`).

---

## 0. 이번 조사에서 원 체크리스트의 전제 하나를 뒤집었다 — 먼저 읽어라

원 체크리스트(§S9)와 master_plan §4-9는 "`motorroad=yes` 배제는 Valhalla 포크 C++
코스팅 수정이 필요하다"고 적어뒀다. **이번 핸드오프 작성 중 직접 소스를 열어 확인한
결과, 이 전제가 틀렸다** — 정정 사유와 대안은 아래 §2에 있다. **재작업하지 말고
§2부터 읽고 시작하라.**

---

## 1. 트랙 A — motorway/trunk 하드 배제 (상대적으로 명확, 여기부터)

### 현재 상태 (확인 완료, `lib/services/routing_service.dart`)

체크리스트의 `routing_service.dart:157,178` / `highway_classes` 표기는 **낡았다.**
실제 키 이름과 위치:

- `_ruralBalancedOpts`(시골길 코스): `:174` `use_highways: 0.0`, `:176-186` `class_factors`
  — `'0': 100`(motorway 소프트 페널티)
- `_provincialBalancedOpts`(지방도 코스): `:195` `use_highways: 0.0`, `:197-206` 동일 패턴
- 국도 코스(인덱스 2)용 블록은 이 두 개 아래 더 있을 수 있음 — **먼저 파일 전체에서
  `use_highways`/`class_factors` 전부 grep해서 코스 3종 블록을 다 찾아라.**
- `'1'`(trunk) 키는 의도적으로 제거돼 있음(주석: `use_highways:0.0`이 이미 trunk 회피
  처리, 이중 페널티가 580km 우회를 낸 적 있음 — `RECON_costing_national.md` 참고).

**문제**: `use_highways`/`class_factors`는 Valhalla 표준 코스팅 옵션이고 전부 **소프트
페널티**다. 대안이 없으면 뚫린다 — 이게 S9이 생긴 이유(38번 지방도 실사례).

### 구현 방향

Valhalla 포크(`/data/projects/valhalla-src`, 브랜치 `yurunavi-fork`, 현재 HEAD `637ca089e`,
이미지 태그 `patch6-turnangle2`)의 `src/sif/motorcyclecost.cc`:

- `MotorcycleCost::Allowed()`(:387) / `AllowedReverse()`(:412)의 `if (!IsAccessible(edge) || ... )
  return false;` 조건절에 `edge->classification() == RoadClass::kMotorway ||
  edge->classification() == RoadClass::kTrunk` 를 추가(reverse 쪽은 `opp_edge`).
- **그래프 재빌드 불필요** — `RoadClass`는 이미 저장된 edge 속성이라 코스팅 재컴파일 +
  이미지 재빌드만 필요하다(트랙 B와 다름, 아래 참고).
- JSON 쪽(`routing_service.dart`)의 `use_highways`/`class_factors`는 **그대로 둬도 된다**
  (하드 배제가 코스팅에서 걸리므로 JSON 페널티는 그 위의 안전망으로 유지 — 굳이 지우지 마라).
- 코스팅 변경이 `use_highways: 0.0`으로 이미 회피 중이던 경로 선택(우회 방향 등)에 영향을
  주는지 §4 검증에서 확인.

### 배포 (Valhalla 포크는 이 리포 밖의 별도 git 저장소 — 주의)

1. `/data/projects/valhalla-src`에서 새 브랜치 커밋 (patch 번호는 `patch7-...`로 이어감,
   `git log --oneline yurunavi-fork -5`로 최신 확인 후 넘버링).
2. **`git push backup yurunavi-fork` 필수** — origin은 공식 `valhalla/valhalla.git`이라
   push 금지(memory `reference_valhalla_fork_backup`).
3. `docker/Dockerfile.fork`(같은 저장소 안)로 이미지 재빌드 → 새 태그.
4. **이 리포**의 `docker/docker-compose.yml:3` `image: valhalla-fork:patch6-turnangle2`를
   새 태그로 갱신 → 커밋.
5. `docker compose up -d`로 재기동 — **이건 프로덕션 라우팅 서비스에 영향을 준다.** 로컬/
   격리 컨테이너(임시 포트)로 먼저 검증 후 진행할 것 (§5의 사유지 조사가 쓴 패턴 참고:
   `docker run -d -p 18010:8002 ...`로 격리 기동 후 `docker rm -f`).

---

## 2. 트랙 B — `motorroad=yes` 배제 (원 전제 정정, 방법 재검토)

### 확인한 사실 (추측 아님, 소스 직접 열람)

- `motorroad=yes`는 그래프 빌드 시(`src/mjolnir/countryaccess.cc:118-120`) **RoadClass를
  바꾸지 않는다.** 대신 국가별 access override 테이블(`AccessTypes::kMotorroad`)을 찾아
  적용하고, 못 찾으면 trunk/trunk_link 로직으로 폴백한다.
- 이 체크아웃에서 한국(KR/KOR) 전용 override를 못 찾았다 — 즉 오토바이 access가 실제로
  안 막히는 것으로 보인다. **38번 지방도 실사례와 부합.**
- **핵심: 이 태그는 그래프에 별도 필드로 남지 않는다.** `motorcyclecost.cc`의 코스팅
  단계에서 "이 edge가 원래 motorroad였는가"를 조회할 방법이 없다 — 즉 **트랙 A와 같은
  RoadClass 체크 방식으로는 처리 불가능하다.** 이게 원 체크리스트가 "코스팅만 고치면
  된다"고 적은 부분이 틀린 지점이다. 하려면 mjolnir 그래프 빌드 코드 자체를 고치고
  **전체 그래프를 재빌드**해야 한다 — 코스팅 패치 6회(patch1~6)와는 급이 다른 작업이다.

### 이미 이 리포에 검증된 선례가 있다 — 같은 문제를 이미 풀어본 적 있다

`RECON_private_avoid.md` + `RECON_overlay_pipeline.md`(2026-07-20~21, 사유지 관통 회피
조사)가 **정확히 같은 클래스의 문제**("소수의 알려진 도로 구간을 하드 배제하고 싶다")를
다뤘고, 트레이드오프까지 정리해뒀다. 재탕하지 말고 그 결론을 재사용하라:

| 방법 | 위치 | 리스크 | 비고 |
|---|---|---|---|
| **A. `exclude_polygons`(클라이언트 요청 바디)** | `routing_service.dart` (사유지 조사가 이미 위치 특정: `_doFetch` 근방) | 낮음 — 서버·그래프 무변경 | 팀이 **같은 문제에서 이미 이 방법을 권고**함("목록이 소수~수십 곳이면 압도적으로 저비용"). |
| B. `avoid_locations`(소프트) | 동일 | 낮음, 단 **소프트라 S9 목적(하드 배제)에 안 맞음** | "불가능한 좌회전" 안전망(`knownImpossibleTurnAvoids`)에 이미 쓰인 패턴 — 참고만, 이번엔 부적합 |
| C. Valhalla 그래프 오버레이 재빌드(`.osc` apply-changes) | 신규 파이프라인(설계는 있음, 미구현 — `RECON_overlay_pipeline.md` §4) | 중간 — 롤백 지점 4개로 완화 설계는 돼 있으나 스크립트·cron 자체가 없음 | 목록이 수십~수백 건으로 크거나 다른 클라이언트도 지원해야 할 때 재고(원 문서 결론 그대로) |
| D. mjolnir 그래프 빌드 코드 수정 + 전체 재빌드 (원 체크리스트가 가정한 방법) | `countryaccess.cc` 등 | **가장 큼** — 사실상 C보다 더 무거움(그래프 스키마 자체를 바꿈) | 권장 안 함. A로 안 되는 게 확인되면 C부터 검토 |

**권고: A(`exclude_polygons`)부터 시도.** 서버·그래프 무변경이라 리스크가 가장 낮고,
같은 문제유형에 팀이 이미 권고한 방법이며, 구현 위치도 이미 알려져 있다.

### 실행 전 반드시 규모부터 확인하라

exclude_polygons가 "소수~수십 곳"에서만 저비용이라는 게 원 결론의 전제다.
**나무위키 자동차전용도로 목록의 실제 개수를 먼저 세라** — 이 리포엔 아직 그 목록이
없다(검색 완료, 마스터가 예전에 "준다"고 언급만 했고 실제 URL/좌표는 안 남아있음).
공개 정보이므로 WebSearch로 "나무위키 자동차전용도로"를 직접 찾아 목록화하면 된다.
**수십 곳을 넘으면(예: 100건+) A는 페이로드/폴리곤 정밀도 부담이 커진다 — 이 경우
멈추고 마스터에게 C(그래프 오버레이 파이프라인 실구현, "최소 1개 tick 이상 추가 소요"
원 문서 견적)로 갈지 확인받아라.** 추측으로 밀어붙이지 말 것.

### 구현 방향 (규모 확인 후, A로 갈 경우)

- 각 자동차전용도로 구간을 도로 중심선 buffer 폴리곤(폭 수십 m)으로 변환.
- `routing_service.dart`의 3개 코스 요청(시골길/지방도/국도) 전부의 costing 요청 바디에
  `exclude_polygons` 추가.
- 유지보수성: 폴리곤 목록을 코드에 하드코딩하지 말고 별도 데이터 파일(예:
  `assets/config/motorroad_exclude.json`)로 분리 — `routing-config` 원격 갱신 패턴
  (memory `project_routing_remote_config`)과 결이 맞으면 그쪽에 편입도 고려.

---

## 3. 검증 (두 트랙 공통)

- 나무위키 좌표셋 전 구간에 대해 `/route`(costing=motorcycle) 호출 → 진입 경로에
  motorway/trunk/motorroad 구간이 하나도 없는지 확인 (스크립트로 자동화 권장,
  `RECON_overlay_pipeline.md` §5의 curl 회귀 패턴 참고).
- 트랙 A 배포 시 **회귀 확인**: 기존 코스 3종의 우회 경로 선택이 이상해지지 않았는지
  (580km 우회 사고 전례 — `RECON_costing_national.md`).
- 격리 검증 먼저(임시 포트 컨테이너), 프로덕션 스왑은 그 다음.

---

## 4. 하지 말 것 / 지켜야 할 선

- **소프트 페널티로 타협하지 마라.** 이 항목은 취향이 아니라 위법 방지다
  (memory `project_motorcycle_legal_constraints`) — "그래도 대안 없으면 뚫림" 상태로
  완료 보고하지 말 것.
- Valhalla 포크 작업 시 **`/data/projects/valhalla-src`는 yurunavi 리포 밖의 별도 git**이다.
  두 리포를 혼동해 커밋하지 마라. 커밋 후 `git push backup yurunavi-fork` 잊지 말 것
  (origin push 금지).
- `docker compose up -d` 재기동은 **프로덕션에 영향**을 준다 — 로컬/격리 검증 없이 바로
  실행하지 마라.
- flutter-coder/rust-coder 둘 다 Valhalla C++ 포크(트랙 A)를 커버하지 않는다 — 오케스트
  레이터가 직접 처리하거나 general-purpose 에이전트에 위임할 것. 트랙 B(Dart/JSON)는
  flutter-coder에 위임 가능.
- `git add -A` 금지 등 CLAUDE.md 하드룰 동일 적용 — **두 리포 각각** 커밋 전
  `git status --short` 확인(yurunavi와 valhalla-src는 별개 워킹트리).
- 이번 세션 범위는 S9만. Valhalla rate limit/재탐색 폭주(memory
  `project_valhalla_rate_limit`)는 별개 결함, 손대지 마라.

## 5. 산출물

1. 트랙별 체크포인트 커밋(각 code-auditor PASS 후 — 단 트랙 A의 C++ 변경은
   code-auditor가 Dart/Rust 전제 도구라 리뷰 방식을 오케스트레이터가 직접 판단해야 할 수
   있음, 최소 `flutter test`/기존 커밋 스타일의 회귀 curl 테스트로 대체).
2. `loop/CHECKLIST_0805_testride0802.md` §S9 갱신 + `loop/MORNING_REPORT_0810_S9_*.md`
   (`Goal: X / Met: yes·partial·no — 이유` 포함).
3. 규모 확인 결과(나무위키 목록 건수)와 A/C 중 어느 쪽으로 갔는지 리포트에 명시.
