# 구현 프롬프트 — 포크 패치 #2 (곡률/긴교량/긴터널 페널티) + 앱 연동 (감독형, 단계별 정지)

> 환경: Claude Code on Ubuntu(westinx), **마스터 직접 감독**(C++ 빌드·회귀위험, 무인 금지).
> 목표: motorcycle costing에 per-course **곡률 페널티 / 긴 교량 페널티 / 긴 터널 페널티**를 추가하고, 앱(Dart)에 새 파라미터 + 1.3→1.5 적용. 새 검증 포트 **8013**으로 빌드·검증.
> 운영(8002)·기존 검증(8012) 불가침. 새 이미지/새 포트로만.

## 🚫 규칙

- 각 STEP 끝 **정지·보고**, 다음으로 자동진행 금지.
- 운영 컨테이너/8002/docker-compose.yml/valhalla.json 수정 금지. 기존 valhalla-fork-test(8012)도 건드리지 말 것.
- 추측 금지: 패치 전 `view`로 현재 줄번호 재확인(class_factor 주입은 RECON_FORK_SIGNALS 기준 L455, 이동 가능).
- 빌드는 docker/Dockerfile.fork(기존 사본) 재사용. tmux 사용.

## 설계 사양 (확정)

**전부 per-course, class_factors와 동일 방식. 기본값 = 미적용(스톡 동일).**

신규 proto 필드 (`proto/descriptors/options.proto`, class_factors=97 다음):

```
float curvature_penalty = 98;     // 직진 페널티 강도 (0=미적용)
float long_bridge_factor = 99;    // 긴 교량 배수 (1.0=미적용)
float long_tunnel_factor = 100;   // 긴 터널 배수 (1.0=미적용)
uint32 span_min_length = 101;     // 교량/터널 길이 임계(m), 기본 500
```

생성자: proto → 멤버 초기화. 기본값 `curvature_penalty_=0.0`, `long_bridge_factor_=1.0`, `long_tunnel_factor_=1.0`, `span_min_length_=500`.

EdgeCost 주입 (L455 `factor *= class_factor_[...]` 인근, EdgeFactor 직전):

```cpp
// 직진 페널티: curvature 0(직선)일수록 페널티. 8 이상(굽음)은 페널티 0.
// factor *= 1 + curvature_penalty_ * max(0, (8 - curvature)) / 8
if (curvature_penalty_ > 0.0f) {
  uint32_t cv = edge->curvature();           // 0~15
  float straight = (cv < 8) ? (8 - cv) / 8.0f : 0.0f;  // 0(굽음)~1(직선)
  factor *= (1.0f + curvature_penalty_ * straight);
}
// 긴 교량/터널: 임계 길이 초과한 것만
if (edge->length() > span_min_length_) {
  if (edge->bridge()) factor *= long_bridge_factor_;
  if (edge->tunnel()) factor *= long_tunnel_factor_;
}
```

- 짧은 하천 교량(<500m)은 무영향 → 강 건너기 보존.
- 연속/개수 카운팅은 범위 밖(EdgeCost는 엣지 단위). per-edge 길이 임계로 긴 고가/터널을 잡는다.

## STEP 0 — 소스 정합성 게이트

- `git -C /data/projects/valhalla-src status` 깨끗한지, HEAD가 72f459fc5인지, 패치 #1(class_factors)이 그대로 있는지 확인.
- 3지점 현재 줄번호 `view`로 재확인: options.proto의 class_factors=97 줄 / motorcyclecost.cc 생성자 / EdgeCost의 class_factor 주입 줄.
- 보고 후 정지.

## STEP 1 — 패치 (빌드 전)

1. proto 4필드 추가 (98~101)
2. 생성자에서 파싱·초기화 (ParseMotorcycleCostOptions에 curvature_penalty/long_bridge_factor/long_tunnel_factor/span_min_length 파싱 — class_factors 파싱과 동일 매크로/패턴; float은 JSON_PBF_RANGED_DEFAULT 류, uint는 적절히)
3. 멤버 변수 선언 + EdgeCost 주입(위 코드)
- `git diff` 보고. 빌드 안 함. 정지.

## STEP 2 — 빌드 (tmux)

```bash
tmux new -s fork-build2
cd /data/projects/valhalla-src
docker build -t valhalla-fork:patch2-signals --build-arg CONCURRENCY=2 -f docker/Dockerfile.fork . 2>&1 | tee /tmp/fork_build2.log
```

- 캐시 덕에 변경 파일만 재컴파일. 성공/실패 보고(실패 시 `grep -iE "error:" /tmp/fork_build2.log`). 정지.

## STEP 3 — 포트 8013 기동 (운영·8012와 격리)

```bash
docker run -d --name valhalla-fork-p2 -p 8013:8002 \
  -v /data/valhalla/custom_files:/custom_files:ro \
  valhalla-fork:patch2-signals \
  valhalla_service /custom_files/valhalla.json 1
sleep 6
curl -s http://localhost:8013/status | python3 -m json.tool
```

정지.

## STEP 4 — 검증 (곡률/긴교량/긴터널이 실제로 동작하는지)

311 동부대로 포함 OD로, 패치 파라미터 유무 비교. (출발/도착은 STEP에서 마스터가 평택→팔당 좌표 기입.)

```bash
# D1: class_factors만 (패치2 미적용)
... "class_factors":{...}}
# D2: + curvature_penalty 2.0
... "class_factors":{...}, "curvature_penalty":2.0}
# D3: + 긴 교량/터널 회피
... "class_factors":{...}, "curvature_penalty":2.0, "long_bridge_factor":3.0, "long_tunnel_factor":3.0, "span_min_length":500}
```

각 거리 + 가능하면 trace로 곡률/교량 분포 비교. D2/D3가 D1과 달라지면(직진·긴교량 회피) 성공. 정지.

- ⚠️ span_min_length는 uint 파라미터 — JSON에서 정수로 전달. 0이나 미전달 시 기본 500 적용 확인.

## STEP 5 — 앱(Dart) 연동

`lib/services/routing_service.dart`:

- 1.3배 폴백 임계 → **1.5배**로 변경 (시골길 폴백 조건).
- 코스별 새 파라미터 추가 (class_factors 옆):
  - 시골길: `curvature_penalty: 2.5, long_bridge_factor: 3.0, long_tunnel_factor: 3.0, span_min_length: 500`
  - 지방도: `curvature_penalty: 1.0, long_bridge_factor: 1.5, long_tunnel_factor: 1.5, span_min_length: 500`
  - 국도: 직진 OK → `curvature_penalty: 0.0`(미적용), 교량/터널도 1.0(미적용)
  - _ruralBalancedOpts: 시골길보다 약하게 `curvature_penalty: 1.2, long_bridge_factor: 1.5, ...`
- `git diff` 보고. 단일 파일. 정지. (APK 빌드는 마스터)

## 범위 밖

- 운영 docker 교체(8002) — 마스터 직접, 실측 통과 후.
- 8013 검증 컨테이너는 검증용. 끝나면 정리.
- 곡률/교량 factor 값은 시작값 — 실측으로 튜닝.

각 STEP 정지·보고. 완료 후 REPORT_PATCH2.md.
