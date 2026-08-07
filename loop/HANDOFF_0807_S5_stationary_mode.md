GOAL: 정차 중 재탐색/POI/카메라추종 폭주와 GPS 배터리 소모를 정지시킨다 — 속도 5km/h 미만이 10초 지속되면 "정차 모드"에 진입, 재진입 조건은 즉시(속도 회복 시 지연 없이 해제).

- 작성 2026-08-07 · 근거: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) §S5 (336~346행)
- 마스터 확인 완료 사항 (2026-08-07 대화):
  - 이번 세션 스코프: **S5만** (CLAUDE.md "모듈당 1세션" 하드룰 — S6~S8/S10~S13은 큐에 남김, S9는 이번 스코프 전체 제외 — Valhalla 포크 별도 승인 필요, S12는 마스터 스크린샷 대기)
  - 정차 판정 임계값: **5km/h 미만 · 10초 지속**

## 배경 (RECON 근거)

`YNAV_REROUTE` 로그가 분당 최대 151건. `distanceFilter: 0`(모든 GPS 지터가 fix로 들어옴) +
정차 중 GPS 지터가 원인. S1(clamp)·S2(POI 429)와 별개 결함.

## 현재 코드 구조 (2026-08-07 확인, 최신 줄번호)

- `lib/features/navigation/providers/nav_state_provider.dart` — `NavStateNotifier`가
  `locationStreamProvider`를 구독해 `speedKmh`/`moving`/`headingDeg`를 파생.
  `NotifierProvider`(비-autoDispose)라 **앱 생명주기 동안 상시 구동** — 이미 그렇다,
  이번 작업으로 새로 생기는 문제 아님.
  - `_moving`(:132-136)은 **순간 판정**(속도 2.0/1.5km/h 히스테리시스 + 주차버퍼반경) —
    이번에 만들 "정차 모드"(10초 지속)와는 **다른 개념**이다. 기존 `_moving`을 건드리지 말 것,
    그 위에 별도의 지속시간 상태머신을 얹는다.
- `lib/features/map/providers/map_providers.dart:66-92` — `locationStreamProvider`
  (`StreamProvider<Position>`). `:72` `ref.keepAlive()`, `:75` `accuracy: bestForNavigation`,
  `:77` `distanceFilter: 0`.
- `lib/features/navigation/presentation/nav_screen.dart`:
  - `:524-553` `_startLocation()`의 `navStateProvider` 리스너 — 매 틱마다
    `_recenter(...)`(카메라 추종, `:536`) · `_maybeFetchAmbientPois()`(`:542`) 호출.
  - `:800-805` `_offRouteDebounce` 타이머가 만료되면 `_reroute(current)` 호출 (이탈 감지 후
    디바운스 재탐색 트리거).
  - `:913` `_reroute(currentPos, silent: true)` — 별도 트리거(정확한 컨텍스트는 근처 코드 확인).
  - `:835`, `:1684` — `offsetOrigin(origin.lat, origin.lng, heading, 40)` **두 곳** 모두 하드코딩
    40. (체크리스트의 "842, 1643"은 S3b 등 이후 커�밋으로 밀린 낡은 줄번호 — 위 두 곳이 현재 정답)

## 작업 항목

### 1. 정차 모드 상태머신 신설

- **순수 클래스로 분리해 테스트 가능하게** (코드베이스 관례: `safe_clamp.dart`,
  `_distToKorean()` 등 순수 로직은 항상 분리·단위테스트됨). 예: `StationaryDetector` —
  속도 스트림을 받아 "5km/h 미만이 10초 연속"이면 `true`, **속도가 5km/h 이상으로 단 한 번이라도
  회복되면 지연 없이 즉시 `false`**(진입은 신중하게, 해제는 즉시 — safety-first 원칙,
  memory `feedback_safety_priority` 참고: 안내류 기능은 넓게/보수적으로).
  실제 시각(`DateTime.now()`) 대신 **주입 가능한 clock**을 받게 해 위젯/유닛 테스트에서
  가짜 시간으로 10초 경과를 시뮬레이션할 수 있게 할 것.
- `NavStateNotifier`(또는 그 안에서 이 detector를 소유)의 속도 계산 경로(`_onFix`/`_tickSpeed`)에서
  매 틱마다 detector에 `speedKmh` 공급, 결과를 **새 provider**로 노출
  (예: `isStationaryProvider`, `nav_state_provider.dart`에 정의).

### 2. 재탐색 정지

- `:800-805`의 `_offRouteDebounce` 타이머 등록부 — `isStationary`이면 새 디바운스 타이머를
  등록하지 않고 조용히 리턴 (기존 이탈 로직 자체는 건드리지 않되, 재탐색 트리거링만 차단).
- `:913`의 `silent` 재탐색 호출부도 동일 가드. 정확한 트리거 조건은 주변 코드를 읽고 판단할 것.
- **주의**: 정차 모드에서 벗어나는 순간(속도 회복) 경로 이탈 상태가 남아 있었다면 정상적으로
  다시 재탐색이 걸려야 한다 — 가드가 "정차 동안만" 차단하고 해제 후엔 기존 로직 그대로 흐르는지
  확인.

### 3. 앰비언트 POI 페치 정지

