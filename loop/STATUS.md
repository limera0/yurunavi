# YuruNavi STATUS — Claude 세션 진입점

> **자동 생성 파일이다. 직접 편집하지 마라 — `loop/gen_status.sh` 다음 실행에 덮어써진다.**
> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다.
> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라
> (예: `sed -n '161,183p' loop/RELEASE_ROADMAP.md`). 로드맵을 통째로 읽지 마라.

생성: 2026-07-29 12:22 · 브랜치 `verify/ride-0711` · HEAD `0462410`

## 1. 지금 상태

- 야간루프: 정지
- 마지막 handoff: `STATUS: DONE` (갱신 2026-07-28 16:01)
- 작업트리: **미커밋 16건** — 다른 세션 작업일 수 있으니 `git status`로 확인 후
  내 파일만 골라 스테이징할 것(CLAUDE.md 하드룰: `git add -A` 금지)

## 2. 미완료 릴리스 항목

`loop/RELEASE_ROADMAP.md`의 `### N.` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다.

- **9. 앱 아이콘 확정**  —  `RELEASE_ROADMAP.md:245`
- **10. 실제 release build 검증**  —  `RELEASE_ROADMAP.md:248`
- **11. 하드코딩 스타일 → 토큰 기반 전면 리팩터 — PARTIAL**  —  `RELEASE_ROADMAP.md:254`
- **14. Crashlytics fatal 오분류 전수 감사 — PARTIAL (A/C 완료, B/D 남음)**  —  `RELEASE_ROADMAP.md:580`
- **18번 — 후면단속카메라 안내**  —  `RELEASE_ROADMAP.md:741`
- **19번 — 실시간 최저가 주유소 안내**  —  `RELEASE_ROADMAP.md:763`

## 3. 최근 실행 결과

- [MORNING_REPORT_0728_rearcam_data.md](MORNING_REPORT_0728_rearcam_data.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_
- [MORNING_REPORT_0728_multi_stop_ux.md](MORNING_REPORT_0728_multi_stop_ux.md)
  - *목표 달성 판정:** 원래 목표: 다중 경유지 코스 설계 UX 개선 (Phase 1~4 전체) / 달성: 예 — 4개 Phase 모두 완료, analyze PASS, code-auditor PASS
- [MORNING_REPORT_0722_waypoint_privacy.md](MORNING_REPORT_0722_waypoint_privacy.md)
  - _(달성도 판정 줄 없음 — CLAUDE.md 규칙 B 미준수)_

## 4. 최근 작업 지시서

- [HANDOFF_0729_brand_skins.md](HANDOFF_0729_brand_skins.md)
- [HANDOFF_0728_rearcam_ui.md](HANDOFF_0728_rearcam_ui.md)
- [HANDOFF_0728_rearcam_api_endpoint.md](HANDOFF_0728_rearcam_api_endpoint.md)

## 5. 최근 커밋

```
0462410 feat(nav): 후면단속카메라 접근/사후구간 게이지 디자인 재작업 (체크포인트)
ed5d973 fix(nav): 목적지 도착 배너가 회전 안내 카드에 가려지는 문제 수정
4b9cf8e docs: 후면단속카메라 HANDOFF 완료 체크리스트 갱신
589e5b4 feat(nav): 후면단속카메라 TTS 안내 구현 (Phase 3)
56ada4a feat(nav): 후면단속카메라 접근/사후구간 게이지 UI 구현 (Phase 2)
8cba24d feat(nav): 후면단속카메라 탐지 엔진 구현 (Phase 1)
145aba5 feat(data): 후면단속카메라 유닛별 좌표 3583건 변환 (Phase 0)
a3f2216 feat(data): 후면단속카메라 데이터 확보
59012c3 feat(map): WaypointManagementSheet 인라인 경유지 검색 추가 (Phase 4)
ec89981 feat(map): _AddToRouteSheet 가로 3-버튼 레이아웃으로 개선 (Phase 3)
```

## 6. 더 깊이 볼 때

- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)
  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것.
- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)
- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)
- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)
