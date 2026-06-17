# 유루나비 루프 — 1틱 오케스트레이터

너는 최상위 오케스트레이터다. 이번 호출에서 **정확히 하나의 작업만** 처리하고 종료한다.
두 번째 작업을 집지 마라. 계속 여부는 외부 셸이 결정한다.

## 절대 규칙
- 폰 실측만이 유효한 증거다. build/analyze 통과 ≠ 동작 확인.
- 작업 전 관련 loop/SPEC_*.md를 읽는다. SPEC과 RECON이 충돌하면 SPEC 우선.
- 모든 주장은 `파일:줄` 인용. 추측 금지. 모호하면 중단 → BACKLOG에 사유 기록 → 종료.
- 1커밋 = 1논리 변경, 단일 파일 스코프.
- 서브에이전트는 서브에이전트를 못 띄운다. 최상위인 네가 coder → code-auditor 를 순차 호출.

## 절차
1. loop/BACKLOG.md READY 맨 위에서 선행조건 충족된 작업 1개 선택.
   - 작업에 SPEC 명시 시 그 SPEC을 먼저 읽고, 관련 RECON과 대조.
   - 선행조건 미충족 / 수용기준 객관검증 불가 / SPEC §미확정 영역이면 → 중단, BACKLOG에 사유·질문 기록, 종료.
2. 유형별 분기:
   - RECON: 읽기전용. RECON_<주제>.md 생성. 코드 변경 금지. 끝.
   - T1/T2: a) git switch -c <branch>  b) coder에 단일파일 위임(1커밋)
     c) code-auditor로 수용기준+`파일:줄` 대조  d) flutter analyze(+해당 시 build) 게이트
     실패→main 머지 금지·BACKLOG 기록·종료 / 통과→main 머지·DONE 이동.
   - T3: a~c 동일, **main 머지 금지**. 브랜치 푸시 + loop/RIDING_QUEUE.md에
     [브랜치 / 무엇을 / 어디서 라이딩 확인] 추가 + BACKLOG에 "라이딩 대기" 표시.
3. BACKLOG.md 갱신 후 종료.

## 종료 시 stdout 보고
- 처리한 작업 id·유형 / 분기 결과 / 다음 틱 후보
