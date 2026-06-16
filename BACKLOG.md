# BACKLOG — YuruNavi

출처: RECON_startup_accuracy.md, RECON_guidance_redesign.md, RECON_direction.md  
갱신: 2026-06-16

---

## READY

### T1 [S] 출발 TTS 발화 개선
**증상**: 내비 시작 시 "2.3km 앞 출발" 발화 — 거리 접두사가 어색함.  
**원인**: `_announceStep(idx)` 에 출발 maneuver(type 1~3, label='출발') 전용 분기 없음.  
**수정**: `step.label == '출발'` 조건 시 '안내를 시작합니다' 발화 (거리 생략).  
**위치**: `lib/features/navigation/presentation/nav_screen.dart:521` `_announceStep`  
**출처**: RECON_startup_accuracy.md §C.2  
**branch**: `fix/tts-departure`

---

### T2 [S] 재탐색 TTS 맥락 구분
**증상**: 경로 이탈 후 재탐색 완료 시에도 "안내를 시작합니다" 발화 — T1 수정 후에도 맥락 불일치.  
**원인**: `_reroute(:499)` 에서 `_announceStep(0)` 호출 → 재탐색 맥락 전달 없음.  
**수정**: `_reroute` 내 `_announceStep(0)` 를 '경로를 재탐색했습니다' 직접 발화로 교체, `_lastAnnouncedIdx=0` 수동 설정.  
**위치**: `lib/features/navigation/presentation/nav_screen.dart:499` `_reroute`  
**출처**: RECON_guidance_redesign.md §TTS 발화 지점  
**branch**: `fix/tts-reroute`

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
