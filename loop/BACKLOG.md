# 유루나비 루프 백로그 (단일 상태 소스)

tick은 READY 맨 위부터 선행조건 충족된 작업 1개를 집는다.
유형: RECON(읽기전용) / T1·T2(객관 검증→auto-merge) / T3(라이딩 검증 필요→머지 금지)
작업 전 관련 SPEC_*.md를 읽고 RECON과 대조. 충돌 시 SPEC 우선.

## READY
- [x] **RECON-tts-pack** (RECON) 팩 구조 착수 전 정찰 ✓ 2026-06-16
  - 산출물: loop/RECON_tts_pack.md 생성 완료
  - 발화 지점 8개 전수, 변경 파일 1개(nav_screen.dart) + 신규 2개, 단일커밋 불가(2커밋 권장)
- [x] **TTS-PACK** (T2/설계) 음성안내 팩 구조 모듈화 ✓ 2026-06-16
  - 산출물: VoicePackService + default_ko.json, nav_screen 8곳 재배선, main 머지 완료
  - SPEC §4 전 항목 PASS + analyze No issues
- [ ] **RECON-heading** (RECON) 증상3 재탐색 heading 미전달
  - 산출물: RECON_reroute.md §D 기준, Valhalla 포크 heading 수용 curl A/B
  - 선행조건: 없음

## RIDING_QUEUE (구현 완료 · 라이딩 검증 대기 · main 머지 금지)
phase1/startup-accuracy / feat/guidance-fix 에 존재. main 미반영(2026-06-17 확인).
- [ ] type18 아이콘 반전 + type17 불일치 (65528b7) — 카드 아이콘 방향 육안 확인
- [ ] 카드 off-by-one (2048379) — 접근 중 교차로 표시 맞는지
- [ ] 카드 거리 live remaining (0195e6d) — 틱마다 갱신되는지
- [ ] Seoul 카메라 flicker (initState 162-167) — 진입 시 떨림 없는지
- [ ] _lastAnnouncedIdx=0 회귀 점검 (903715f) — 재탐색 후 카드·TTS 리빌드 정상? (06-15 증상4 회귀 여부)
- [ ] T3 2단 안내 카드 재설계 — 미착수, 라이딩 가능 세션에서

## DONE (main 반영 완료)
- **RECON-tts-pack** (RECON) ✓ 2026-06-16 — loop/RECON_tts_pack.md
- **TTS-PACK** (T2/설계) ✓ 2026-06-16 — VoicePackService + default_ko.json + nav_screen 재배선
