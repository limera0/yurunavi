# REPORT_voice_v2A — 음성 v2 슬라이스 A (R1+R2+R3) 완료 보고

작성일: 2026-06-30
브랜치: feat/ic-early-guidance (main 머지 금지 — T3, 라이딩 검증 대기)
앵커: loop/RECON_voice_v2.md 슬라이스 A

---

## 커밋 (4개, 1커밋=1논리)

| 커밋 | 메시지 | 파일 |
|------|--------|------|
| a3582b5 | feat(voice): near-dest cue 10m + phrase 부근 | guidance_profile.json, guidance_profile.dart, default_ko.json |
| d70d7f4 | feat(voice): speed-aware imminent turn phrasing | voice_engine.dart, default_ko.json, voice_pack_service.dart |
| 712ac56 | feat(voice): pass speed to voice engine | nav_screen.dart |
| ba9a1d6 | test(voice): speed-aware imminent phrasing | test/voice_engine_speed_test.dart |

## 변경 file:line

- `assets/config/guidance_profile.json:4` — `"imminent_m": 5` → `10`
- `lib/features/navigation/guidance_profile.dart:30` — fallback `imminentM: 5` → `10`
- `assets/voice_packs/default_ko.json:28` — `"destination_imminent": "목적지 도착"` → `"목적지 부근입니다"` (R2+R3 동일 키)
- `assets/voice_packs/default_ko.json:10` — `"arrival": "목적지에 도착했습니다"` 불변 확인
- `lib/features/navigation/voice_engine.dart:32` — `onProgress(...)`에 `{double speedKmh = 0}` 추가
- `lib/features/navigation/voice_engine.dart:54-62` — imminent phase에서 `turn_left`/`turn_right` + `speedKmh >= 20`이면 `_fast` suffix
- `assets/voice_packs/default_ko.json:13,16` — `turn_left_imminent_fast`/`turn_right_imminent_fast` 키 추가
- `lib/services/voice_pack_service.dart:20-27` — `resolveTemplate`: `_fast` 키 미존재 시 베이스 키로 폴백 (신규 헬퍼, 단위 테스트 대상)
- `lib/features/navigation/presentation/nav_screen.dart:241-243` — `onProgress` 호출에 `speedKmh: ref.read(navStateProvider)?.speedKmh ?? 0` 전달 (단 1지점)

## 테스트 결과

`flutter test test/voice_engine_speed_test.dart test/voice_engine_test.dart` → **13/13 green**

- 신규 (voice_engine_speed_test.dart, 4건):
  1. turn_left speed 25 → `turn_left_imminent_fast` ✅
  2. turn_left speed 10 → `turn_left_imminent` (suffix 없음) ✅
  3. turn_right speed 30 → `turn_right_imminent_fast` ✅
  4. `_fast` 키 없는 팩 → `resolveTemplate`이 베이스 키로 폴백 ✅
- 회귀 (voice_engine_test.dart, 9건): 전건 green, 시그니처 확장으로 인한 호출부 영향 없음.

## flutter analyze

신규 에러 0건. 기존 경고 4건(`route_progress_provider.dart` unused field 2건, `settings_screen.dart` deprecated_member_use 2건)은 본 슬라이스와 무관, 변경 전부터 존재.

## 라이딩 체크리스트 (T3 — main 머지 전 폰 실측 필수)

- [ ] 고속(≥20km/h) 좌/우회전 임박 시 "곧 좌회전입니다" / "곧 우회전입니다" 발화 확인 (저속 시 기존 "좌회전입니다"/"우회전입니다" 유지 확인)
- [ ] 목적지 10m 이내 진입 시 "목적지 부근입니다" 발화 확인 (5m 임계 변경 체감 — 너무 이르거나 늦지 않은지)
- [ ] 목적지 도착(잔여 25m, `prog.arrived`) 시 "목적지에 도착했습니다" 발화 확인 (부근 문구와 중복/충돌 없는지)
- [ ] 위 3건 확인 후 BACKLOG 갱신 → main 머지

## 보류 (이번 슬라이스 범위 외)

- R4 (사거리 직진), R5 (지하차도 진출) — RECON_voice_v2.md 분류상 라우팅/엣지 데이터 필요, 실증 선행 전까지 보류.
