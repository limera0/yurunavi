# RECON_perm_halt.md — 첫 실행 권한 halt (Layer 0 회귀)

작성일: 2026-06-28 (토요일 야간 세션)
방식: 읽기 전용. logcat 실측 + grep + 4지점 정독.
분류: **T3 (라이딩 불필요, 콜드스타트 first-run 검증만)** — 권한 흐름 한정 회귀.
브랜치: `feat/layer0-navstate` (Layer 0 fix, 미머지 상태에서 이어감).

---

## §A 증상 (실측 확정)

첫 설치 후 첫 실행 → 위치 권한 "허용" 직후 **halt**(완전 멈춤). 뒤로/재실행 무효.
recents로 죽이고 재실행하면 정상(알림 권한으로 진행). 2회차부터 재현 안 됨.

logcat 결정적 증거:
```
E flutter : Unhandled Exception: User denied permissions to access the device's location.
E flutter : #0  GeolocatorAndroid.getLastKnownPosition (...:91:7)
E flutter : #1  NavStateNotifier._seed (...nav_state_provider.dart:76:18)
W Activity: Can request only one set of permissions at a time
W permissions_handler: onRequestPermissionsResult is called without results.
                       This is probably caused by interfering request codes.
```
EMM/MDM 무관 확정: `dumpsys device_policy` → `Permission policy: {0=0, 150=0}`,
위치/yurunavi 대상 permissionGrant 0건. user 150(보안폴더)은 앱과 무관.

## §B 근본 원인 — 권한 요청 3중 + seed unhandled

권한 다이얼로그를 띄우는 주체가 **둘**(서로 다른 라이브러리), 거기에 seed 예외가 겹침:

```
앱 시작
 ├─ splash._runSequence() (900ms 후) → _requestPermissions()
 │    └─ Permission.location.request()           [permission_handler] ← 의도된 주체
 │         └─ granted 후 locationStreamProvider 워밍업 (splash:64)
 │              └─ map_providers:67 Geolocator.requestPermission()  [geolocator] ❌ 충돌1
 │
 └─ navStateProvider.build()  (앱 시작 즉시, splash와 병렬)
      └─ _seed() → getLastKnownPosition()  (권한 전 → throw, try/catch 없음) ❌ 충돌2
```

- **충돌1**: `permission_handler`와 `geolocator`가 같은 LOCATION 권한을 거의 동시에 요청 →
  `Can request only one set of permissions at a time` → permission_handler 콜백 유실.
- **충돌2**: `_seed`의 `getLastKnownPosition()`이 권한 전 호출돼 unhandled exception.
- 2회차 정상 이유: 권한 이미 granted → 다이얼로그 안 뜸 → 둘 다 발화 안 함.

**회귀 출처**: Layer 0 전에는 seeding이 화면 mount 후(권한 흐름 종료 뒤) 일어났음.
`navStateProvider.build()`로 당기면서 seed 시점이 **권한 흐름 전**으로 앞당겨진 것이 회귀.

## §C 권한 요청 주체 전수 (grep + 정독)

| # | 파일:line | 호출 | 역할 | 판정 |
|---|---|---|---|---|
| 1 | splash:60,63,69,71 | `Permission.{location,notification}.request()` | OS 표준 1회 요청 + granted 시 stream 워밍업 | **유지 (단일 주체)** |
| 2 | map_providers:65 | `Geolocator.checkPermission()` | stream 전제조건 확인 | **유지** |
| 3 | map_providers:67 | `Geolocator.requestPermission()` | stream 자가 요청 | **제거** (splash가 보장) |
| 4 | nav_screen:180 | `Geolocator.checkPermission()` | nav 진입 확인 | **유지** |
| 5 | nav_screen:181 | `Geolocator.requestPermission()` | nav 자가 요청 | **제거** (splash 뒤라 granted) |
| 6 | nav_state_provider:73 | `getLastKnownPosition()` | seed, 권한 게이팅 없음 | **게이팅+try/catch** |

splash가 `await _requestPermissions()` 후에야 `_goToMain()` 하므로(splash:54~56),
이후 깨어나는 stream·nav는 **granted 상태를 전제**할 수 있음 → 요청은 splash만, 나머지는 확인만.

## §D 정독 소견 (각 지점 거동)

- **splash:52~70**: `_requestPermissions()`가 location request → granted면 stream 워밍업(:64)
  → notification request. **순차 await**라 그 자체는 정상. 문제는 워밍업이 여는 stream(map_providers)이
  *또* 요청하는 것. 워밍업은 유지하되 stream의 자가요청만 빼면 됨.
