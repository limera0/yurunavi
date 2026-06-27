# RECON_layer0.md — 단일 실세계 SoT (운동학 상태 추출)

작성일: 2026-06-27
방식: 읽기 전용. main(cleanup 머지 후) grep. 레퍼런스: OsmAnd Location↔RoutingHelper 분리.
목표: 위치 파생값(속도·moving·heading)을 View에서 떼어 단일 Notifier로. Layer1(진행추적)의 토대.

---

## §A 현재 데이터 흐름 (file:line)

```
locationStreamProvider (map_providers.dart:63, raw Position, keepAlive, 1Hz, bestForNavigation)
   │  ref.listenManual (nav:232 / main_map:194)
   ▼
nav_screen._onPosition(pos) (:299)
   ├─ currentLocationProvider.set(loc)         (:301)   ← main_map도 동일 set (:198)
   ├─ _posBuffer 적재/프루닝                     (:307~308, 12초)
   ├─ _calcParkState() → _moving 히스테리시스    (:329~338, :609)
   ├─ 도플러 속도 이력 _vPrev/_vCur 등 갱신       (:341~342)
   ├─ _speedKmh = _moving ? d*3.6 : 0           (:344~347)
   └─ heading: pos.heading로 카메라 회전          (:358, 진행상태로 저장 안 함)

_speedTicker 200ms (:241) → _tickSpeed() (:247~298)
   └─ staleness8s/fast-stop1500ms/ZUPT/선형외삽/점프가드 → _speedKmh 평활
```

## §B 단일소스 현황

- **raw 위치**: 단일(`locationStreamProvider`). ✓ LOC-UNIFY 완료분.
- **`currentLocationProvider`**(map_providers): LatLng? 싱크. nav·map 둘 다 `.set()`. 속도/heading 없음.
- **속도 중복 아님**: main_map은 `_speedKmh` 미산출(LatLng만 set). 속도계는 nav 전용(:1022).
- **진짜 문제 = View 엔탱글**: 평활속도·`_moving`·`_firstFixReceived`·heading·진행이 전부 nav_screen
  위젯 state. 도착(`_checkArrival`)·카드·속도계·카메라가 **각자 `loc`를 따로 해석** → desync 토양.

## §C Layer 0으로 이동할 운동학 기계 (nav_screen → Notifier)

| 자산                                                 | line                 | 비고                |
| -------------------------------------------------- | -------------------- | ----------------- |
| `_posBuffer` (12초 링)                               | :75, 307~308         | 적재/프루닝            |
| `_moving` 히스테리시스                                   | :77, 329~338         | _calcParkState 의존 |
| `_firstFirstReceived`                              | :78, 170/213/319/348 | 콜드스타트 표시          |
| `_speedTicker` 200ms + `_tickSpeed`                | :82, 241, 247~298    | 외삽 평활             |
| `_vPrev/_vCur/_vPrevAt/_vCurAt/_vPrevPos/_vCurPos` | :83~85, 341~342      | 도플러 이력            |
| `_calcParkState()`                                 | :609~                | posBuffer 군집반경    |
| `_speedKmh`                                        | :69, 344~347         | 출력                |
| heading                                            | :358                 | 현재 카메라 직결, 미저장    |
| SPD 디버그로그                                          | :352~                | 같이 이동             |

## §D 목표 구조

### Layer 0 — `navStateProvider` (단일 운동학 SoT)

`locationStreamProvider`를 구독하는 Notifier가 §C 기계를 소유하고 다음을 emit:

```dart
class NavigationState {
  final LatLng pos;
  final double speedKmh;   // 평활/ZUPT 적용
  final bool moving;
  final double? headingDeg; // pos.heading (유효 시)
  final bool firstFix;
  final DateTime fixAt;
}
```

- 200ms 티커는 Notifier 내부 `Timer.periodic`으로 이동, 상태 emit.
- nav_screen: 속도계·카메라bearing·moving/firstFix를 `ref.watch(navStateProvider)`로 읽음.
- `currentLocationProvider`(LatLng 싱크)는 `navStateProvider.pos`로 **대체**(중복 set 제거).
  main_map도 navState.pos 구독으로 전환.

