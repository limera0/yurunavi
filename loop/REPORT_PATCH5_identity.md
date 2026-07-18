# REPORT_PATCH5 — 3코스(시골길/지방도/국도) 정체성 튜닝 + U턴 허용범위 엔진 패치

작성일: 2026-07-18
작업 범위: valhalla-src C++ 패치(uturn_penalty) + Docker 빌드/배포 + routing_service.dart 값 반영
+ tuning_dashboard 계측 도구 확장

---

## 1. 배경

기존 3코스는 이미 class_factors/curvature_penalty로 차별화돼 있었지만, 마스터가 각 코스의
목표 정체성을 구체적으로 지정(도로 등급 위주 비율, 고가/터널 회피 거리, 코스별 U턴 허용범위,
코스 간 겹침률 상한 10%)했다. 이번 작업은 그 정체성을 실제 값으로 반영하고 5개 실측 OD로
검증한 뒤 프로덕션에 배포하는 것.

**절대 원칙(변경 없음)**: 한국 도로교통법상 오토바이는 배기량 무관 고속도로·자동차전용도로
통행 불가 — 3코스 전부 `class_factors '0':100,'1':100`(motorway/trunk 배제) 유지. 국도
코스의 "일반 내비게이션과 동일한 안내"는 primary 안에서의 시간 최적화를 의미하며 고속도로
개방과는 무관함(마스터가 직접 정정, [[project_motorcycle_legal_constraints]] 메모리 참조).

---

## 2. 엔진 패치: `uturn_penalty` (신규 코스팅 옵션)

### 문제

기존 U턴 페널티(`kMotoUturnPenalty = 5000.0f`)는 하드코딩 상수로 모든 코스에 동일 적용됨.
이번 요구사항은 "U턴은 지양하되, 피하려면 코스별 한계거리(시골길 300m/지방도 500m/국도 1km)
이상 돌아가야 하는 경우엔 허용"이라는 코스별 튜닝이 필요했다 — patch3(2026-07-11)의 "재탐색
시 제자리 U턴 강요" 버그 대응과는 무관한 별개 요구사항(투어링 중 불필요한 U턴 자체가 라이더
경험상 거슬린다는 이유).

### 패치 내역

| 파일 | 변경 |
|------|------|
| `proto/descriptors/options.proto` | `float uturn_penalty = 102;` 추가 (기존 마지막 필드 101 다음) |
| `src/sif/motorcyclecost.cc` | `kMotoUturnPenalty` 상수 → `kDefaultUturnPenalty`(5000.0f, 기존값 그대로) + `kUturnPenaltyRange{0.0f, 5000.0f, 20000.0f}` 추가. 멤버 `uturn_penalty_` 추가, 생성자에서 `costing_options.uturn_penalty()` 파싱(0 이하면 기본값 폴백, 다른 factor류와 동일한 관례). `ParseMotorcycleCostOptions`에 `JSON_PBF_RANGED_DEFAULT_V2` 파싱 라인 추가. `TransitionCost`/`TransitionCostReverse` 두 곳의 `c.cost += kMotoUturnPenalty` → `c.cost += uturn_penalty_`로 교체. |

### 빌드/배포

- 이미지 태그: `valhalla-fork:patch5-uturn-allowance` (기반 `docker/Dockerfile.fork`, patch4-turnangles 위에 누적)
- 빌드: 에러 0건, `docker/Dockerfile.fork`로 정상 빌드
- 검증 포트 8016에서 2단계 검증 후 운영(8002) 교체, `docker-compose.yml` 이미지 태그 갱신, 임시 컨테이너 제거 완료

### 검증 결과

**① 회귀 (uturn_penalty 미지정 시 기존과 100% 동일해야 함)**: 5개 OD × 3코스(최종 튜닝값,
uturn_penalty 키 제외) 전부 patch4(8002)와 patch5(8016)의 `length`/`time`이 소수점까지
완전 일치 — **PASS (15/15)**.

