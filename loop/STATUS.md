# YuruNavi STATUS — Claude 세션 진입점

> **자동 생성 파일이다. 직접 편집하지 마라 — `loop/gen_status.sh` 다음 실행에 덮어써진다.**
> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다.
> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라
> (예: `sed -n '161,183p' loop/RELEASE_ROADMAP.md`). 로드맵을 통째로 읽지 마라.

생성: 2026-07-22 17:50 · 브랜치 `verify/ride-0711` · HEAD `0929c47`

## 1. 지금 상태

- 야간루프: 정지
- 마지막 handoff: `STATUS: CONTINUE` (갱신 2026-07-20 20:46)
- 작업트리: **미커밋 8건** — 다른 세션 작업일 수 있으니 `git status`로 확인 후
  내 파일만 골라 스테이징할 것(CLAUDE.md 하드룰: `git add -A` 금지)

## 2. 미완료 릴리스 항목

`loop/RELEASE_ROADMAP.md`의 `### N.` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다.

- **6. 개인정보처리방침 초안 + 호스팅 — PARTIAL**  —  `RELEASE_ROADMAP.md:172`
- **8. 브랜드 방향성 확정**  —  `RELEASE_ROADMAP.md:220`
- **9. 앱 아이콘 확정**  —  `RELEASE_ROADMAP.md:229`
- **10. 실제 release build 검증**  —  `RELEASE_ROADMAP.md:232`
- **11. 하드코딩 스타일 → 토큰 기반 전면 리팩터**  —  `RELEASE_ROADMAP.md:238`
- **14. Crashlytics fatal 오분류 전수 감사 — PARTIAL (A/C 완료, B/D 남음)**  —  `RELEASE_ROADMAP.md:561`

## 3. 최근 실행 결과

- [MORNING_REPORT_0722_skin_infra.md](MORNING_REPORT_0722_skin_infra.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_
- [MORNING_REPORT_0722_night.md](MORNING_REPORT_0722_night.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_
- [MORNING_REPORT_0720_auto.md](MORNING_REPORT_0720_auto.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_

## 4. 최근 작업 지시서

- [HANDOFF_0722_waypoint_mgmt.md](HANDOFF_0722_waypoint_mgmt.md)
- [HANDOFF_0722_skin_infra.md](HANDOFF_0722_skin_infra.md)
- [HANDOFF_0720_night_14_16.md](HANDOFF_0720_night_14_16.md)

## 5. 최근 커밋

```
0929c47 docs(loop): WIKI_INDEX.md 최초 생성 — RECON/REPORT 152건 날짜순 큐레이션
5c2a238 fix(loop): REPORT_reroute_merge.md 줄바꿈 깨짐 복구
23b058b chore(cleanup): 루트 폴더 과거 RECON/REPORT/지시서/로그 archive로 분류
a991589 feat(discord-bot): 봇 명령 인증을 지정 채널 1개 → 길드 전체로 확대
cf7f02f feat(loop): CLAUDE.md 워크플로 A/B/C 실제 배선
ad45a69 docs(claude): 하이브리드 실행 모델로 재작성 + 개조식 영어 간소화
09dcf05 docs(roadmap): 17번 DONE — 경유지 관리 UI Phase 0~4 완료 기록
43b5c31 feat(waypoint): Phase 4 — 코스 시트 경유지 관리 진입점 UI
f6b021c feat(waypoint): Phase 3 — 검색 결과에서 출발지/경유지/목적지 선택
26e5c4a feat(waypoint): Phase 2 — WaypointManagementSheet (드래그 재배치 + 즉시 경로 재계산)
```

## 6. 더 깊이 볼 때

- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)
  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것.
- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)
- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)
- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)
