# SPEC_layer0.md — 단일 운동학 SoT (NavigationState 추출)

작성일: 2026-06-27 (rev.2 — 발사 전 검토 반영)
근거: loop/RECON_layer0.md, loop/AUDIT_architecture.md
대상: 신설 `lib/features/navigation/providers/nav_state_provider.dart`,
      `lib/features/map/providers/map_providers.dart`,
      `lib/features/navigation/presentation/nav_screen.dart`,
      `lib/features/map/presentation/main_map_screen.dart`
분류: **T3 (라이딩 회귀 필수)** — 속도계 거동 변경. 카드/도착 미변경이라 회귀 범위는 속도계 한정.
브랜치: `feat/layer0-navstate` (main 기준, cleanup 머지 후).

> rev.2 변경점 요약 (구현자 주의):
> - §1 seeding은 **async fire-and-forget**(`build()`는 동기, await 금지).
> - §1 `copyWith` **사용 금지** — heading null화 함정. 매 fix/tick마다 `NavigationState(...)` 전체 생성.
> - §4 쓰기 제거(nav:301, main_map:198)는 **C2로 재배치**. C3는 map_providers.dart **단일 파일**.
> - §5 화면은 `navStateProvider`만 구독. `locationStreamProvider` **직접 재구독 금지**(단일소스 순도).
> - §3 `_kAvgSpeedGuardMs` → `_kMaxSpeedMps` rename(값은 m/s).
> - nav:209 경계: seeding 블록만 이동, 단순 읽기 줄은 잔존(§4/§5 줄단위 명시).

---

## 0. 한 줄 목표

nav_screen 위젯에 갇힌 운동학 파생값(평활속도·moving·heading·firstFix)을 **단일 Riverpod
`navStateProvider`로 추출**. 모든 화면·로직이 거기서만 파생값을 읽게 해 desync 토양 제거.
경로 진행추적은 Layer 1(별도) — 이번 범위 **아님**.

레퍼런스: OsmAnd `OsmAndLocationProvider.setLocation → RoutingHelper`(단일 공급),
Organic Maps `location ↔ FollowedPolyline`(운동학/경로 분리). Layer 0 = 운동학만.

핵심 불변식 (구현 중 지킬 것):
- **raw GPS(`locationStreamProvider`)의 유일한 소비자는 `navStateProvider`다.** 화면·다른 provider는
  raw를 직접 듣지 않고 navState에서 파생값을 읽는다.
- `NavigationState`에 **경로 지식(snapIdx·도착·카드거리)은 넣지 않는다**(Layer 1 소유).

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
  // ⚠️ copyWith 두지 않는다. heading은 null↔값을 오가므로 copyWith(`?? this`)로는
  //    null 복귀가 안 돼 정지 후 옛 heading이 박힌다(카메라 오작동).
  //    _onFix/_tickSpeed에서 매번 NavigationState(...) 전체 생성으로 명시 지정.
}

final navStateProvider =
    NotifierProvider<NavStateNotifier, NavigationState?>(NavStateNotifier.new);
```

### NavStateNotifier 생명주기

```dart
class NavStateNotifier extends Notifier<NavigationState?> {
  Timer? _ticker;

  @override
  NavigationState? build() {
    // build()는 동기. await 금지. seeding은 fire-and-forget.
    final sub = ref.listen(locationStreamProvider, (_, next) {
      next.whenData(_onFix);
    });
    _ticker = Timer.periodic(
      const Duration(milliseconds: 200), (_) => _tickSpeed());
    ref.onDispose(() {
      _ticker?.cancel();
      sub.close();
    });
    _seed();            // async, 첫 fix 전에만 채움
    return null;        // 콜드스타트 null
  }

  Future<void> _seed() async {
    final last = await Geolocator.getLastKnownPosition();
    if (last == null || state != null) return;  // 첫 fix가 이미 왔으면 덮지 않음
    state = NavigationState(
      pos: LatLng(last.latitude, last.longitude),
      speedKmh: 0, moving: false, headingDeg: null,
      firstFix: false, fixAt: DateTime.now(),
    );
  }

