# 정찰 프롬프트 — Valhalla 3.7.0 포크 패치 설계 (class_factors 구현)

> **실행 환경:** Claude Code on Ubuntu(westinx), Sonnet 4.6, 읽기전용 분석. /goal 무인 가능.
> **목표:** Valhalla `3.7.0` 소스에서 `class_factors`(도로 등급별 비용 배수)를 motorcycle costing에 추가하기 위한 **패치 지점 3곳을 실소스로 확정**한다. 코드 수정·빌드는 하지 않는다.
> **배경:** 현재 운영 Valhalla는 스톡 `ghcr.io/valhalla/valhalla` 버전 `3.7.0-5ed7267b7`. 앱이 보내는 `class_factors`는 스톡에 없는 키라 무시됨(curl A/B로 19.51km 동일 확인). 이를 실제로 구현할 포크를 설계 중.

---

## 🚫 절대 규칙 (위반 시 즉시 중단)

- **읽기전용 분석.** 허용된 쓰기는 단 둘: ① 아래 지정한 scratch 디렉터리로의 `git clone`, ② 최종 보고서 `RECON_VALHALLA_FORK.md` 작성. 그 외 **어떤 파일도 수정·생성·삭제 금지.**
- **금지:** 소스 파일 편집, `cmake`/`make`/빌드, `docker`/`systemctl`/실행 중 서비스 조작, 운영 중인 `/data/valhalla/` 건드리기, `git commit`/`push`.
- **추측 금지.** enum 값·proto 필드·함수 시그니처는 **반드시 소스에서 그대로(verbatim) 인용**한다. 인용에는 `파일경로:줄번호`를 붙인다. 못 찾으면 "❓미확인"으로 명시.
- 작업 끝에 `/data/projects/yurunavi/RECON_VALHALLA_FORK.md` **한 파일만 작성**하고 **정지**한다.

---

## 0단계: 소스 확보 (정확한 버전 고정)

```bash
# scratch 위치 (운영 /data/valhalla 와 무관한 별도 디렉터리)
cd /data/projects
# 이미 있으면 재clone 금지, 기존 것 사용
git clone --depth 1 --branch 3.7.0 https://github.com/valhalla/valhalla.git valhalla-src 2>&1 | tail -5
cd valhalla-src
git rev-parse --short HEAD     # 기대: 5ed7267b 와 일치하는지 확인
git describe --tags 2>/dev/null
```

- HEAD short sha가 운영 버전 `5ed7267b7`과 **일치하는지 보고**한다. 불일치 시: 그 사실만 보고하고(추가 fetch는 하지 말 것) 진행 — 3.7.0 태그 기준으로 정찰.
- **서브모듈 받지 말 것**(읽기 전용이라 불필요, 시간 낭비).

---

## 수집 항목 (4개)

### 1. RoadClass enum (FC 매핑의 근거)

- `valhalla/baldr/graphconstants.h`에서 `enum class RoadClass` 정의를 **값과 함께 verbatim** 인용.
  - 각 멤버명과 **정수값**(kMotorway=? kTrunk=? … kServiceOther=?)을 표로.
- 엣지에서 이 값을 얻는 접근자 확인: `DirectedEdge::classification()`이 `RoadClass`를 반환하는지 — `valhalla/baldr/directededge.h`에서 시그니처 인용.

### 2. costing options proto 정의 패턴 (class_factors 필드 추가 위치)

- `proto/options.proto`에서:
  - costing 옵션이 담기는 메시지(예: `Costing.Options` 또는 `CostingOptions`)의 정의를 찾아, **motorcycle/auto가 쓰는 기존 factor 옵션 몇 개**(`use_highways`, `use_tracks`, `use_living_streets`, `top_speed`)가 **어떤 타입·필드번호로 선언돼 있는지** verbatim 인용.
  - proto에 **map 타입 필드가 이미 쓰인 사례가 있는지**(`map<...>`) grep. (class_factors를 `map<uint32, float>`로 넣을지 `repeated`로 넣을지 판단 근거.)
  - 마지막으로 사용된 **필드 번호(최댓값)** 확인 — 새 필드는 그 다음 번호를 써야 함.

### 3. motorcycle costing의 옵션 파싱 + EdgeCost (핵심 패치 지점)

- motorcycle costing 구현 파일 위치 확인: `src/sif/motorcyclecost.cc` (없거나 AutoCost 상속이면 `src/sif/autocost.cc`도 확인).
- **옵션 파싱부**: 요청 JSON의 costing_options를 proto로 읽어들이는 함수(예: `ParseCostingOptions` 또는 생성자에서 `costing_options.use_highways()` 식으로 읽는 부분)를 찾아, **기존 factor 하나(use_tracks 등)가 파싱·저장되는 코드 흐름**을 verbatim 인용. (class_factors를 같은 패턴으로 추가하면 되는지 판단.)
- **`EdgeCost()` 함수**: 시그니처(`Cost EdgeCost(const baldr::DirectedEdge* edge, ...)`)와 **본문에서 비용을 계산·곱하는 부분**을 인용. 특히:
  - `edge->classification()`(또는 등급) 을 본문에서 이미 참조하는지.
  - 기존 factor(예: `use_highways` 의 highway factor)가 **어디서 어떻게 cost에 곱해지는지** — class_factor 배수를 끼워넣을 정확한 지점 후보.
- motorcycle이 AutoCost를 상속한다면, `EdgeCost`가 motorcycle에 오버라이드돼 있는지 / auto 것을 그대로 쓰는지 명시.

### 4. 커스텀 이미지 빌드 경로 (포크 배포 설계용)

- repo 루트/`docker/`에서 **공식 Dockerfile** 위치와, 그것이 소스를 어떻게 빌드하는지 핵심 줄(빌드 커맨드, 베이스 이미지) 인용. (우리 커스텀 이미지를 이 위에 얹을지 판단.)
- `valhalla_service` 바이너리가 빌드되는 CMake 타깃이 어디서 정의되는지 대략 위치만.

---

## 출력: `RECON_VALHALLA_FORK.md` 구조

```
# RECON: Valhalla 3.7.0 포크 패치 설계

## 0. 소스 버전
- clone 경로 / HEAD sha / 운영(5ed7267b7) 일치 여부

## 1. RoadClass enum
- (멤버명 + 정수값 표, file:line) / classification() 접근자

## 2. proto 패턴
- (기존 factor 필드 선언 verbatim, map 사용례, 마지막 필드번호 — file:line)

## 3. motorcycle costing
- (파일 위치 / 옵션 파싱 흐름 / EdgeCost 시그니처·본문 핵심 / class_factor 주입 후보 지점 — file:line)

## 4. 빌드 경로
- (공식 Dockerfile 위치 + 빌드 핵심 줄 — file:line)

## 5. 종합
- ✅ 패치 3지점 확정:
- ❓ 미확인:
- 🔧 다음 단계(구현 설계)에서 결정할 것: (예: class_factors proto 타입, FC1~5↔enum 매핑 확정안, EdgeCost 주입 위치 1곳)
```

작성 후 **정지**. 구현·패치 제안은 하지 않는다(사실 수집만).
