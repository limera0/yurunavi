# 정찰 프롬프트 — 코스 차별화 A안(Valhalla FC 인지형 커스텀) 설계용

> **실행 환경:** Claude Code, Sonnet 4.6, 읽기전용. /goal 무인 가능.
> **목표:** A안(Valhalla costing 자체를 FC 등급 인지형으로 커스텀)을 설계하기 위한 사실관계만 수집. 구현·수정은 절대 하지 않는다.

---

## 🚫 절대 규칙 (위반 시 즉시 중단)

- **읽기전용.** `grep`, `cat`, `view`, `ls`, `find`, `git log/show/blame`(읽기만)만 사용한다.
- **금지:** 파일 수정/생성/삭제(단 하나의 예외 = 아래 `RECON_COURSE_A.md` 작성만 허용), `git add/commit/push`, `flutter build`/`analyze`, `docker`/`systemctl`/서비스 재시작·재설정, 실행 중 서비스(valhalla/tiles/navi)로의 네트워크 요청(curl 포함).
- **추측 금지.** API·필드·함수 시그니처는 반드시 실제 파일에서 확인해 인용한다. 추측한 내용은 "⚠️추측"으로 명시한다.
- 모든 코드 인용은 **`파일경로:줄번호`** 를 붙인다.
- 작업 끝에 **`/data/projects/yurunavi/RECON_COURSE_A.md` 한 파일만 작성**하고 **정지**한다. 다른 어떤 것도 하지 않는다.

---

## 수집 항목 (5개)

### 1. Valhalla 배포 실태 (A안 실현 가능성의 핵심)
- Valhalla가 **어떻게 기동되는지**: docker-compose.yml / Dockerfile / 기동 스크립트 / `/data/valhalla/` 내 config json 등을 찾아 확인.
- **이미지 이름과 태그/버전**, 스톡 공식 이미지인지 이미 커스텀된 것인지.
- valhalla **config json 경로**와 사용 중인 **costing 모델 관련 설정**(service_limits 등).
- 프로젝트 내에 Valhalla **소스/빌드 관련 파일이 존재하는지**(있으면 경로, 없으면 "없음" 명시 — A안은 별도 valhalla 소스 클론이 필요해짐).

### 2. 현재 라우팅 요청의 실제 내용 (수정 대상 베이스라인)
- `lib/features/.../routing_service.dart`(메모상 line ~75 costing_options)에서:
  - Valhalla로 보내는 **costing 모델**이 정확히 무엇인지 (`auto` / `motorcycle` / `motor_scooter` / 기타).
  - **세 코스(시골길/지방도/국도) 각각에 보내는 costing_options JSON을 그대로(verbatim)** 추출. "class_factors"의 실체가 use_highways/use_primary인지, 다른 무엇인지 확정.
  - `alternates` 파라미터 사용 여부.

### 3. Rust 스코어링 레이어 실태 (곡률·골프 보너스가 들어갈 자리 + fun score)
- `native/src/api.rs`, `native/src/main.rs`에서:
  - `rank_candidates_v2`, `fun_score_v3`가 **실제로 존재하는지**. 존재하면 **함수 시그니처와 입력/반환 타입을 verbatim** 인용.
  - 이들이 **무엇을 계산하는지**: FC 등급 구성비? 곡률? 그냥 Valhalla alternate 정렬? 실제 로직 요약.
  - 이 결과가 **Flutter로 반환되는지, 아니면 버려지는지**(미연결 여부) — 호출 경로 추적.

### 4. 분석문서 주장 대조 (검증/반박용)
- `docs/course_analysis/01_current_state`, `02_valhalla_costing`, `03_funroad_design`, `04_roadmap`, `MORNING_REPORT_COURSE.md`에서:
  - 주장 ①(class_factors 작동, "3코스 15.4/15.9/17.2km 다른 geometry, Night7 curl")의 **근거가 된 실제 테스트 좌표/요청**이 문서에 기록돼 있는지. 있으면 그 좌표를 그대로 인용.
  - 04_roadmap의 **"가장 먼저 칠 한 커밋"** 권고 원문(짧게 인용).
  - 각 문서에서 "확정 사실"로 적힌 것과 "분석가 해석/추측"으로 적힌 것을 구분.

### 5. 경로 응답의 도로 등급 정보
- 코드 어딘가에서 Valhalla route 응답의 **road class / `road_class` / `use` 같은 등급 필드를 요청하거나 파싱**하는 곳이 있는지 (검증·스코어링에 활용 가능 여부).

---

## 출력: `RECON_COURSE_A.md` 구조

```
# RECON: 코스 차별화 A안 설계 정찰

## 1. Valhalla 배포 실태
(이미지/태그/기동방식/config경로/소스존재여부 — file:line 인용)

## 2. 현재 라우팅 요청
(costing 모델 + 세 코스 costing_options verbatim — file:line)

## 3. Rust 스코어링 레이어
(rank_candidates_v2/fun_score_v3 시그니처·로직·연결여부 — file:line)

## 4. 분석문서 주장 대조
(주장 ① 근거 좌표 / 04_roadmap 첫커밋 원문 / 사실 vs 해석 구분)

## 5. 경로 응답 등급 정보
(road class 파싱 여부 — file:line)

## 6. 종합
- ✅ 확인된 사실:
- ❓ 미확인(코드에서 못 찾음):
- ⚠️ 분석문서가 추측이었던 것:
- 🔧 A안 진행 시 추가로 필요한 것(예: valhalla 소스 클론 위치 등):

## 부록: 마스터가 직접 실행할 검증 (자동 실행 금지)
- (실행 중 Valhalla 동작을 확인할 수 있는 read-only curl 명령 후보를 적되, 직접 실행하지 말고 명령만 제시)
```

작성 후 **정지**. 구현 제안이나 코드 수정은 하지 않는다.
