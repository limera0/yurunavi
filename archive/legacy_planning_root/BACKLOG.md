# BACKLOG — YuruNavi

출처: RECON_startup_accuracy.md, RECON_guidance_redesign.md, RECON_direction.md  
갱신: 2026-06-16

**⚠️ 2026-07-17 확인**: 이 파일은 자주 stale함(메모리 `project_yurunavi.md` 경고와 일치).
아래 T1/T2는 실제로는 이미 코드에 반영되어 DONE인데 이 파일만 갱신이 안 돼 있었음(현재
`_announceStep`은 `lib/features/navigation/presentation/nav_screen.dart:707` 부근, 재탐색
분기는 `:659` 부근 — 줄번호가 원래 기록과 다른 건 그 사이 파일이 많이 자라서). 현재 릴리스
준비 작업의 단일 소스는 `loop/RELEASE_ROADMAP.md`이니 이 파일 대신 그쪽을 우선 참조할 것.

---

## READY

### T1 [S] 출발 TTS 발화 개선 — **DONE** (2026-07-17 코드 확인, 커밋 시점 미상)
**증상**: 내비 시작 시 "2.3km 앞 출발" 발화 — 거리 접두사가 어색함.  
**확인**: `_announceStep`이 `step.label == '출발'`일 때 거리 없이 `'departure'` 발화하는
분기가 이미 존재(`nav_screen.dart:712`).

---

### T2 [S] 재탐색 TTS 맥락 구분 — **DONE** (2026-07-17 코드 확인, 커밋 시점 미상)
**증상**: 경로 이탈 후 재탐색 완료 시에도 "안내를 시작합니다" 발화 — T1 수정 후에도 맥락 불일치.  
**확인**: 재탐색 경로에서 `_announceStep(0)` 대신 재탐색 전용 발화로 분기하고
`_lastAnnouncedIdx = 0`을 수동 설정하는 코드가 이미 존재(`nav_screen.dart:659` 부근 주석
"재탐색 맥락 구분: '안내를 시작합니다' 대신 재탐색 메시지 발화").

---

## DONE (이번 phase1 세션)

- ✅ Seoul 카메라 flicker — initState 동기 `_currentPos` 초기화 (lines 162-167)
- ✅ type 18 아이콘 좌우 반전 — 커밋 65528b7
- ✅ type 17 아이콘↔레이블 불일치 — 커밋 65528b7
- ✅ 카드 off-by-one (upcoming 표시) — 커밋 2048379
- ✅ 카드 거리 live remaining 바인딩 — 커밋 0195e6d

---

## RIDING_QUEUE

### T3 [L] 2단 안내 카드 + TTS 전면 재설계
**내용**: 현재 1단 카드(아이콘+거리/레이블)를 2단으로 확장.  
1단: 현재 step 진행 상태 (프로그레스 + 남은 거리)  
2단: 다음 step 예고 (작은 아이콘 + 레이블)  
TTS 타임라인도 카드 구조에 맞게 전면 재설계 필요.  
**이유 보류**: 단일 Row 레이아웃 변경 → 전체 카드 위젯 재작성 필요. 주행 중 테스트([HUMAN]) 필수.  
**출처**: RECON_guidance_redesign.md §2단 카드 얹을 지점  
**예상 크기**: L (3~4시간 + 실기기 검증)
