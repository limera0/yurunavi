# YuruNavi STATUS — Claude 세션 진입점

> **자동 생성 파일이다. 직접 편집하지 마라 — `loop/gen_status.sh` 다음 실행에 덮어써진다.**
> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다.
> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라
> (예: `sed -n '161,183p' loop/RELEASE_ROADMAP.md`). 로드맵을 통째로 읽지 마라.

생성: 2026-07-31 04:47 · 브랜치 `verify/ride-0711` · HEAD `ac3d484`

## 1. 지금 상태

- 야간루프: 정지
- 마지막 handoff: `STATUS: DONE` (갱신 2026-07-29 14:34)
- 작업트리: **미커밋 27건** — 다른 세션 작업일 수 있으니 `git status`로 확인 후
  내 파일만 골라 스테이징할 것(CLAUDE.md 하드룰: `git add -A` 금지)

## 2. 미완료 릴리스 항목

`loop/RELEASE_ROADMAP.md`의 `### N.` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다.

- **10. 실제 release build 검증**  —  `RELEASE_ROADMAP.md:259`
- **11. 하드코딩 스타일 → 토큰 기반 전면 리팩터 — PARTIAL**  —  `RELEASE_ROADMAP.md:265`
- **18번 — 후면단속카메라 안내 — PARTIAL (구현 완료, 실기기 시각 검증 남음)**  —  `RELEASE_ROADMAP.md:783`
- **19번 후속 (2026-07-30, 같은 날 저녁 세션) — 고급휘발유 99999 버그 수정 + 지도 검색창 진입점 추가**  —  `RELEASE_ROADMAP.md:850`
- **20. 위치정보 확인자료 로깅 구현**  —  `RELEASE_ROADMAP.md:897`

## 3. 최근 실행 결과

- [MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md](MORNING_REPORT_0730_gasstation_search_chip_and_premium_bug.md)
  - *목표 달성 판정:** 원래 목표: 지도 검색창 주유소 단독 선택 시 오피넷 가격순 전환 + 고급휘발유
- [MORNING_REPORT_0730_ufw_fail2ban_done.md](MORNING_REPORT_0730_ufw_fail2ban_done.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_
- [MORNING_REPORT_0730_access_log_and_ufw_prep.md](MORNING_REPORT_0730_access_log_and_ufw_prep.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_

## 4. 최근 작업 지시서

- [HANDOFF_0731_layout_batch2_map_course_flow.md](HANDOFF_0731_layout_batch2_map_course_flow.md)
- [HANDOFF_0730_renderflex_overflow_fix.md](HANDOFF_0730_renderflex_overflow_fix.md)
- [HANDOFF_0730_gasstation_search_chip_and_premium_bug.md](HANDOFF_0730_gasstation_search_chip_and_premium_bug.md)

## 5. 최근 커밋

```
ac3d484 docs(roadmap): 22번(투어 진단 로그) 신규 기록 + release 설치·스모크테스트 결과 반영
4c8cd03 feat(logging): 투어 진단 로그 커버리지 확대 (20번 관련, 500km 실주행 대비)
f0f69b1 chore(status): STATUS.md 재생성 (14번 완료, 라운드1 반영)
0619872 docs(roadmap): 14번(RenderFlex overflow) 완료 반영 — 전수감사 DONE 전환
d8d00b0 fix(nav): 주유소 시트 제목 Row RenderFlex overflow 수정 (14번 신규 건)
0ab4807 fix(splash): 스플래시 태그라인 삭제 + 하단 내비게이션 바 색상 통일 (라운드1)
b6695a6 docs: 라운드17(앱 종료 확인 카드) 구현완료 반영
9254a79 feat(map): 앱 종료 시 확인 카드 도입 (라운드17)
e85d637 docs: 라운드10-2→11→12(히스토리 화면) 구현완료 반영
2b8c393 feat(history): 공유 이미지 카드+지도 정사각/세로형 캡처 + 메모 클립보드 전환 (라운드12)
```

## 6. 더 깊이 볼 때

- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)
  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것.
- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)
- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)
- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)