  void _onFix(Position pos) { /* §2 운동학 기계 */ }
  void _tickSpeed()        { /* §2 외삽 평활 */ }
}
```

- seeding은 Seoul-flicker 회피용(기존 nav 콜드스타트 seed 로직 이동). **첫 fix 도착 후엔 덮지 않음**.
- 200ms 티커·구독은 **Notifier 생명주기**로 관리(위젯 dispose와 무관). `ref.onDispose`에서 정리.

## 2. 이동할 운동학 기계 (nav_screen → NavStateNotifier)

RECON §C 그대로. 기존 로직 **동작 보존**(상수·임계·계산 동일), 위치만 이동:
- `_posBuffer`(12초 링) + 적재/프루닝 (nav:75,307~308)
- `_moving` 히스테리시스 + `_calcParkState()` (nav:77,329~338,609~)
- `_firstFixReceived` → state.firstFix로 표면화 (nav:78)
- `_speedTicker`/`_tickSpeed` 200ms 외삽 (nav:82,241,247~298)
- 도플러 이력 `_vPrev/_vCur/_vPrevAt/_vCurAt/_vPrevPos/_vCurPos` (nav:83~85,341~342)
- `_speedKmh` 산출 (nav:344~347)
- heading 판정: `pos.heading >= 0 ? pos.heading : null` — **저장만**(카메라 회전은 §5에서 화면이
  state.headingDeg로 수행). nav_screen의 직접 카메라회전 결선은 §5에서 교체.
- SPD 디버그로그 (nav:352~)

각 fix/tick 종료 시 `state = NavigationState(...)`로 **전체 필드 명시 생성**(copyWith 금지, §1).
`_kSpeedEpsKmh` 미만 변화면 state 재설정 생략 가능(불필요 rebuild 억제) — 단 pos는 항상 갱신.

## 3. 평활 상수 named const (매직넘버 청산)

NavStateNotifier 상단에 모음(기존 산재값 그대로, **이름만 정정**):
```dart
static const _kStaleMs       = 8000;    // 이후 정차 간주
static const _kFastStopMs    = 1500;    // posBuffer 정지 시 표시 0
static const _kJumpGuardM    = 150.0;   // GPS 점프 보간 OFF
static const _kMaxSpeedMps   = 75.0;    // (구 _kAvgSpeedGuardMs) 비현실 평균속도 m/s 가드
static const _kDtGuardMs     = 6500;    // fix 간격 과대 보간 OFF
static const _kSpeedEpsKmh   = 0.05;    // state 재설정 트리거 최소차
static const _kBufferTtlSec  = 12;      // posBuffer 보존
```
> `_kMaxSpeedMps`는 m/s 단위(75m/s ≈ 270km/h). 기존 `Ms` 접미사는 밀리초 오해 소지라 rename.

## 4. `currentLocationProvider` 전환 (map_providers.dart) — **C3, 단일 파일**

map_providers.dart **한 파일만** 수정:
- 기존 `NotifierProvider<_LatLngNotifier, LatLng?>`(:87) + `_LatLngNotifier` 클래스 **제거**.
- 파생 읽기전용으로 교체:
```dart
final currentLocationProvider =
    Provider<LatLng?>((ref) => ref.watch(navStateProvider)?.pos);
