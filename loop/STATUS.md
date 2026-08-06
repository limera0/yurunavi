# YuruNavi STATUS — Claude 세션 진입점

> **자동 생성 파일이다. 직접 편집하지 마라 — `loop/gen_status.sh` 다음 실행에 덮어써진다.**
> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다.
> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라
> (예: `sed -n '161,183p' loop/RELEASE_ROADMAP.md`). 로드맵을 통째로 읽지 마라.

생성: 2026-08-06 04:00 · 브랜치 `verify/ride-0711` · HEAD `d8f2b0b`

## 1. 지금 상태

- 야간루프: 정지
- 마지막 handoff: `STATUS: DONE` (갱신 2026-08-06 01:51)
- 작업트리: **미커밋 38건** — 다른 세션 작업일 수 있으니 `git status`로 확인 후
  내 파일만 골라 스테이징할 것(CLAUDE.md 하드룰: `git add -A` 금지)

## 2. 미완료 릴리스 항목

`loop/RELEASE_ROADMAP.md`의 `### N.` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다.

- **10. 실제 release build 검증**  —  `RELEASE_ROADMAP.md:259`
- **11. 하드코딩 스타일 → 토큰 기반 전면 리팩터 — PARTIAL**  —  `RELEASE_ROADMAP.md:265`
- **18번 — 후면단속카메라 안내 — PARTIAL (구현 완료, 실기기 시각 검증 남음)**  —  `RELEASE_ROADMAP.md:783`
- **19번 후속 (2026-07-30, 같은 날 저녁 세션) — 고급휘발유 99999 버그 수정 + 지도 검색창 진입점 추가**  —  `RELEASE_ROADMAP.md:850`
- **20. 위치정보 확인자료 로깅 구현**  —  `RELEASE_ROADMAP.md:897`

## 3. 최근 실행 결과

- [MORNING_REPORT_0806_S3b_floating_and_notif.md](MORNING_REPORT_0806_S3b_floating_and_notif.md)
  - *목표 달성 판정:** 원래 목표: 시스템 PIP를 폐기하고 네이버지도/카카오내비 스타일의 플로팅 오버레이(아이콘 1탭 → 앱 즉시 복귀)로 재구현하며, 동�
- [MORNING_REPORT_0805_S3_lifecycle.md](MORNING_REPORT_0805_S3_lifecycle.md)
  - *목표 달성 판정:** 원래 목표: 알림창·화면캡쳐·엣지패널만 건드려도 PIP로 튀어 안내가
- [MORNING_REPORT_0805_S2_network_flood.md](MORNING_REPORT_0805_S2_network_flood.md)
  - *목표 달성 판정:** 원래 목표: POI 네트워크 요청 폭주(초당 ~10회, 로그상 69,875건

## 4. 최근 작업 지시서

- [HANDOFF_0806_S3b_floating_and_notif.md](HANDOFF_0806_S3b_floating_and_notif.md)
- [HANDOFF_0805_S3_lifecycle.md](HANDOFF_0805_S3_lifecycle.md)
- [HANDOFF_0806_S1b_continue.md](HANDOFF_0806_S1b_continue.md)

## 5. 최근 커밋

```
d8f2b0b docs: S3b 완료 반영 — 체크리스트 [x]·모닝리포트 (알림 A + 플로팅 오버레이 자체 구현 3청크 완료)
77b2ce8 test(nav): S3b 청크3 — 플로팅 오버레이 라이프사이클 회귀 테스트
7e68a72 feat(nav): S3b 청크2 — 플로팅 오버레이 신규 구현(SYSTEM_ALERT_WINDOW, 아이콘 1탭 복귀)
2ffd233 refactor(nav): S3b 청크1 — PIP·nav_pip_hint 폐기 + geolocator FGS 알림 제거(결정 A)
c1a7847 docs: S3 완료 반영 — 체크리스트 [x]·모닝리포트 (알림 A/C·PIP UX A/B 마스터 결정 대기)
386a2f3 fix(nav): S3 청크3 — 지도 API 호출부 게이트로 MissingPluginException 억제
18da084 fix(nav): S3 청크2 — geolocator wakelock 중복 제거
a5beab1 fix(nav): S3 청크1 — 라이프사이클 오검출 근원 제거 + FGS 재전달 반환
dcc4c29 feat(discord): 대화 세션 크기 상한 + 인수인계 자동 롤오버
ebd5a84 fix(discord): !new 명령 추가 — 대화 세션 무한 누적 방지
```

## 6. 더 깊이 볼 때

- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)
  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것.
- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)
- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)
- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)
