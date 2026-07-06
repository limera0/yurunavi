# REPORT — #5 TTS 가청성 (usage 내비 + focus/덕킹) — 리베이스판

브랜치: `feat/tts-audibility-v2` (main에서 재분기, T3 — 라이딩 검증 전 병합 금지)
근거: `loop/RECON_tts_volume.md`

기존 `feat/tts-audibility` 브랜치(main 대비 44 커밋 divergence로 정리 필요)에서 실제
동작에 필요한 커밋 3개만 현재 main 위로 cherry-pick. 코드 변경 내용은 원본과 동일, 리스크
재검토·재작성 아님.

## 변경 사항

1. `loop/RECON_tts_volume.md` 신규 — usage/focus 미설정 확인 조사 (커밋 `cba3808`, 원본 `33aa6d4`).
2. `lib/features/navigation/presentation/nav_screen.dart:407` `_initTts()` —
   `setVolume(1.0)` 다음 줄에 `await _tts!.setAudioAttributesForNavigation();` 추가.
   → TTS 발화가 `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` 스트림으로 라우팅, 미디어 볼륨과 분리.
   커밋: `12a2809` (원본 `07feb5b`)
3. `lib/services/voice_pack_service.dart:36` —
   `await _tts.speak(text);` → `await _tts.speak(text, focus: true);`
   → 발화 시 `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` 요청, 배경음(음악 등) 있으면 덕킹.
   커밋: `ff64619` (원본 `98b71b0`)

네이티브 코드 변경 없음 (flutter_tts 4.2.5 기존 API만 사용).

## 테스트

- `flutter analyze`: 0 (main이 이번 세션에 `d9d78d5` 반영으로 사전 이슈 4개 정리된 상태라
  이 브랜치도 신규 0/기존 0).
- `flutter test`: 전체 통과 (아래 실행 로그 참고). VoicePackService.speak 시그니처 불변이라
  기존 voice 테스트 영향 없음 확인됨.
- 플랫폼 채널(TTS 오디오 usage/포커스) 의존이라 가청성 자체는 유닛테스트로 검증 불가 —
  원본 RECON 때부터 알려진 한계, 이번 리베이스에서도 동일.

## 라이딩 검증 체크리스트 (미완료 — 실기 필요)

- [ ] 고속 주행 중 발화가 이전보다 크게/명확하게 들리는가
- [ ] 터널 등 소음 환경에서 가청성 개선 체감되는가
- [ ] 배경음악 재생 중 발화 시 음악이 덕킹(감쇠)되는가
- [ ] 일부 기기에서 내비게이션 스트림 볼륨이 미디어 볼륨보다 낮게 설정되어 있어
      오히려 이전보다 작게 들리는 회귀가 없는가 (기기별 내비 볼륨 슬라이더 확인 필요)

## 결론

analyze/test 게이트 통과. main 병합 금지(T3) — 위 체크리스트 PASS 후 `feat/tts-audibility-v2`에서
개별 main 머지. 다음 단계로 `verify/ride-0706`에 6번째 브랜치로 merge, 내일(2026-07-07)
새벽 퇴근길에 5개 기존 기능과 함께 한 번에 검증 예정(사용자 지시, 2026-07-06).

## 남겨둔 것 (범위 밖)

옛 `feat/tts-audibility` 브랜치는 그대로 둠(삭제 안 함) — TTS 커밋 3개 외에 무관한
docs-only 커밋 3개(사유지 도로 회피 조사/게이트 태깅 PoC/오버레이 파이프라인 설계)가
얹혀 있음. 이번 작업 범위 밖이라 별도로 처리 필요(다음 세션 후보로 기록).
