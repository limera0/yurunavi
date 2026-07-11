# RECON_sharp_curve — 급커브(45°+) 전용 안내 누락

작성일: 2026-07-06
브랜치: feat/sharp-curve-voice
상태: 읽기전용 조사. 코드 변경 전.

---

## 문제

Valhalla maneuver type 11(`kSharpRight`)/14(`kSharpLeft`, 45°+ 급회전)가 완만한 회전(9 `kSlightRight`,
10 `kRight`, 15 `kLeft`, 16 `kSlightLeft`)과 **동일한 이벤트·문구·타이밍**으로 발화된다.
모터사이클 투어링 앱 특성상 급커브는 감속이 안전과 직결되는데, 현재는 "우회전입니다"/
"좌회전입니다" 한 마디뿐이라 완만한 회전과 구분이 안 된다.

## 훅 지점

| 파일 | 라인 | 현황 |
|------|------|------|
| `lib/features/navigation/voice_engine.dart` | 12 | `case 14: case 15: case 16: return 'turn_left';` — 급좌회전(14)과 완만한 좌회전(16) 구분 없음 |
| `lib/features/navigation/voice_engine.dart` | 13 | `case 9: case 10: case 11: return 'turn_right';` — 급우회전(11)과 완만한 우회전(9) 구분 없음 |
| `assets/config/guidance_profile.json` | 8-9 | `turn_left`/`turn_right` 이벤트에 별도 tiers 없음 → 최상위 공통 tiers(500/300/50) 사용 |
| `assets/voice_packs/default_ko.json` | 12-16 | `turn_left_*`/`turn_right_*` 템플릿에 감속 경고 문구 없음 |
| `lib/features/navigation/presentation/nav_screen.dart` | 1061-1085 | `_labelForType`: 카드 표시도 type 11/14를 그냥 '우회전'/'좌회전'으로만 표기(구분 없음, 카드 UI는 이번 스코프 밖) |

## Valhalla type 매핑 근거

`/data/projects/valhalla-src/proto/descriptors/directions.proto`:
```
kSlightRight = 9;  kRight = 10;  kSharpRight = 11;
kSharpLeft = 14;   kLeft = 15;   kSlightLeft = 16;
```

## 분류 → 순수로직·책상검사 가능

`eventForType`이 이미 정수 `type`을 받으므로 11/14를 별도 이벤트로 분기하는 것은 기존 ramp/exit
이벤트 추가(6e27c1b~994a08c) 때와 동일한 패턴 — 라우팅 데이터 추가 조회 불필요, 순수 로직+JSON
변경만으로 완결. `sharp_curve.dart` 신규 파일 불필요, 기존 `voice_engine.dart`/`guidance_profile.json`/
`default_ko.json` 3곳만 수정.

## 제안

1. `eventForType`: `case 11: return 'sharp_turn_right';` / `case 14: return 'sharp_turn_left';`로 분리
   (9/10은 `turn_right`, 15/16은 `turn_left` 그대로 유지).
2. `guidance_profile.json`에 `sharp_turn_left`/`sharp_turn_right` 이벤트 추가, tiers는 기존 공통
   tiers(500/300/50)와 동일하게 유지(라이딩 검증 없이 타이밍까지 바꾸는 건 과도한 추정 — 문구만
   먼저 분리하고 타이밍은 실주행 후 조정).
3. `default_ko.json`에 4개 키 추가:
   - `sharp_turn_left_approach`: `"{dist}미터 앞 급좌회전, 감속하세요"`
   - `sharp_turn_left_imminent`: `"급좌회전 주의"`
   - `sharp_turn_right_approach`: `"{dist}미터 앞 급우회전, 감속하세요"`
   - `sharp_turn_right_imminent`: `"급우회전 주의"`
4. `_fast` suffix 분기(voice_engine.dart:62-66)는 `event == 'turn_left' || event == 'turn_right'` 조건이라
   급커브 이벤트는 자동으로 제외됨 — 급커브는 애초에 감속 대상이므로 "곧 좌회전입니다"류 고속 축약
   문구를 만들지 않는 게 맞음(의도적으로 `_fast` 키 미추가).

## 리스크 / 보류 사항

- 타이밍(tier 조정)은 실주행 없이 추정 금지 — 이번 슬라이스는 문구 분리까지만, tier 재조정은
  라이딩 후 피드백 있으면 후속 RECON.
- 카드 UI(`_labelForType`)의 급커브 표기는 이번 스코프 밖(TTS 발화만 대상). 필요 시 별도 티켓.
