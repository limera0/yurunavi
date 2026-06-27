# SPEC_layer0.md — 단일 운동학 SoT (NavigationState 추출)

작성일: 2026-06-27
근거: loop/RECON_layer0.md, loop/AUDIT_architecture.md
대상: 신설 `lib/features/navigation/providers/nav_state_provider.dart`,
      `lib/features/map/providers/map_providers.dart`,
      `lib/features/navigation/presentation/nav_screen.dart`,
      `lib/features/map/presentation/main_map_screen.dart`
분류: **T3 (라이딩 회귀 필수)** — 속도계 거동 변경. 카드/도착 미변경이라 회귀 범위는 속도계 한정.
브랜치: `feat/layer0-navstate` (main 기준, cleanup 머지 후).

---

## 0. 한 줄 목표

nav_screen 위젯에 갇힌 운동학 파생값(평활속도·moving·heading·firstFix)을 **단일 Riverpod
`navStateProvider`로 추출**. 모든 화면·로직이 거기서만 파생값을 읽게 해 desync 토양 제거.
경로 진행추적은 Layer 1(별도) — 이번 범위 **아님**.

레퍼런스: OsmAnd `OsmAndLocationProvider.setLocation → RoutingHelper`(단일 공급),
Organic Maps `location ↔ FollowedPolyline`(운동학/경로 분리). Layer 0 = 운동학만.

---

## 1. 신설 — NavigationState 모델 + Provider

`lib/features/navigation/providers/nav_state_provider.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import '../../map/providers/map_providers.dart' show locationStreamProvider;

@immutable
class NavigationState {
  final LatLng pos;
  final double speedKmh;    // 평활/ZUPT 적용 결과
  final bool moving;
  final double? headingDeg; // pos.heading >= 0 일 때만, 아니면 null
  final bool firstFix;      // 첫 GPS fix 수신 여부(콜드스타트 표시용)
  final DateTime fixAt;     // 수신시각(pos.timestamp 불신 → DateTime.now())
  const NavigationState({
    required this.pos, required this.speedKmh, required this.moving,
    required this.headingDeg, required this.firstFix, required this.fixAt,
  });
  NavigationState copyWith({...}) => ...;
}

final navStateProvider =
    NotifierProvider<NavStateNotifier, NavigationState?>(NavStateNotifier.new);
```

- 초기 build()에서 `Geolocator.getLastKnownPosition()`로 seeding(Seoul-flicker 회피, 기존
  nav:209~238 로직 이동). 없으면 null 유지(firstFix=false).
- `locationStreamProvider` 구독 → fix마다 `_onFix(Position)`로 상태 갱신.
- 내부 200ms `Timer.periodic` → `_tickSpeed()`로 외삽 평활(기존 nav:241/247~298 이동).
- Notifier 생명주기로 ticker 관리(위젯 dispose와 무관). `ref.onDispose`로 ticker/구독 정리.

## 2. 이동할 운동학 기계 (nav_screen → NavStateNotifier)

RECON §C 그대로. 기존 로직 **동작 보존**(상수·임계 동일), 위치만 이동:
- `_posBuffer`(12초 링) + 적재/프루닝 (nav:75,307~308)
- `_moving` 히스테리시스 + `_calcParkState()` (nav:77,329~338,609~)
- `_firstFixReceived` (nav:78)
- `_speedTicker`/`_tickSpeed` 200ms 외삽 (nav:82,241,247~298)
- 도플러 이력 `_vPrev/_vCur/_vPrevAt/_vCurAt/_vPrevPos/_vCurPos` (nav:83~85,341~342)
- `_speedKmh` 산출 (nav:344~347)
- heading 판정(`pos.heading >= 0`) — 저장만(카메라 회전은 화면이 navState.headingDeg로 수행)
- SPD 디버그로그 (nav:352~)

## 3. 평활 상수 named const (매직넘버 청산)

NavStateNotifier 상단에 모음(기존 산재값 그대로):
```dart
static const _kStaleMs = 8000;       // 이후 정차 간주
static const _kFastStopMs = 1500;    // posBuffer 정지 시 표시 0
static const _kJumpGuardM = 150.0;   // GPS 점프 보간 OFF
static const _kAvgSpeedGuardMs = 75.0; // 비현실 평균속도(m/s) 보간 OFF
static const _kDtGuardMs = 6500;     // fix 간격 과대 보간 OFF
static const _kSpeedEpsKmh = 0.05;   // setState 트리거 최소차
static const _kBufferTtlSec = 12;    // posBuffer 보존
```