### Layer 1 — `routeProgressProvider` (별도, 진행추적)

`navStateProvider.pos` + 활성 경로를 입력으로 shape_index 단조스냅 →
`{snapIdx, progressM, distToNextTurn, stepIdx, remainingToDest, arrived}`. = SPEC_guidance_p1 로직.

## §E 경계 확정 (결정 완료)

**Layer 0 = 운동학(위치파생)만. Layer 1 = 경로진행(경로파생)을 별도 provider로.**

- 근거: OsmAnd `Location`↔`RoutingHelper`, OM `location`↔`FollowedPolyline` — 둘 다 분리.
- `NavigationState`에 진행 필드(snapIdx 등)를 **넣지 않음**. routeProgress가 navState를 구독.
- 이로써 Layer 0은 경로 지식 0, Layer 1만 경로 알면 됨 → 관심사 분리, 그릇 두 번 안 고침.

## §F 위험/구현 주의

- 티커→Notifier 전환: `setState` 제거, 상태 emit. 위젯 dispose와 무관하게 Notifier 생명주기로.
- `currentLocationProvider` 사용처 전수(map 카메라 등) 확인 후 navState.pos로 일괄 이관.
- `pos.timestamp` 불신 → 수신시각(`DateTime.now()`) 기반 유지(현 코드 동일 정책 보존).
- 평활/가드 상수(8000/1500/150/75/6500/0.05 등) Layer 0 상단 named const로 모음(매직넘버 청산).

## §H `currentLocationProvider` 이관 맵 (전수 확인 완료)

현재 `currentLocationProvider`는 **쓰기 가능한 LatLng? Notifier 싱크**(map_providers.dart:87). 화면이
push하는 구조 → navState 도입 시 **읽기전용 파생 Provider로 전환**(싱크 제거).

**쓰기(.set) — 제거 대상 (2곳)**

- nav_screen.dart:301 `currentLocationProvider.notifier.set(loc)` → 삭제 (navState가 스트림서 직접 파생)
- main_map_screen.dart:198 동일 → 삭제

**읽기 — 유지(파생값 그대로 읽음, 5곳)**

- nav_screen.dart:167 `ref.read` (initState 초기 카메라) — navState 로딩 중이면 null, 기존과 동일
- nav_screen.dart:209 `ref.read` (knownLoc 콜드스타트)
- map_providers.dart:230 / 239 / 255 — **daylight 계열 provider**(일출·일몰 위치 계산). 위치만 필요.

**전환 방식 (예외 없음, 단일소스 유지)**

```dart
// Before: NotifierProvider<_LatLngNotifier, LatLng?> (쓰기 싱크)
// After : 파생 읽기전용
final currentLocationProvider =
    Provider<LatLng?>((ref) => ref.watch(navStateProvider).valueOrNull?.pos);
```

→ 단일소스 = `navStateProvider`. 나머지는 전부 거기서 파생. daylight·initState 읽기 코드 **무변경**.
이름 유지로 churn 최소(파생 셀렉터라 "예외"가 아님 — 단일소스에서 뽑는 정식 접근자).

**콜드스타트 seeding 이동**: 현재 nav initState의 `getLastKnownPosition` 폴백(:234) + Seoul-flicker
회피 로직(:209~238)은 **navStateProvider 내부로 이동**(운동학 초기상태 seeding). 화면은 seeding 안 함.

**main_map 정리(권장)**: main_map의 raw `locationStreamProvider` 직접구독(:194)도 navState로 전환하면
SoT 순수. 단 카메라 추종이 raw를 원하면 navState.pos가 동일하므로 무손실.

## §I SPEC 전 미결 (해소 상태)

- ~~currentLocationProvider 소비처 전수~~ → §H 완료.
- Layer 0 단독 커밋으로 속도계가 기존과 동일 거동인지 **실측 회귀**(속도 폭주 전력 — 메모리).
  → Layer 0은 **T3(라이딩 회귀)**. 카드/도착 미변경이라 회귀 범위는 **속도계 한정**.
- daylight provider 3곳: 파생 셀렉터 도입 시 자동 호환(코드 무변경) — SPEC에서 회귀 확인만.
