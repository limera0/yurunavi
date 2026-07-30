# YuruNavi STATUS — Claude 세션 진입점

> **자동 생성 파일이다. 직접 편집하지 마라 — `loop/gen_status.sh` 다음 실행에 덮어써진다.**
> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다.
> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라
> (예: `sed -n '161,183p' loop/RELEASE_ROADMAP.md`). 로드맵을 통째로 읽지 마라.

생성: 2026-07-30 03:34 · 브랜치 `verify/ride-0711` · HEAD `0decff2`

## 1. 지금 상태

- 야간루프: 정지
- 마지막 handoff: `STATUS: DONE` (갱신 2026-07-29 14:34)
- 작업트리: **미커밋 7건** — 다른 세션 작업일 수 있으니 `git status`로 확인 후
  내 파일만 골라 스테이징할 것(CLAUDE.md 하드룰: `git add -A` 금지)

## 2. 미완료 릴리스 항목

`loop/RELEASE_ROADMAP.md`의 `### N.` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다.

- **10. 실제 release build 검증**  —  `RELEASE_ROADMAP.md:259`
- **11. 하드코딩 스타일 → 토큰 기반 전면 리팩터 — PARTIAL**  —  `RELEASE_ROADMAP.md:265`
- **14. Crashlytics fatal 오분류 전수 감사 — PARTIAL (ListTile 건 A~D 전부 완료, RenderFlex overflow 신규 건 미해결)**  —  `RELEASE_ROADMAP.md:595`
- **18번 — 후면단속카메라 안내 — PARTIAL (구현 완료, 실기기 시각 검증 남음)**  —  `RELEASE_ROADMAP.md:772`
- **19번 후속 (2026-07-30, 같은 날 저녁 세션) — 고급휘발유 99999 버그 수정 + 지도 검색창 진입점 추가**  —  `RELEASE_ROADMAP.md:839`
- **20. 위치정보 확인자료 로깅 구현**  —  `RELEASE_ROADMAP.md:886`

## 3. 최근 실행 결과

- [MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md](MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md)
  - *목표 달성 판정:** 원래 목표: 지도 검색창 주유소 단독 선택 시 오피넷 가격순 전환 + 고급휘발유
- [MORNING_REPORT_0730_ufw_fail2ban_done.md](MORNING_REPORT_0730_ufw_fail2ban_done.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_
- [MORNING_REPORT_0730_access_log_and_ufw_prep.md](MORNING_REPORT_0730_access_log_and_ufw_prep.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_

## 4. 최근 작업 지시서

- [HANDOFF_0730_renderflex_overflow_fix.md](HANDOFF_0730_renderflex_overflow_fix.md)
- [HANDOFF_0730_gasstation_search_chip_and_premium_bug.md](HANDOFF_0730_gasstation_search_chip_and_premium_bug.md)
- [HANDOFF_0730_session_end.md](HANDOFF_0730_session_end.md)

## 5. 최근 커밋

```
0decff2 feat(map): 검색창 주유소 단독선택 시 오피넷 가격순 목록으로 전환
5353305 fix(navi): 오피넷 99999 센티널 필터 + B034 미취급 주유소 목록 제외
201dcd8 docs: 19번 후속(검색창 오피넷 전환+고급휘발유 버그) · 14번(오버플로) 핸드오프 작성
63181ca docs(roadmap): 마스터 검증 반영 — 18/19/21번 실제 상태 갱신, 14번 신규 크래시 패턴 기록
b87e28b docs: 21번(운영 서버 보안 강화) 1~5순위 전부 완료 — ufw+fail2ban 마무리
8a339b0 docs: 세션 보고 — 21번 4순위(요청 로깅) 완료, 3/5순위 실행 순서서로 대체
b5a21d7 chore(status): STATUS.md 재생성 (21번 4순위 완료 반영)
1d643ec docs(roadmap): 21번 4순위(요청 로깅) 완료 기록 + 3/5순위 실행 runbook 추가
da5bf40 feat(navi): 요청 접근 로그 미들웨어 추가 (21번 4순위)
02ac8a4 chore(status): STATUS.md 재생성 (Cloudflare 1순위 완료 반영)
```

## 6. 더 깊이 볼 때

- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)
  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것.
- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)
- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)
- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)
