# MORNING REPORT — S9 · 자동차전용도로 하드 배제

- 작성 2026-08-10 (대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0810_S9_motorroad_hard_exclusion.md](HANDOFF_0810_S9_motorroad_hard_exclusion.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S9

---

## 착수 전 확인한 것

작업 시작 전 마스터에게 세션 범위(트랙 A+B 완전 구현)와 프로덕션 스왑 처리 방식(격리
검증 통과 후 스왑 직전 재확인)을 확인받았다.

## 뭐가 됐나 — 지시서 계획과 실제 경로가 갈라짐

지시서 §2는 트랙 B(`motorroad=yes`)를 exclude_polygons 또는 그래프 오버레이
파이프라인(옵션 C)으로 풀 것을 전제했다. 실제로는:

1. 나무위키 자동차전용도로 목록 197건(1,984.5km) 확인 → 지시서의 "100건+" 게이트에
   걸림.
2. exclude_polygons 시도 → Valhalla `max_exclude_polygons_length`(운영 설정 10km)에
   바로 막히는 것을 확인(197건 버퍼폴리곤 둘레는 이 한도의 400배 규모).
3. 마스터 확인 후 그래프 오버레이 파이프라인(옵션 C) 착수 결정.
4. **착수 중 `valhalla-src` 소스를 직접 추적하다 전제 자체가 틀렸음을 발견**:
   `motorroad=yes`는 그래프 스키마에 남지 않는 게 맞지만, 그걸 우회할 그래프
   오버레이 파이프라인을 새로 만들 필요가 없었다. 실제 원인은 `graphenhancer.cc`/
   `countryaccess.cc`의 국가별 access override 폴백 로직이 보행자·자전거·모페드
   접근권만 제거하고 **모터사이클 접근권 제거를 빠뜨린** 단 하나의 플래그 누락이었고,
   이 국가별 override 테이블 자체가 `admins.sqlite` 파일이 애초에 생성된 적이 없어
   (`valhalla.json`엔 경로 설정이 있었으나 파일 부재) 통째로 죽어있었다.
5. 마스터 재확인 후 D'(admin DB 생성 + 국가 항목 1건 추가)로 전환, 그대로 완료.

세션 중 마스터에게 3차례 확인을 구했다 — ① 세션 범위/스왑 방식, ② 197건 확인 후
Track B 방법(A/C/D' 재검토), ③ 프로덕션 실제 스왑 실행. 매번 근거(소스 라인, SQL
쿼리 결과 등)를 먼저 제시하고 판단을 구했다.

## 구현 내용

### 트랙 A — motorway/trunk 하드 배제

`motorcyclecost.cc` `Allowed()`(:387)/`AllowedReverse()`(:412)의 조건절에
`edge->classification() == baldr::RoadClass::kMotorway/kTrunk` 체크를 직접 추가.
JSON costing(`use_highways`/`class_factors`)과 무관하게 항상 하드 배제 — 대안이
없어도 절대 진입하지 않는다.

빌드 중 컴파일 에러 1건 발견·수정: `namespace valhalla::sif` 안에서 비한정
`RoadClass`가 protobuf 생성 `valhalla::RoadClass`로 잘못 해석됨(같은 이름의
enum이 상위 네임스페이스에 존재) → `truckcost.cc`의 기존 관례대로 `baldr::RoadClass::`
로 명시.

### 트랙 B — `motorroad=yes` 하드 배제

- `valhalla_build_admins`로 `admins.sqlite` 생성(KR+JP pbf 기준).
- 스크래치 빌드로 한국 관리구역의 정확한 이름을 먼저 확인:
  `name_en="South Korea"`, `iso_code="KR"`.
- `adminconstants.h`의 `kCountryAccess`에 `"South Korea"` 항목 추가 —
  motorroad 인덱스에 `kAutoAccess|kTruckAccess|kBusAccess|kHOVAccess|kTaxiAccess`만
  포함(모터사이클·모페드·자전거·보행자·휠체어 제외). trunk/trunk_link는 -1(변경
  없음) — 이미 트랙 A에서 코스팅 레벨에 하드 배제되므로 중복 불필요.
- 생성된 `admin_access` 테이블을 SQL로 직접 조회해 `motorroad=233`
  (=1+8+64+128+32, 모터사이클 비트 1024 제외됨)을 확인 — 코드가 의도한 값과 정확히
  일치.
- **부수 효과**: `admins.sqlite` 부재로 일본 타일의 `drive_on_right`가 계산된 적이
  없었다는 것도 함께 드러남(일본은 좌측통행인데 기본값 우측통행으로 처리되고
  있었을 가능성) — 이번 조치로 같이 정상화됨. 이번 세션 스코프는 아니었으나 기록.

### 배포

- Valhalla 포크(`/data/projects/valhalla-src`, `yurunavi-fork` 브랜치) 커밋
  `313e30b62`(motorway/trunk) → `4f077a042`(빌드 수정) → `de28c1ae7`(admin override),
  전부 `backup` remote에 push 완료.
- 이미지 `valhalla-fork:patch7-s9-hardexclude` 빌드(`docker/Dockerfile.fork`).
- `admins.sqlite` + KR/JP 타일 재빌드(685초) → `valhalla_build_extract`로 tar 패키징
  (4.14GB, 기존과 유사 크기).
- 격리 컨테이너(임시 포트)로 3코스 회귀 확인(용인남부→팔당댐: 시골길 67.4km /
  지방도 57.9km / 국도 51.7km — 패치 전과 사실상 일치) 후, tar extract 방식(운영과
  동일 서빙 모드)으로 재검증까지 마치고 프로덕션 스왑.
- 프로덕션 파일(`valhalla.json`, `valhalla_tiles.tar`) 스왑 전 타임스탬프 백업
  (`*.bak.20260810_132227`) 완료. 스왑 후 동일 OD로 프로덕션 포트(8002) 재확인 —
  격리 검증 결과와 정확히 일치.
- `docker-compose.yml` 이미지 태그 갱신, 커밋 `6f4858f`.

## 알려진 제약 / 후속 과제

1. **초장거리 단일 요청 실패**: 서울↔부산(500km+) 같은 직선 장거리 요청은
   motorway/trunk 셧컷 제거로 Valhalla의 단일 탐색이 실패할 수 있음(`no path
   could be found`). **실제로 무경로인 게 아니다** — 경유점 하나(대전)를 끼워
   2구간으로 나누면 585km 완주 경로가 정상 산출됨(has_highway: false 확인). 원인은
   Valhalla 검색 알고리즘이 저비용 셧컷 없이 초장거리를 단일 패스로 탐색하다 자체
   한계에 부딪히는 것으로 보임 — `max_distance`를 500km→800km로 올려도 이 특정
   실패는 해소되지 않았음(별개 요인). 마스터 결정: 일단 배포, 품질은 실주행에서
   판단. 이 앱은 이미 "제자리 루프" 회피에 경유점 주입 패턴을 쓰고 있어
   (`routing_service.dart`), 필요하면 같은 패턴으로 초장거리 요청에 자동 경유점을
   넣는 방안을 검토할 수 있음 — 이번 세션 스코프 밖.
2. **motorroad=yes 실도로 end-to-end 검증 미완**: SQL 레벨(정확한 access 비트마스크가
   `admin_access` 테이블에 반영됨, 이 테이블을 읽는 코드는 Valhalla 표준 코드로
   이번에 수정하지 않음)로는 검증했으나, 실제 한국 도로 좌표로 "회피 확인" 예시는
   확보하지 못했다. Overpass API가 이 환경에서 접속 불가(두 미러 모두 timeout/
   connection refused), 로컬에 OSM 파싱 도구(osmium/pyosmium) 부재. 마스터 확인 후
   SQL 검증으로 충분하다고 판단해 배포 진행. **후속**: 지시서 §3이 원래 계획한
   나무위키 197건 좌표 기반 대량 curl 회귀(진입 경로에 motorway/trunk/motorroad가
   없는지 전수 확인)는 미실행 — 다음 세션 후보.
3. **일본 타일 우측통행 정상화**: 부수 효과로 발견·해결됐으나 실주행/회귀 테스트는
   하지 않음(이 앱이 일본에서 실제로 쓰이는지 여부와 무관하게 그래프 정확성 차원의
   개선).

## 검증

- `flutter analyze`/`flutter test`: 이번 세션은 Dart 코드 변경 없음(Valhalla 포크
  C++만 수정) — 해당 없음.
- code-auditor: 이번 세션은 Valhalla C++ 포크 작업이라 code-auditor 대상 밖(Dart/Rust
  전제 도구) — 오케스트레이터가 직접 SQL/curl 회귀로 검증(위 참고).
- 프로덕션 스왑 전후 동일 OD 회귀 일치 확인 완료.

---

**목표 달성 판정:** 원래 목표: 자동차전용도로(motorway/trunk 등급 + `motorroad=yes`
태그 도로) 전부를 오토바이 경로에서 하드 배제, 대안이 없어도 절대 진입하지 않게.
/ 달성: **yes** — 두 트랙 모두 코드·인프라 레벨에서 하드 배제 구현·검증·배포 완료.
단, motorroad=yes의 실도로 end-to-end 검증(나무위키 197건 curl 회귀)과 초장거리
단일 요청 실패 건은 후속 과제로 남음 — 법적 배제 자체는 완료됐으나 완전한 실증은
다음 세션 몫.