```
- daylight 읽기 3곳(map_providers:230,239,255) **무변경**(파생값 그대로 읽음 — 회귀 확인만).
- ⚠️ **쓰기 제거(nav:301, main_map:198)는 이 커밋이 아니다.** 그 두 줄은 nav_screen.dart /
  main_map_screen.dart에 물리적으로 존재하므로 **C2에서 처리**(파일 1개=커밋 1개 유지).

> 선택(순환 import 거슬리면): 파생 `currentLocationProvider` 정의를 nav_state_provider.dart로
> 옮기면 map_providers→navState 단방향이 된다. 동작엔 무관(Riverpod lazy). 기본은 위 배치 유지.

## 5. nav_screen 리팩터 (소비 측) — **C2**

- 운동학 필드/메서드(§2) 전부 제거.
- **구독 전환**: 화면은 이제 `locationStreamProvider`를 **직접 듣지 않는다**. `navStateProvider`만
  구독. (raw GPS 유일 소비자 = navState. 이게 단일소스 순도의 핵심.)
- 속도계(:1022):
  ```dart
  final s = ref.watch(navStateProvider);
  _Speedometer(speedKmh: s?.speedKmh ?? 0, firstFixReceived: s?.firstFix ?? false)
  ```
- 카메라 bearing(기존 :358 결선 교체): `s.headingDeg != null && s.speedKmh > 2`일 때
  `s.headingDeg!`로 회전(기존 임계 보존, heading 소스만 state로).
- `_onPosition`(:299) 처리: 운동학 계산은 navState로 위임돼 사라짐. **경로/도착 관심사만 잔존** —
  `_checkArrival`/`_checkArrivedGeofence` 호출 유지하되 loc는 `ref.read(navStateProvider)?.pos`
  (또는 파생 `currentLocationProvider`)에서 취득. (Layer 1에서 이 잔존부도 routeProgress로 이관.)
- **nav:209~238 경계**(중요): 이 블록 중 **콜드스타트 seeding 로직만 §1로 이동**(화면에서 제거).
  단순 위치 읽기·UI 초기화 줄은 **잔존**. seeding 줄과 잔존 줄을 분리해 처리(이중처리/누락 금지).
  쓰기 `nav:301` `.notifier.set(loc)` **삭제**(이 커밋에서).

## 6. main_map_screen 정리 — **C2 동반**

- `.set(loc)` 제거(main_map:198). 위치 필요 시 `ref.watch(navStateProvider)?.pos` 또는 파생
  `currentLocationProvider`. 카메라 추종이 raw 원하면 navState.pos 동일(무손실).
- main_map도 `locationStreamProvider` 직접 구독이 위치 표시 목적이면 navState로 전환(raw 재소비 금지).
  단 main_map이 listen하는 이유가 위치표시뿐인지 grep 확인 후 전환.

## 7. 커밋 분할 (3커밋, 각 analyze 통과 / 파일1개=커밋1개)

- **C1** `feat(nav): add NavigationState kinematic provider`
  — `nav_state_provider.dart` 신설(§1~3). 아직 미사용 → 단독 컴파일 OK.
- **C2** `refactor(nav): consume navState, drop in-widget kinematics`
  — nav_screen §2 제거 + §5 소비/구독 전환 + **nav:301 쓰기 제거**,
    main_map §6 + **main_map:198 쓰기 제거**.
  (nav_screen.dart, main_map_screen.dart 두 파일 — 동일 논리변경 '운동학 소비전환'이라 1커밋 유지.)
- **C3** `refactor(map): currentLocationProvider as derived selector`
  — map_providers.dart **단일 파일** §4(쓰기 제거 없음, 셀렉터 교체만).

순서: C1(신설) → C2(화면이 set 중단·navState 소비) → C3(셀렉터 교체). C2 착지 시 더 이상 아무도
`_LatLngNotifier.set`을 호출 안 하므로 C3에서 안전 제거. **각 커밋 `flutter analyze` 새 에러 0 필수.**

## 8. 검증

### 빌드/정적
- 각 커밋 `flutter analyze` 새 에러 0(settings 경고 2개 잔존 허용) + code-auditor 7/7.
- `flutter build apk --debug` 성공.

### 스모크 (라이딩 불필요)
- 앱 실행 → 지도 표시 → 정지 상태 속도계 **0 고정** → 짧게 이동 시 속도 표시 → 설정/프로필 진입 →
  경로 1개 탐색 시작 → 크래시 없음.

### 라이딩 회귀 (T3 — 속도계 한정, main 머지 전 필수)
1. **정차 0**: 신호대기·정지 시 속도계 즉시 0(고착·잔값 없음).
2. **저속 추종**: 골목 서행 시 실제 속도와 일치(외삽 평활 정상).
3. **고속**: 폭주(200+km/h) 재현 없음(가드 정상). ※ 과거 칼만 도입 시 폭주 전력.
4. **콜드스타트**: 출발 직후 "GPS 검색 중"→첫 fix 후 정상, Seoul-flicker 없음.
5. **카메라**: 진행방향 회전이 기존과 동일(state.headingDeg 경유, 정지 시 회전 멈춤).
- 카드/도착은 이번에 미변경 — 거동 동일해야(회귀가 아니라 **무변경 확인**).

## 9. Layer 1 연결 지점 (다음, 범위 밖)
- `routeProgressProvider`가 `navStateProvider.pos`를 구독해 shape_index 단조스냅(SPEC_guidance_p1).
- 그때 nav `_onPosition`의 `_checkArrival`/카드 거리/`_checkArrivedGeofence` 잔존부가 routeProgress로 이관.

## 10. 미결/판단 위임
- C2가 두 파일(nav_screen, main_map)을 건드림: 둘 다 '운동학 소비 전환'이라 1커밋 유지가 원칙이나,
  컴파일 단위로 분리가 더 깨끗하면 구현자 판단(단 각 커밋 analyze 통과·메시지에 변경 명시).
- `NavigationState?` nullable 유지(콜드스타트 null) — 소비처 `?.`/기본값 처리 일관 적용.
- main_map이 `locationStreamProvider`를 위치표시 외 목적으로도 듣는지 grep 후 전환 범위 확정.

---
## 실행 규약 (헤드리스 필수 준수)
- 0단계 사전검증 게이트(브랜치/대상파일 존재 확인) → 체크포인트 커밋 → 구현 → 커밋별 analyze →
  분할 커밋 → `loop/REPORT_layer0.md` 작성.
- 모호하면 **추측 말고 중단·보고**. 폰 실측 전이므로 **main 머지 금지**.
- 시그니처 불확실 시 `~/.pub-cache` 실제 파일 확인(Notifier/ref.listen/whenData 등).
