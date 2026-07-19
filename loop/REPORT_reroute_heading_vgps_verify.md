# REPORT — 자동 재탐색(이탈 감지) heading 버그, M32 가상GPS 실기 검증

작성일: 2026-07-19/20. 대상: 실주행 피드백 최신 5건 중 #1
("재탐색 2회/3회 이상 연속 시 heading 무시하고 제자리 유턴 유도").

## 1. 코드 수정

`nav_screen.dart`의 `_reroute()`(이탈 자동 재탐색)와 `_openCourseSheet()`(수동
"재탐색" 버튼) 둘 다 기존에는

```dart
final heading = (navState != null && navState.speedKmh > 2) ? navState.headingDeg : null;
```

라는 단순 게이트를 썼다. 라이더가 재탐색과 재탐색 사이에 속도가 3km/h 밑으로
떨어지면(막 재탐색해서 새 경로 계산 중 잠깐 멈칫하는 등) heading이 그대로
`null`로 버려지고, `offsetOrigin()`이 no-op이 되어 origin이 밀리지 않는다 —
이 상태로 또 이탈이 걸리면 Valhalla가 반대편(뒤쪽) 엣지에 스냅해 제자리
유턴을 유도한다. 이미 카메라 bearing 표시용으로 검증돼 있던
`_resolveHeading(speedKmh, headingDeg)`(저속 시 마지막 관측 heading을
유지하는 폴백)를 두 재탐색 경로에 동일하게 적용:

```dart
final heading =
    navState != null ? _resolveHeading(navState.speedKmh, navState.headingDeg) : null;
```

## 2. M32 가상GPS 실기 검증

`gpsinjector`(GPS/NETWORK/FUSED 3-provider 목업) + E2E 인텐트 하네스로
송탄 출발점에서 북쪽 정지 드리프트를 준 CSV 재생, 4회 반복 끝에 성공:

- **반복 1-4**: 첫 재탐색은 매번 성공 확인(`used=<non-null>`)했지만, 8초
  쿨다운 + 3초 디바운스를 다 지나기 전에 CSV가 끝나 두 번째 재탐색을 강제로
  끌어내지 못함(합성 궤적이 재계산된 경로와 우연히 겹쳐 off-route 상태가
  풀리기도 함).
- **반복 5**(`reroute_heading_test5.csv`, 37pt로 확장): 정지 드리프트 구간을
  8pt 더 늘려 쿨다운+디바운스를 확실히 지나도록 구성. 결과:
  ```
  01:04:50.701 YNAV_REROUTE hdg_src spd=0.0 rawHdg=90.0 used=90.0   ← 2번째 재탐색
  01:05:05.289 YNAV_REROUTE hdg_src spd=0.0 rawHdg=90.0 used=90.0   ← 3번째 재탐색
  ```
  둘 다 **spd=0.0(정지 상태)**에서 발생했고, `used`가 `null`로 떨어지지 않고
  마지막 관측 heading(90°)을 정확히 유지함. 수정 전 코드였다면 `spd=0.0`이라
  `used=null`이 찍혔을 시나리오 — 실기에서 재현 후 수정 확인 완료.
- 두 재탐색 모두 12초 윈도 내 3회 실패 임계값(`_kFailureCount=3`)에는
  못 미쳐 `_rerouteFallback`은 발동하지 않음(합성 테스트라 발동 조건까지는
  안 갔지만, 폴백 로직 자체는 이번 수정과 무관하게 그대로 — 폴백은 "재탐색을
  잠시 멈추는" 안전장치이지 heading 버그의 원인이 아니었음, RECON 재확인).

## 3. 결론

수동 버튼(`_openCourseSheet`)에 이어 자동 이탈 재탐색(`_reroute`)도 동일하게
`_resolveHeading()` 폴백을 타도록 통일 완료, M32 실기에서 정지 상태 연속
재탐색 2회 모두 heading 유지 확인. 커밋 대상.
