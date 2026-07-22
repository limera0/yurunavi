# 정찰 프롬프트 — 포크 패치 #2 신호 확정 (속도/직진/고가도로)

> 환경: Claude Code on Ubuntu(westinx), Sonnet 4.6, 읽기전용. /goal 무인 가능.
> 목표: 이미 clone된 `/data/projects/valhalla-src`(3.7.0, HEAD 72f459fc5)에서, motorcycle costing에 **속도 페널티 / 직진(곡률) 페널티 / 고가도로 페널티**를 추가하기 위해 사용 가능한 엣지 속성·접근자를 실소스로 확정한다.
> 배경: 317번 같은 "secondary로 태깅된 고속 직진 고가도로"가 세 코스에 모두 끼어듦. class_factors(등급)로는 구분 불가 → 물리 특성(고속·직진·고가)을 직접 때릴 신호가 필요.

## 🚫 규칙

- 읽기전용. 허용 쓰기 = `/data/projects/yurunavi/RECON_FORK_SIGNALS.md` 한 파일.
- 빌드/수정/docker/서비스 조작 금지.
- 추측 금지. 시그니처·값범위는 소스에서 verbatim 인용 + `파일:줄`.

## 수집 항목

### 1. 곡률(직진) 신호

- `valhalla/baldr/directededge.h`에서 **곡률 관련 멤버/접근자**가 있는지 grep: `curvature`, `bendiness`, `complex_restriction` 무관. 특히 `curvature()` 메서드 존재 여부와 **반환 타입·값 범위·의미**를 verbatim 인용. (있으면 직진 페널티를 이걸로 직접 구현 가능.)
- 없으면 "없음" 명시. (그 경우 속도 대리지표로 감.)

### 2. 고가도로/터널 신호

- `directededge.h`에서 `bridge()`, `tunnel()` 접근자 존재·반환타입 확인 (verbatim).
- 엣지 길이 접근자 `length()` 확인 (고가 길이 누적/판단용).

### 3. 속도 신호 + 기존 속도 페널티

- `src/sif/motorcyclecost.cc` `EdgeCost()`에서 현재 **edge 속도를 어떻게 얻는지**(`edge_speed` 변수, tile->GetSpeed 등) verbatim.
- 기존 `SpeedPenalty()` 함수가 **무엇을 계산하는지** 요약 (우리가 추가할 속도 페널티와 중복/충돌 여부 판단). 시그니처 + 핵심 로직 인용.
- motorcycle costing에 이미 속도 관련 옵션(`top_speed` 등)이 EdgeCost 비용에 영향을 주는지, 아니면 시간(time)에만 영향을 주는지 — 코드로 확인. (top_speed가 비용 페널티로 작동하면 새 파라미터 없이 될 수도 있음 → 중요.)

### 4. 우리 class_factor 주입 지점 재확인

- 우리가 STEP 1에서 넣은 `factor *= class_factor_[classification()]` 줄의 **현재 위치**(파일:줄). 새 페널티(속도/곡률/bridge)도 그 인접에 같은 패턴으로 들어갈 것이므로 정확한 좌표 확보.
- `EdgeCost()`에서 `edge->classification()`, (있다면)`edge->curvature()`, `edge->bridge()`, `edge_speed`가 **모두 같은 스코프에서 접근 가능한지** 확인.

### 5. proto 다음 필드 번호

- `proto/descriptors/options.proto` `Costing.Options`에서 우리가 추가한 `class_factors = 97` 이후 **다음 사용 가능 필드번호**(98~) 확인. 새 파라미터들이 쓸 번호.

## 출력: RECON_FORK_SIGNALS.md

```
# RECON: 포크 패치 #2 신호

## 1. 곡률 신호
- curvature() 존재? 타입/범위/의미 (또는 "없음") — file:line

## 2. bridge/tunnel/length
- 각 접근자 시그니처 — file:line

## 3. 속도
- EdgeCost의 속도 취득 방식 — file:line
- SpeedPenalty 로직 요약 — file:line
- top_speed가 비용에 영향? 시간에만? — 근거 file:line

## 4. 주입 지점
- class_factor 주입 줄 현재 위치 — file:line
- 같은 스코프에서 classification/curvature/bridge/edge_speed 접근 가능 여부

## 5. proto 다음 필드번호
- 98~ 가용

## 6. 종합
- ✅ 직진 페널티 구현 경로: (곡률속성 직접 / 속도 대리 — 어느 쪽 가능한지)
- ✅ 고가 페널티 구현 경로: (bridge() 페널티 가능 여부)
- ✅ 속도 페널티 구현 경로: (기존 SpeedPenalty와 충돌 없이 추가 가능한지)
- ❓ 미확인 / ⚠️ 주의점
```

작성 후 정지. 구현·패치 제안은 하지 말 것.

```

```
