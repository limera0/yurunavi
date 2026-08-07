# MORNING REPORT — S5 정차 모드 + 전력

- 작성 2026-08-07 (저녁 대화형 세션) · 브랜치 `verify/ride-0711`
- 지시서: [HANDOFF_0807_S5_stationary_mode.md](HANDOFF_0807_S5_stationary_mode.md)
- 체크리스트: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S5

---

## 착수 전 확인 (2026-08-07 대화)

S5~S12(8개 모듈)를 한 번에 검토해 달라는 요청에, CLAUDE.md "모듈당 1세션" 하드룰과 걸리는
지점을 먼저 질문했다.

- **세션 범위** → 우선순위 1개(S5) 선정 후 바로 착수, 나머지는 큐에 남김
- **S5 정차 판정 임계값** → 5km/h 미만 · 10초 지속
- **S9(자동차전용도로 하드배제)** → Valhalla 포크(C++, 레포 밖) 수정이 필요해
  "이 레포로 범위 고정" 하드룰과 충돌 → **이번 스코프 전체 제외**
- **S12(도로 색상)** → 기준 스크린샷 없음 → **마스터 제공 대기, 보류**

---

## 뭐가 됐나

커밋 `fd667f1`. `StationaryDetector`(순수 클래스, 주입 가능 clock) 신설 —
속도 5km/h 미만이 10초 지속되면 정차 모드 진입, 5km/h 이상 회복 시 **즉시**(지연 없이)
해제.

- **정차 중 정지되는 것**: 재탐색 디바운스 타이머 등록(`_triggerReroute()`), 카메라추종
  (`_recenter`), 앰비언트 POI 페치(`_maybeFetchAmbientPois`). 내 위치 마커
  (`_ensureLocationMarker`)는 계속 갱신 — 정차 중에도 파란 점은 살아있다.
- **GPS 다운시프트**: `locationStreamProvider`가 `stationaryModeProvider`를 watch해
  `distanceFilter: 0→15`, `accuracy: bestForNavigation→high`로 전환. 전이 시 Geolocator
  스트림이 재구독된다 — geolocator 플랫폼 구현이 스트림을 캐시해 두는 구조라 dispose 순서가
  틀리면 새 설정이 적용 안 된 낡은 스트림이 재사용될 위험이 있었는데, Riverpod 소스로
  dispose-먼저 순서를 확인하고 실제 플랫폼 채널을 모킹한 통합테스트로 직접 검증했다.
- **재탐색 origin 오프셋**: `40m → 50m` (`nav_screen.dart:846`, `:1702` 두 곳).
- **판단 1건**: 주유소 경유지 추가 시의 재탐색(`_addGasStationWaypoint`)은 사용자가 카드를
  명시적으로 탭해야만 발화하는 1회성 트리거라 게이트 대상에서 제외했다. `YNAV_REROUTE`
  151건/분의 원인인 GPS 지터 자동 재탐색과는 다른 경로이고, 게이트를 걸면 정차 중 사용자가
  요청한 경유지 추가가 조용히 무시되는 역효과만 생긴다. code-auditor가 콜사이트 추적으로
  "사용자 탭 전용" 여부를 확인했다.
- **keepAlive 재검토**: `ref.keepAlive()`는 그대로 유지하기로 결론. 제거하면 S0에서 만든
  "앱 시작 시 내 위치 상시 표시" 기능이 회귀할 위험이 있다. 대신 GPS 다운시프트가 같은
  공유 스트림을 통해 홈/설정 화면에서도 배터리 절감 효과를 준다.
- **Thermal Governor**: 체크리스트에 "(선택)"로 명시된 옵션 항목이라 이번 세션에서 제외,
  백로그로 남김.

---

## 검증

- `flutter analyze`: 이슈 0
- `flutter test`: **419건 전건 통과** (기존 402 + 신규 17 — 정차 판정 경계값 단위테스트,
  reroute/POI/카메라 게이트 정적 검사, 실제 플랫폼 채널을 모킹한 스트림 재구독 통합테스트)
- code-auditor: **1차 PASS**(수정 없이) — 4가지 핵심 리스크(가스스테이션 재탐색 게이트
  제외 판단, `StateProvider` import 경로, 첫 fix 이전 미탐지 가드, 스트림 재구독 순서)를
  각각 소스·패키지·테스트로 직접 검증

---

## 참고 (결함 아님, 실기기 검증 시 알아둘 것)

- geolocator_android 문서상 `LocationAccuracy.high`와 `bestForNavigation`은 Android에서
  동일한 `PRIORITY_HIGH_ACCURACY`로 매핑된다. 즉 이번 다운시프트의 실측 배터리 절감은
  주로 `distanceFilter`(0→15) 쪽에서 나올 가능성이 크고, `accuracy` 변경 단독으로는
  체감 차이가 작을 수 있다.

---

## 잔여 / 다음 세션 큐

- **S9** — Valhalla 포크 작업 별도 승인 필요(이번 스코프 제외 확정)
- **S12** — 마스터 도로 색상 참고 스크린샷 대기
- **S6·S7·S8·S10·S11·S13** — 아직 착수 전, 다음 세션에 마스터가 순서 지정
- **다른 세션 미커밋 파일 30여 건**은 그대로 워크트리에 남아 있음(스코프 밖, 손대지 않음)

---

**목표 달성 판정:** 원래 목표: 정차 중 재탐색·POI·카메라추종 폭주와 GPS 배터리 소모를
정지시킨다(5km/h 미만 10초 지속 시 정차 모드 진입, 즉시 해제). / 달성: **코드 완료 — yes**.
`YNAV_REROUTE` 0건/배터리 소모 실측은 실기기가 필요해 **마스터 수동 검증 대기**.