- `:542` `unawaited(_maybeFetchAmbientPois())` 호출부 — `isStationary`면 스킵.
  (홈 화면 `main_map_screen`은 S2에서 이미 15초/200m 스로틀이 있어 이번 스코프 제외.)

### 4. 카메라 추종 정지

- `:536` `_recenter(...)` 호출부 — `isStationary`면 스킵(카메라 그대로 유지, GPS 지터로 인한
  미세 흔들림 방지). 단, `:541` `_ensureLocationMarker(...)`(파란 점 위치/방향 갱신)는 **계속
  호출** — 정차 중에도 내 위치 마커 자체는 최신 상태 유지.

### 5. GPS 정확도/거리필터 다운시프트 (가장 리스크 큰 변경)

- `map_providers.dart`에 `stationaryModeProvider`(`StateProvider<bool>`, 기본 `false`) 신설.
- `locationStreamProvider`가 `ref.watch(stationaryModeProvider)`로 값을 읽어 설정 분기:
  - 이동 중(`false`): 기존 그대로 `accuracy: bestForNavigation`, `distanceFilter: 0`
  - 정차 중(`true`): `accuracy: LocationAccuracy.high`, `distanceFilter: 15`
  - (숫자 근거: `distanceFilter 15`는 실제 이동 재개 시 몇 초 안에 감지되면서 정차 중
    GPS 지터로 인한 fix 폭주를 걸러냄. `LocationAccuracy.high`는 `bestForNavigation`보다
    한 단계 낮은 GPS 정확도로 배터리 절감, 이동 재개 시 감지 지연 허용 범위로 판단 —
    수치가 부적절하다고 판단되면 조정하되 근거를 보고서에 남길 것)
- `NavStateNotifier`가 자신의 `StationaryDetector` 결과가 바뀔 때
  `ref.read(stationaryModeProvider.notifier).state = ...`로 **명령형으로 갱신**
  (양방향 `ref.watch` 순환 아님 — `locationStreamProvider`는 `stationaryModeProvider`를
  watch하지만 `stationaryModeProvider`는 아무것도 watch하지 않는 단순 플래그이므로
  순환 없음).
- **리스크**: `stationaryModeProvider`가 바뀌면 Riverpod가 `locationStreamProvider`를
  **재생성**한다 — 기존 `Geolocator.getPositionStream` 구독이 끊기고 새로 시작된다.
  `NavStateNotifier`의 `_posBuffer`/`_vPrev`/`_vCur` 등 누적 상태가 일시적으로 끊길 수 있다.
  기존 `_kStaleMs`(8000ms) 가드가 이 gap을 흡수하는지 확인하고, 재구독 직후 몇 틱 동안
  이상 동작(속도 스파이크 등)이 없는지 반드시 테스트할 것.
- **`ref.keepAlive()`(`:72`)는 그대로 유지** — 제거하면 홈/설정 화면에서 "내 위치" 표시(S0
  완료 기능)가 끊길 위험이 있다. 대신 이 5번 항목(다운시프트)이 홈/설정 화면에서도 같은
  공유 스트림을 통해 배터리 절감 효과를 준다 — 이게 체크리스트의 "keepAlive 재검토" 항목에
  대한 이번 세션의 결론이다. **keepAlive를 실제로 제거하는 방향은 이번 스코프에서 하지 않는다.**

### 6. 재탐색 origin 오프셋 40m → 50m

- `nav_screen.dart:835`와 `:1684` **두 곳 모두** `offsetOrigin(..., 40)` → `offsetOrigin(..., 50)`.

### 7. 스코프 밖 (이번엔 하지 않음)

- **Thermal Governor** — 체크리스트에 `(선택)`로 명시된 옵션 항목. 이번 세션 제외, 백로그 유지.
- **S9, S12** — 마스터 확인으로 이번 스코프 전체 제외 (별도 세션).

## 검증 요구

- 신규 유닛 테스트: `StationaryDetector`(또는 동등 클래스) — 가짜 clock으로
  ① 5km/h 미만 10초 미만 지속 → 아직 미진입 ② 10초 도달 → 진입
  ③ 진입 후 속도 5km/h 이상 단발 → 즉시 해제 ④ 경계값(정확히 5km/h, 정확히 10.0초)
- 신규/수정 위젯 또는 provider 테스트: `isStationary=true`일 때 재탐색/POI페치/카메라추종
  호출이 스킵되는지 (기존 `nav_lifecycle_test.dart` 패턴 참고)
- `flutter analyze` 이슈 0, `flutter test` 전건 통과 (현재 402건 + 신규분)
- 회귀 확인: `locationStreamProvider` 재구독 시 `NavStateNotifier`가 예외 없이 동작
  (재구독 직후 fix 처리 경로에 널 참조·상태 불일치 없는지)

## 완료 후

- `code-auditor` PASS 후 커밋, `CHECKLIST_0805_testride0802.md` §S5 `[x]`로 갱신
  (실기기 검증 항목은 기존 패턴대로 `[ ] 마스터 실기기 수동 검증 대기`로 남김:
  정차 10분간 `YNAV_REROUTE` 0건 / 배터리 소모 체감 / 정차 후 재출발 시 안내 정상 재개)
- `loop/MORNING_REPORT_0807_S5_stationary_mode.md`에 검증(A)/판정(B) 기록