## 4. `currentLocationProvider` 전환 (map_providers.dart)

- 기존 `NotifierProvider<_LatLngNotifier, LatLng?>`(:87) + `_LatLngNotifier` 클래스 **제거**.
- 파생 읽기전용으로 교체:
```dart
final currentLocationProvider =
    Provider<LatLng?>((ref) => ref.watch(navStateProvider)?.pos);
```
- 읽기 5곳(nav:167,209 / map_providers daylight:230,239,255) **무변경**(파생값 그대로 읽음).
- 쓰기 2곳 제거: nav:301, main_map:198의 `.notifier.set(loc)` 삭제.

## 5. nav_screen 리팩터 (소비 측)

- 운동학 필드/메서드(§2) 전부 제거.
- 속도계(:1022): `final s = ref.watch(navStateProvider); _Speedometer(speedKmh: s?.speedKmh ?? 0, firstFixReceived: s?.firstFix ?? false)`.
- 카메라 bearing(:358): navState.headingDeg + speedKmh로 회전(기존 조건 `heading>=0 && speed>2` 보존).
- `_onPosition`은 **경로/도착 관심사만 남김**(Layer 1 흡수 전까지 기존 `_checkArrival`/`_checkArrivedGeofence`
  호출 유지 — 단 loc는 navState.pos에서 취득). 운동학 계산은 navState로 위임.
- initState 콜드스타트 seeding 로직(:209~238)은 §1로 이동했으므로 화면에선 제거, navState 구독만.

## 6. main_map_screen 정리

- `.set(loc)` 제거(:198). 위치 필요 시 `ref.watch(navStateProvider)?.pos` 또는 파생
  `currentLocationProvider`. 카메라 추종이 raw 원하면 navState.pos 동일(무손실).

## 7. 커밋 분할 (3커밋, 각 analyze 통과)

- **C1** `feat(nav): add NavigationState kinematic provider`
  — nav_state_provider.dart 신설(§1~3). 아직 미사용이라 단독 컴파일 OK.
- **C2** `refactor(nav): consume navState, drop in-widget kinematics`
  — nav_screen §2 제거 + §5 소비 전환. main_map §6.
- **C3** `refactor(map): currentLocationProvider as derived selector`
  — map_providers §4 전환, 쓰기 2곳 제거.
  (순서 주의: C3가 쓰기 제거 → C2에서 화면이 더 이상 set 안 하도록 먼저 정리. C2↔C3 의존
   있으면 한 커밋으로 합쳐도 무방. 구현자가 컴파일 단위로 판단, 단 각 커밋 analyze 통과 필수.)

각 커밋 `flutter analyze` 새 에러 0(settings 경고 2개 잔존 허용) + code-auditor 7/7.

## 8. 검증

### 빌드/정적
- `flutter analyze` 새 에러 0. `flutter build apk --debug` 성공.

### 라이딩 회귀 (T3 — 속도계 한정, main 머지 전 필수)
1. **정차 0**: 신호대기·정지 시 속도계 즉시 0(고착·잔값 없음).
2. **저속 추종**: 골목 서행 시 실제 속도와 일치(외삽 평활 정상).
3. **고속**: 폭주(200+km/h) 재현 없음(가드 정상). ※ 과거 칼만 도입 시 폭주 전력.
4. **콜드스타트**: 출발 직후 "GPS 검색 중"→첫 fix 후 정상, Seoul-flicker 없음.
5. **카메라**: 진행방향 회전이 기존과 동일(navState.headingDeg 경유).
- 카드/도착은 이번에 미변경 — 거동 동일해야(회귀 아닌 무변경 확인).

## 9. Layer 1 연결 지점 (다음, 범위 밖)
- `routeProgressProvider`가 `navStateProvider.pos`를 구독해 shape_index 단조스냅(SPEC_guidance_p1).
- 그때 nav `_onPosition`의 `_checkArrival`/카드 거리/`_checkArrivedGeofence`가 routeProgress로 이관됨.

## 10. 미결
- C2/C3 커밋 경계: 컴파일 의존상 합쳐야 하면 합치되 메시지에 두 변경 명시. analyze 통과가 기준.
- `NavigationState?` nullable 유지(콜드스타트 null) — 소비처 `?.`/기본값 처리 일관 적용.
