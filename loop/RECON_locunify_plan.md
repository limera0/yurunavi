# RECON-locunify-plan — LOC-UNIFY 실행계획 정찰

작성: 2026-06-17  
근거: SPEC_location.md / RECON_1hz.md / RECON_location.md / 코드 직접 확인

---

## §A 단일 위치소스 Provider — 배치 위치

**신규 provider:** `locationStreamProvider`  
**배치 파일:** `lib/features/map/providers/map_providers.dart`  
(현재 `currentLocationProvider` — `map_providers.dart:62` — 가 같은 파일에 있음; 위치 관련 선언 응집)

```dart
// map_providers.dart — currentLocationProvider 위 삽입
final locationStreamProvider = StreamProvider<Position>((ref) {
  return Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      intervalDuration: const Duration(milliseconds: 1000),
      distanceFilter: 0,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "유루나비 주행 중",
        notificationText: "경로 안내를 위해 위치를 수신하고 있습니다",
        enableWakeLock: true,
      ),
    ),
  );
});
```

**설정값 근거:** SPEC_location.md §3 확정값 (RECON_1hz §4 보강).  
**타입 선택 이유:** `StreamProvider<Position>` — main_map_screen이 앱 생명주기 동안 살아 있으므로  
autoDispose 기본 설정으로도 스트림이 닫히지 않는다. keepAlive 불필요.

---

## §B 구독 전환 — file:line

### 1. main_map_screen.dart:193 → streamProvider 구독

현재 코드 (`main_map_screen.dart:193–210`):
```dart
_locationSub = Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  ),
).listen((pos) { ... });
```

전환 후:
```dart
_locationSub = ref.read(locationStreamProvider.stream).listen((pos) {
  // 기존 리스너 바디 그대로
});
```

변경 포인트:
- `Geolocator.getPositionStream(locationSettings: const LocationSettings(...))` → 삭제
- `.listen(...)` 의 바디 유지
- `geolocator` import 유지 (getLastKnownPosition 등 다른 곳에서 사용)

### 2. nav_screen.dart:232 → streamProvider 구독

현재 코드 (`nav_screen.dart:232–243`):
```dart
_locationSub = Geolocator.getPositionStream(
  locationSettings: AndroidSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    intervalDuration: const Duration(milliseconds: 1000),
    distanceFilter: 0,
    foregroundNotificationConfig: const ForegroundNotificationConfig(...),
  ),
).listen(_onPosition);
```

전환 후:
```dart
_locationSub = ref.read(locationStreamProvider.stream).listen(_onPosition);
```

- `AndroidSettings` import 삭제 가능 여부: `geolocator/geolocator.dart` 가 이미 import됨 — 삭제 필요.
- `_onPosition` 로직(ZUPT, throttle, 속도 계산 등)은 **변경 없음**. 소스만 교체.

### 3. driving_screen.dart:97

SPEC §3 및 RECON_manifest §D: Dead Code (앱 내 참조 0건). **LOC-UNIFY 에서 변경 불필요.**  
별도 정리 티켓으로 분리.

---

## §C 앱 시작 워밍업 삽입 지점

**자연 워밍업:** 커밋2 완료 후 main_map_screen의 `_startLocationTracking()`이  
`locationStreamProvider.stream`을 구독하는 순간 스트림이 시작된다.  
앱 플로우: `main.dart` → `SplashScreen` (~1.5초: 애니+권한) → `MainMapScreen.initState()` →  
`_startLocationTracking()` (main_map_screen.dart:145 → :169) → **locationStreamProvider 활성화**

이것이 SPEC §1 "앱 시작 시점부터 워밍업" 충족 경로.  
**별도 워밍업 커밋 불필요.**

SplashScreen 시점 워밍업(권한 승인 즉시 GPS 기동)은 SplashScreen을 ConsumerStatefulWidget으로  
변환해야 하므로 스코프 초과 → 별도 티켓 후보, 현 LOC-UNIFY 범위 외.

---

## §D 커밋 분할안

| # | 파일 | 변경 내용 | 검증 방법 |
|---|------|-----------|----------|
| 커밋1 | `map_providers.dart` | `locationStreamProvider` StreamProvider 추가 (신규 선언만) | `flutter analyze` |
| 커밋2 | `main_map_screen.dart` | `_startLocationTracking()` 내 getPositionStream → streamProvider 구독 전환 | `flutter analyze` |
| 커밋3 | `nav_screen.dart` | `_startLocation()` 내 getPositionStream → streamProvider 구독 전환 | `flutter analyze` + `grep -r "getPositionStream" lib/` → locationStreamProvider 1곳만 |

각 커밋: 단일 파일 변경 / 논리 변경 1개.

---

## §E 단계별 검증 분류

| 커밋 | analyze 객관검증 | 라이딩 필수 |
|------|-----------------|------------|
| 커밋1 | ✅ (기존 코드 영향 없음) | ✗ |
| 커밋2 | ✅ | ✗ |
| 커밋3 | ✅ (`getPositionStream` 호출처 1곳 grep 확인) | ✗ |
| **전체 LOC-UNIFY 완료** | ✅ getPositionStream 1곳 | **✅ 라이딩 필수** (콜드 0km/h 소멸 / 마커 추종) |

**LOC-UNIFY 작업 전체 유형: T3** — analyze PASS 후 브랜치 push, main 머지는 라이딩 후.

---

## §F 주의사항 & 위험

1. **`ref.read` vs `ref.watch`:** nav_screen/main_map_screen 모두 `ref.read(locationStreamProvider.stream).listen(...)` 사용.  
   `ref.watch`는 rebuild 시마다 재실행되어 스트림 중복 구독 위험.

2. **geolocator import 정리:** 커밋3 후 nav_screen.dart에서 `AndroidSettings` 직접 참조가 사라지므로  
   `geolocator` 패키지 import는 `Geolocator.getLastKnownPosition()`, `LocationPermission` 등으로  
   여전히 필요 — 삭제 금지.

3. **foregroundNotificationConfig:** 현재 nav_screen.dart:237–241 에만 있음.  
   커밋1에서 locationStreamProvider 내 설정값에 포함시키므로 커밋3에서 nav 코드 삭제 후에도 유지됨.

4. **currentLocationProvider.notifier.set() 호출처:**  
   - `main_map_screen.dart:200` — 기존 리스너 바디 내 (전환 후에도 유지)  
   - `nav_screen.dart:307` — `_onPosition` 내 (변경 없음)  
   두 곳 모두 streamProvider 스트림 이벤트 수신 시 동일하게 동작 → 변경 불필요.

5. **StreamProvider 구독자 없을 때:** autoDispose 기본이므로 두 화면이 모두 없으면 스트림 닫힘.  
   앱 정상 플로우상 main_map_screen은 항상 스택에 존재하므로 실질적으로 앱 종료까지 열림.

---

## §G 미확정 없음

SPEC §3 전 항목 확정 (2026-06-17).  
- 설정값: 확정 ✅
- provider 배치 파일: 확정 ✅
- 커밋 분할: 확정 ✅
- 라이딩 대기 유형(T3): 확정 ✅