**② 동작 변화 (uturn_penalty가 실제로 경로에 영향을 주는지)**: 판교→무릉 시골길 코스에서
```
uturn_penalty=1~50    : 318.464km / 29594.9s / maneuvers=111 (uturn 1회)
uturn_penalty=5000~1e5: 318.756km / 29654.9s / maneuvers=115 (uturn 1회)
```
값이 작을수록 U턴을 받아들여 더 짧은/효율적인 경로(−0.3km, −60s)를, 값이 클수록 U턴을
피해 약간 돌아가는 경로(+4 maneuvers)를 선택함을 실측으로 확인 — **의도한 방향으로 정상
작동**.

### 코스별 배포값

| 코스 | uturn_penalty |
|------|---------------|
| 시골길 | 50 |
| 지방도 | 70 |
| 국도 | 120 |

값의 절대 크기는 "300m/500m/1km 허용범위"를 정밀하게 역산한 것이 아니라 기존 5000 대비
같은 자릿수 스케일로 잡은 시작값이다 — 마스터가 이미 "검증 후 협의하여 변경 가능"이라
명시한 항목이므로, 실주행/가상GPS 검증 후 조정 여지 있음.

---

## 3. 코스별 가중치 최종값 (`lib/services/routing_service.dart` / `tools/tuning_dashboard/routing_config.yaml` 동기화)

| | 시골길 | 지방도 | 국도 |
|---|---|---|---|
| class_factor 0/1 (motorway/trunk) | 100 (배제) | 100 (배제) | 100 (배제, 절대 원칙) |
| class_factor 2 (primary) | 10 | 2.0 | 0.3 |
| class_factor 3 (secondary) | 4 | 0.3 | 1.2 |
| class_factor 4 (tertiary) | 0.5 | 1.1 | 2.0 |
| class_factor 5/6/7 (소로·마을·농로) | 1.3/1.4/1.6 | 1.8/2.2/3.0 | 4.0/5.0/8.0 |
| curvature_penalty | 3.0 | 0.5 | 0.0 |
| long_bridge/tunnel_factor | 6.0 | 5.0 | 1.0 |
| span_min_length | 300 | 1000 | 500(중립) |
| use_tracks | 0.15 (기존 0.8→하향, 보행자 사고 위험 대비 비포장 선호 제거) | 0.2 | 0.0 |
| uturn_penalty | 50 | 70 | 120 |

**변경 근거**: `tools/tuning_dashboard/batch_validate.py`로 5개 실측 OD × 3코스를 반복
호출해 도로등급 구성비(거리 가중)·장대교량터널 회피·코스쌍 겹침률을 관찰하며 5라운드
반복 조정. 한 번에 하나씩 바꾸려 했으나 일부 라운드는 여러 값을 동시에 조정(교차 원인
규명이 다소 거칠어진 지점 있음, §5 참조).

---

## 4. 앱 코드 변경 (`lib/services/routing_service.dart`)

- 3개 코스팅 옵션에 위 최종값 반영 + `uturn_penalty` 키 신규 추가
- 시골길↔지방도 과다우회 폴백 판정 기준을 `durationMin` 비율 → `distanceKm` 비율로 변경
  (임계치 1.5배는 유지) — 소요시간은 평균속도 가정에 의존적이라 신뢰도가 낮다는 마스터
  판단에 따름
- **신규**: 지방도↔국도 과다우회 폴백(`_provincialBalancedOpts`, 임계치 1.3배, 거리 기준)을
  기존 시골길 폴백과 동일한 패턴으로 추가 — 지방도가 국도의 1.3배 이상 거리로 벌어지면
  완화된 costing으로 지방도만 재요청해 교체
- 국도 코스의 motorway/trunk 배제(`'0':100,'1':100`)와 `use_highways:0.0`은 **변경 없음**
- flutter-coder가 구현, `flutter analyze` 0 issues / `flutter test` 246 tests 통과,
  code-auditor PASS(회귀 인덱스·ETA 코스 매칭·0-division 가드·모터웨이 배제 유지 여부 확인)

---

## 5. 5개 실측 OD 최종 검증 결과 (`batch_validate.py`, 교체된 프로덕션 8002 대상)

| OD | 겹침률 게이트 | 판정 |
|----|--------------|------|
| 송탄→팔당 (87.6km 국도) | 적용 | FAIL — 시골-지방 40%대, 나머지 두 쌍 13~15% |
| 행촌동→강릉안목 (477km 국도) | 적용 | FAIL — 세 쌍 모두 47~69% (구조적, 아래 참조) |
| 판교→무릉 (492km 국도) | 적용 | FAIL — 세 쌍 모두 41~81% (구조적, 아래 참조) |
| 화정→석모도 (75.8km 국도) | 적용 | FAIL — 지방-국도 42%대(강화도 진입 교량 공유 추정), 나머지 두 쌍 7~14% |
| 청파동→춘천레고랜드 (106km 국도) | 적용 | **PASS** — 세 쌍 전부 3~8% |

