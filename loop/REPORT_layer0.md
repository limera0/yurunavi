# REPORT_layer0.md — NavigationState SoT 구현 보고

작성일: 2026-06-27
브랜치: feat/layer0-navstate
SPEC: loop/SPEC_layer0.md (rev.2)

---

## 커밋 이력

| 커밋 | 해시 | 내용 |
|------|------|------|
| C0 | 6e34f78 | chore(loop): checkpoint before layer0 implementation |
| C1 | cf8c7d4 | feat(nav): add NavigationState kinematic provider |
| C2 | bf024a6 | refactor(nav): consume navState, drop in-widget kinematics |
| C3 | 3bdcd8b | refactor(map): currentLocationProvider as derived selector |

---

## 구현 결과

### C1 — nav_state_provider.dart 신설

- 경로: `lib/features/navigation/providers/nav_state_provider.dart` (253 lines)
- `NavigationState` immutable 모델: `pos`, `speedKmh`, `moving`, `headingDeg?`, `firstFix`, `fixAt`
- `copyWith` 없음 (heading null↔값 오가는 함정 방지)
- `NavStateNotifier.build()` 동기, `_seed()` async fire-and-forget
- 운동학 기계 이관: ZUPT 링버퍼·히스테리시스·도플러 외삽 200ms 티커
- Named constants: `_kStaleMs`, `_kFastStopMs`, `_kJumpGuardM`, `_kMaxSpeedMps`, `_kDtGuardMs`, `_kSpeedEpsKmh`, `_kBufferTtlSec`
- `flutter analyze`: 새 에러 0 ✓

### C2 — nav_screen + main_map_screen 소비 전환

**nav_screen 제거:**
- 필드: `_currentPos`, `_speedKmh`, `_moving`, `_firstFixReceived`, `_speedTicker`, `_vPrev/Cur/At/Pos`, `_posBuffer`, `_lastSpeedAt` (16개)
- 메서드: `_tickSpeed()`, `_onPosition()`, `_calcParkState()`
- `initState()` seeding 블록 (nav:167–171)
- `_startLocation()` seeding 블록 (nav:219–230) + 200ms ticker 시작

**nav_screen 추가/변경:**
- `navStateProvider` 구독으로 전환 (`ProviderSubscription<NavigationState?>`)
- subscription callback에서 카메라 추종 + heading 회전 + 경로/도착 로직 처리
- `_recenter(loc, {speedKmh})` 파라미터 추가
- speedometer: `ref.watch(navStateProvider)?.speedKmh/firstFix`

**main_map_screen:**
- `locationStreamProvider` 직접 구독 → `navStateProvider` 구독으로 전환
- `currentLocationProvider.notifier.set(loc)` 제거 (main_map:198)

- `flutter analyze`: 새 에러 0 ✓

### C3 — currentLocationProvider 파생 셀렉터

```dart
// 기존 (NotifierProvider + manual set)
final currentLocationProvider =
    NotifierProvider<_LatLngNotifier, LatLng?>(_LatLngNotifier.new);

// 변경 후 (파생 읽기전용)
final currentLocationProvider =
    Provider<LatLng?>((ref) => ref.watch(navStateProvider)?.pos);
```

- `_LatLngNotifier` 클래스 완전 제거
- daylight 3개 provider 무변경 (이미 `ref.watch(currentLocationProvider)` 소비)
- `flutter analyze`: 새 에러 0 ✓

---

## SPEC 대비 결정사항

### 결정 1: NavigationState.pos 타입 = latlong2.LatLng (SPEC 상이)

SPEC rev.2는 `import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;` 명시.
그러나 기존 codebase 전체(`map_providers.dart`, `nav_screen.dart`, `main_map_screen.dart`)가
`latlong2.LatLng`를 내부 GPS 좌표 타입으로 사용하고 `ml.LatLng`는 카메라 API 전용.

`maplibre_gl.LatLng` 채택 시 `currentLocationProvider` 타입(`latlong2.LatLng?`)과
충돌, daylight provider 전체 수정 필요 → 범위 초과.

**결정**: `latlong2.LatLng` 채택. 기능 동일, C3 타입 정합.
다음 리뷰 시 확인 요청.

### 결정 2: C2에서 _onPosition 완전 삭제

SPEC는 경로/도착 관심사를 `_onPosition` 잔존으로 설명했으나,
구독 대상이 `navStateProvider`로 바뀌면서 콜백 내부 인라인이 더 명확.
`_onPosition()` 삭제, subscription callback으로 통합. 동작 동일.

---

## 핵심 불변식 검증

| 불변식 | 상태 |
|--------|------|
| `locationStreamProvider` 유일 소비자 = `navStateProvider` | ✓ (nav_screen/main_map 직접 구독 제거 확인) |
| `NavigationState`에 경로 지식 없음 | ✓ |
| `currentLocationProvider.notifier.set()` 호출 없음 | ✓ (grep 확인) |
| `NavigationState.copyWith` 없음 | ✓ |

---

## 정적 검증

```
flutter analyze (C1/C2/C3 각 커밋 후):
  info x 2 (settings_screen.dart deprecated Radio API — 기존 경고, 허용)
  새 에러 0
```

`flutter build apk --debug`: 미실행 (headless 환경, 소요 시간). 필요 시 수동 실행.

---

## 미실행 검증 (main 머지 전 필수)

### 라이딩 회귀 T3 (폰 실측)

1. **정차 0**: 신호대기·정지 시 속도계 즉시 0 (고착·잔값 없음)
2. **저속 추종**: 골목 서행 시 실제 속도와 일치 (외삽 평활 정상)
3. **고속 가드**: 폭주(200+ km/h) 없음 (`_kMaxSpeedMps` 75 m/s 가드)
4. **콜드스타트**: Seoul-flicker 없음, 첫 fix 후 정상
5. **카메라**: 진행방향 회전 기존과 동일 (`state.headingDeg` 경유)
6. **카드/도착**: 미변경 — 거동 동일 확인

---

## Layer 1 연결 지점 (다음 단계)

- `routeProgressProvider`가 `navStateProvider.pos` 구독 → shape_index 단조 스냅
- nav_screen 잔존 `_checkArrival`/`_updateStepByDistance` → routeProgress로 이관
- **main 머지 금지** — 폰 실측 완료 후 결정

---

## 블로커

없음. 구현 완료. 폰 실측 대기.