- **map_providers:64~84**: stream은 권한 없으면 `return`(빈 스트림)으로 이미 graceful.
  :67 request만 빼고 `checkPermission` 결과로 whileInUse/always 아니면 return하면 충분.
  (이미 :70~73에 그 가드 있음 — request 한 줄만 제거하면 로직 보존.)
- **nav_screen:179~181**: `_startLocation`이 진입마다 check+request. nav는 splash 한참 뒤
  진입(메인→경로→내비)이라 항상 granted. request 제거, check 후 denied면 return 유지.
  deep-link로 splash 우회 진입 경로 **없음**(확인: 진입은 메인 경유 단일 경로).
- **nav_state_provider:72~84 `_seed`**: try/catch 전무. getLastKnownPosition은 권한 전
  반드시 throw. seed는 Seoul-flicker 회피용 nice-to-have → 실패해도 null 유지면 무해
  (첫 fix가 곧 채움). checkPermission 게이팅 + try/catch 2겹.

## §E 수정 방향 (SPEC 예고)

**S1. map_providers.dart (단일 파일):** :67 `requestPermission()` 한 줄 제거.
```dart
final locationStreamProvider = StreamProvider<Position>((ref) async* {
  final permission = await Geolocator.checkPermission();   // request 안 함
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    return;   // splash가 권한 보장. 없으면 조용히 빈 스트림.
  }
  ref.keepAlive();
  yield* Geolocator.getPositionStream(...);  // 기존 그대로
});
```

**S2. nav_screen.dart (단일 파일):** :181 request 제거.
```dart
final perm = await Geolocator.checkPermission();
if (perm == LocationPermission.denied ||
    perm == LocationPermission.deniedForever) return;
```

**S3. nav_state_provider.dart (단일 파일):** `_seed` 2겹 방어.
```dart
Future<void> _seed() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) return;   // 권한 전엔 seed 안 함
    final last = await Geolocator.getLastKnownPosition();
    if (last == null || state != null) return;
    _pos = LatLng(last.latitude, last.longitude);
    _fixAt = DateTime.now();
    state = NavigationState(
      pos: _pos!, speedKmh: 0, moving: false,
      headingDeg: null, firstFix: false, fixAt: _fixAt!,
    );
  } catch (_) {
    return;   // seeding 실패 무해 — 첫 fix가 곧 채움
  }
}
```

근거: 권한 요청은 splash 단일화 → OS 다이얼로그 1회만. stream·nav·seed는 전부
"확인 후 진행/조용히 후퇴". 두 라이브러리 동시 요청 소멸 → 콜백 충돌 소멸.

## §F 커밋 분할 (3커밋, 각 analyze 통과)
- **C1** `fix(map): stop stream self-requesting location permission` — map_providers §S1.
- **C2** `fix(nav): nav_screen checks permission, does not request` — nav_screen §S2.
- **C3** `fix(nav): guard _seed against pre-grant location access` — nav_state_provider §S3.
  (3파일 독립 → 깔끔히 1파일=1커밋. 순서 무관하나 위 순서 권장.)

## §G 검증
### 정적
- `flutter analyze` 새 에러 0. `flutter build apk --debug` 성공.
### 콜드스타트 회귀 (T3, 라이딩 불필요 — first-run만)
1. **첫 설치 first-run**: uninstall→install→실행 → 위치 "허용" → **halt 없이** 알림 권한으로 진행
   → 지도 표시. (←핵심 재현 케이스)
2. **권한 거부 경로**: 위치 "거부" 선택 시 크래시 없이 빈 위치로 진입(추후 안내 동작).
3. **2회차**: 재실행 시 다이얼로그 없이 즉시 지도(기존 정상 거동 보존).
4. **Layer 0 무회귀**: 속도계 정차 0·저속 추종·카메라 회전 — 5/5 통과분 유지 확인.
- 라이딩 회귀 불필요(권한 흐름만 변경, 운동학 로직 무변경).

## §H 미결
- splash:64 stream 워밍업이 granted 직후 여는데, 그 시점 navState가 이미 build됐다면
  seed 게이팅(S3)이 첫 fix와 경합할 수 있음 → S3의 `state != null` 가드가 흡수(첫 fix 우선).
  추가 처리 불필요, 검증 1번에서 확인.
- 권한 "항상 허용"(background) 승격은 이번 범위 밖(현재 whileInUse로 충분, foreground service 가동중).