**구조적 한계로 인정하기로 마스터와 합의한 항목** (가중치를 극단으로 밀어도 개선 폭이
작았음 — 산간 지형에 대체 도로망 자체가 희박한 것으로 추정): 행촌동→강릉안목,
판교→무릉. 마스터 지시: "단거리 위주로 최적화, 장거리는 한계 인정".

**남은 개선 여지** (이번 세션에서 멈춘 지점, 추가 라운드로 이어갈 수 있음):
- 송탄→팔당의 시골길-지방도 겹침(40%대) — 수도권 남부 평지 구간인데도 두 코스가 같은
  지방도/시군도 축으로 수렴하는 것으로 보임, class_factor 3/4 세부 조정 여지 있음.
- 화정→석모도의 지방도-국도 겹침(42%대) — 강화도 진입로가 사실상 교량 하나뿐이라
  구조적일 가능성이 있으나 확인되지 않음, 추가 조사 필요.

`tools/tuning_dashboard/batch_validate.py` 재실행 + `routing_config.yaml` 미세조정으로
언제든 이어갈 수 있음(엔진 재빌드 불필요, JSON 값만 조정).

---

## 6. 신규/변경 파일

| 파일 | 내용 |
|------|------|
| `tools/tuning_dashboard/core/metrics.py` | 거리 가중 구성비, 200km 초과 경로 청크 분할(trace_attributes 거리 상한 대응), 장대교량/터널 판정 함수 추가 |
| `tools/tuning_dashboard/core/overlap.py` | 신규 — 코스 쌍 겹침률(way_id 공유 구간 근사) |
| `tools/tuning_dashboard/batch_validate.py` | 신규 — 5개 OD × 3코스 배치 검증 스크립트 |
| `tools/tuning_dashboard/core/valhalla_client.py` | `build_costing_options()`에 use_tracks/use_living_streets/top_speed/use_ferry/uturn_penalty 패스스루 추가 |
| `tools/tuning_dashboard/routing_config.yaml` | 최종 튜닝값으로 갱신(프로덕션과 동기화) |
| `tools/tuning_dashboard/app.py` | class_factor 슬라이더 상한 20→150(모터웨이 배제값 100 표현 가능하도록) |
| `tools/tuning_dashboard/PARAMS_MANIFEST.md` | uturn_penalty 파라미터 명세 추가 |
| `lib/services/routing_service.dart` | §4 참조 |
| `/data/projects/valhalla-src` (`yurunavi-fork` 브랜치) | §2 참조 |
| `docker/docker-compose.yml` | valhalla 이미지 태그 → `patch5-uturn-allowance` |

---

## 7. 미완료 / 마스터 확인 필요

| 항목 | 내용 |
|------|------|
| 실기기 검증 | `flutter build apk --debug` 빌드 완료(`build/app/outputs/flutter-apk/app-debug.apk`). 3배속 가상GPS/실주행 검증은 마스터가 직접 진행 예정. |
| uturn_penalty 절대값 재협의 | 50/70/120은 시작값 — 실주행에서 체감이 다르면 조정 |
| 송탄-팔당, 화정-석모도 잔여 겹침 | 추가 튜닝 라운드로 이어갈 수 있음 (§5) |
| `native/src/main.rs::handle_calc_route`(port 8003) | 이번 조사 중 발견 — 3코스 costing의 오래된 사본이지만 앱에서 전혀 호출되지 않는 죽은 코드(구버전 class_factors 키 체계, 폴백 배수도 1.3배로 dart와 다름). 이번 범위 밖이라 손대지 않음, 향후 정리 대상. |
| valhalla-fork 브랜치 오프사이트 백업 | patch5 커밋을 `github.com/limera0/valhalla-yurunavi-fork`(private)에 push할지 마스터 확인 필요([[reference_valhalla_fork_backup]] 참조, origin 직접 push는 금지) |
