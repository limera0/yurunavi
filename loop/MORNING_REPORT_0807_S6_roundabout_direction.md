# MORNING REPORT — S6 로터리 안내 재설계

- 작성 2026-08-07 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0807_S6_roundabout_direction.md](HANDOFF_0807_S6_roundabout_direction.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S6

---

## 뭐가 됐나

커밋 `be54f5b`. Valhalla `roundabout_exit_count`가 검단회전교차로 6개 조합 전부에서
`2`를 반환하는 결함(공개 업스트림 Valhalla도 동일 — 앱/포크 결함 아님, 이전 세션에서
확정)에 대응해, 출구 번호 발화를 완전히 폐기하고 **경로 shape의 진입/진출 방위차**로
좌/직/우를 계산해 안내하도록 바꿨다.

- 착수 전 로컬 prod Valhalla(`localhost:8002`)에 검단회전교차로 주변 5개 진입/진출
  조합(N/S/E/W 250m 지점 조합, 6번째 S→N은 로터리를 안 거치는 경로가 나와 제외)을 직접
  curl로 프로브해 알고리즘이 실제로 동작하고 좌/직 두 버킷에 고르게 나뉘는 것까지 확인한
  뒤 구현에 들어갔다.
- `PoiService.signedBearingDiff` 신설(부호 있는 -180~180 방위차,
  `((to-from+540)%360)-180`). 프로브 5개 값 전부와 일치 확인.
- `RoutingService.RoundaboutDirection{left,straight,right}` + `labelKo` +
  `classifyRoundaboutDirection`(±45° 임계값) — **기존 `CurveDirection`(급커브 좌/우
  판정)과 동일 부호 관례**를 그대로 따르게 만들어 코드베이스 안에서 좌/우 규약이
  갈리지 않게 했다.
- `voice_engine.dart` — `roundabout_enter`의 출구번호 주입을 방향 계산으로 교체.
  진입(type26)-진출(type27) maneuver를 페어링해 진입 직전/진출 직후 방위각을 구하고,
  실패(페어링 안 됨·경계 밖)하면 방향 없는 일반 문구로 안전하게 폴백한다.
  **이미 S4b로 비활성화돼 죽어 있던 `roundabout_exit && isImminent` 블록**(또 다른
  `{exit}` 주입 경로)도 이번에 통째로 삭제 — JSON 설정 하나에만 기대지 않는 이중 차단.
- `default_ko.json` — 실제 도달 가능한 `{exit}` 템플릿 **2종**(체크리스트 원문의 "4종"은
  재확인 결과 정정됨 — `roundabout_exit` 계열은 이미 비활성화라 처음부터 도달 불가였다)을
  `{direction}` 기반으로 교체.

## 검증

- `flutter analyze`: 이슈 0
- `flutter test`: **456건 전건 통과**
- code-auditor: **1차 PASS**(수정 없이) — 부호 관례 일치, 페어링 실패 폴백 4종 전부 실제
  도달 확인, `{exit}` 완전 제거를 JSON 설정이 아닌 코드 레벨로도 재확인(합성 프로필로
  `roundabout_exit`를 강제로 켜봐도 `{exit}` 주입 경로 자체가 없음을 검증)

## 참고 (감사 부수 발견, 이번 스코프 밖)

`nav_screen.dart`의 화면 카드 텍스트(`_maneuverText`, type 26)는 여전히
`roundaboutExitCount`를 "회전교차로 N번째 출구"로 **화면에** 표시한다. 이번 S6는
지시서상 TTS(발화)만 스코프였다 — 신뢰 불가로 확정된 값을 화면에는 여전히 보여준다는
뜻이라 후속 조치가 필요할 수 있다.

## 잔여 — 정확성 실측 대조 (마스터 확인 필요)

이 세션은 헤드리스 서버라 위성지도를 볼 수 없다. 알고리즘이 "동작한다"는 건 확인했지만
"실제 지형과 일치한다"는 건 지도 육안 대조나 실기기 주행으로만 확정 가능하다.

| 조합 | entry bearing | exit bearing | signed turn | 판정 |
|---|---|---|---|---|
| S→E | 56.2° | 64.6° | +8.4° | 직 |
| S→W | 56.2° | 265.3° | −150.9° | 좌 |
| N→S | 171.7° | 154.2° | −17.5° | 직 |
| E→W | 254.4° | 265.3° | +10.9° | 직 |
| W→N | 56.2° | 315.1° | −101.1° | 좌 |

지도에서 눈으로 대조 가능하면 이 판정들이 실제 방향과 맞는지 확인 부탁.

---

**목표 달성 판정:** 원래 목표: 신뢰할 수 없는 `roundabout_exit_count` 기반 출구 번호
발화를 완전히 폐기하고, 경로 shape의 진입/진출 방위차를 직접 계산해 좌/직/우로 안내한다.
/ 달성: **코드 완료 — yes**. 실제 지형과의 일치 여부는 지도 육안 대조가 필요해
**마스터 확인 대기**.
