# RECON: 전체 코드베이스 현황 棚卸
작성일: 2026-06-14 | 기준 브랜치: main (082d6e5)

---

## A. 화면 인벤토리

### A-1. 화면 목록

| 파일 | 클래스 | 줄수 | 기반 |
|---|---|---|---|
| `lib/screens/main_map_screen.dart` | (shim) | 3 | re-export only |
| `lib/features/auth/presentation/splash_screen.dart` | `SplashScreen` | ~81 | StatefulWidget |
| `lib/screens/intro_screen.dart` | `IntroScreen` | 192 | StatefulWidget |
| `lib/features/map/presentation/main_map_screen.dart` | `MainMapScreen` | ~1,100+ | ConsumerStatefulWidget |
| `lib/features/navigation/presentation/nav_screen.dart` | `NavScreen` | ~1,100+ | ConsumerStatefulWidget |
| `lib/screens/settings_screen.dart` | `SettingsScreen` | 104 | ConsumerWidget |
| `lib/screens/profile_screen.dart` | `ProfileScreen` | 456 | ConsumerStatefulWidget |
| `lib/screens/route_options_screen.dart` | `RouteOptionsScreen` | 375 | ConsumerStatefulWidget |
| `lib/screens/driving_screen.dart` | `DrivingScreen` | 615 | ConsumerStatefulWidget |

`lib/screens/main_map_screen.dart:1-3` — 3줄짜리 shim: `export '../features/map/presentation/main_map_screen.dart';`

### A-2. 진입 경로

| 화면 | 진입처 | file:line | 상태 |
|---|---|---|---|
| `SplashScreen` | 앱 진입점(main.dart 추정) | 미확인 | 연결됨 |
| `IntroScreen` | 미확인 (splash 이후 또는 직접?) | — | 연결됨(추정) |
| `MainMapScreen` | splash_screen.dart:68-71 `pushReplacement` | ✅ | 연결됨 |
| `MainMapScreen` | intro_screen.dart:72-75 `pushReplacement` | ✅ | 연결됨 |
| `NavScreen` | main_map_screen.dart:667-669 `Navigator.push` | ✅ | 연결됨 |
| `SettingsScreen` | main_map_screen.dart:898-899 `Navigator.push` | ✅ | 연결됨 |
| `ProfileScreen` | settings_screen.dart:26-27 `Navigator.push` | ✅ | 연결됨 |
| `RouteOptionsScreen` | **어디서도 import/push 없음** | ❌ | **미아(dead code)** |
| `DrivingScreen` | **어디서도 import/push 없음** | ❌ | **미아(dead code)** |

`DrivingScreen`은 `flutter_map` 기반 구 내비 화면. `NavScreen`(MapLibre 기반)으로 완전 대체됨.
`_TurnStep`을 하드코딩 더미로 보유 (`driving_screen.dart:46-50`).

---

## B. 미완성 신호 수집

### B-1. TODO / FIXME / 미구현

| file:line | 내용 |
|---|---|
| `nav_screen.dart:35` | `TODO: 실효속도 보정 적용` — ETA가 Valhalla 낙관 추정치(57-88 km/h 기준), 실측 속도 보정 없음 |
| `settings_screen.dart:38` | `TODO Phase 2: 도로 선호도` — UI 미구현 |
| `settings_screen.dart:39` | `TODO Phase 2: 내비뷰 설정` |
| `settings_screen.dart:40` | `TODO Phase 2: 안내 음성 / 안내 언어` |
| `settings_screen.dart:43` | `TODO Phase 2: 다크모드` |
| `settings_screen.dart:44` | `TODO Phase 2: 지도 다운로드` |
| `settings_screen.dart:47` | `TODO Phase 2: 약관 / 오픈소스 라이선스` |

### B-2. 빈 핸들러

| file:line | 내용 |
|---|---|
| `driving_screen.dart:400` | `onTap: () {}` — DrivingScreen 내 버튼(미아 화면이므로 영향 없음) |

---

## C. 내비게이션 기능 상태

### C-1. 재탐색(_reroute) 위치·동작

- **이탈 감지**: `nav_screen.dart:429-438` — 3초 디바운스 후 `_reroute(current)` 호출
- **_reroute 구현**: `nav_screen.dart:457-484`

현재(main) `_reroute` 실제 동작:
```dart
// nav_screen.dart:463-476
final routes = await RoutingService.fetchRoutes(
  origin: origin,
  destination: dest,
  waypoints: widget.waypoints,
  // ← heading 없음
);
// routes[selIdx].points → _routePoints 갱신 ✅
// _durationMin 갱신 ✅
// _steps(maneuver) 갱신 없음 ❌
// TTS 재시작 없음 ❌
```

**재탐색 후 경로선·ETA만 갱신, maneuver/TTS는 초기값(구 경로)으로 계속 동작.**

### C-2. heading 파라미터 여부

`routing_service.dart:123-134` — `fetchRoutes` 시그니처:
```dart
static Future<List<RouteResult>> fetchRoutes({
  required LatLng origin,
  required LatLng destination,
  List<LatLng> waypoints = const [],
})
```
**heading(bearing) 파라미터 없음.** 재탐색 시 현재 주행 방향이 Valhalla에 전달되지 않아 U-turn 경로 반환 가능성 있음.

### C-3. maneuver/TTS 갱신 상태

| 상황 | _steps 갱신 | TTS 안내 | 상태 |
|---|---|---|---|
| 최초 경로 진입 | `initState:153-156` — widget.maneuvers → `_steps` 변환 | `_announceStep(0)` ✅ | 정상 |
| 재탐색 후 | 없음 ❌ | 없음 ❌ | **버그** |

**feat/reroute-maneuver-fix 브랜치**에서 해결 구현됨 — 미머지:
- `_applyRouteGuidance()` 추출 (재사용 가능)
- 재탐색 후 `_applyRouteGuidance(routes[selIdx].maneuvers)` 호출
- `_stepIdx = 0; _lastAnnouncedIdx = -1;` 초기화
- `_announceStep(0)` 으로 TTS 재시작

---

## D. 브랜치 현황

### D-1. 전체 브랜치 목록

```
main                      (HEAD, 082d6e5)
feat/map-language         (이미 main에 머지됨 — 082d6e5 직계 조상)
feat/maplibre-migration   (마지막 커밋 c849693)
feat/reroute-maneuver-fix (마지막 커밋 d6af1b2)
backup-osm-20260531       (마지막 커밋 fba4054)
```

### D-2. feat/reroute-maneuver-fix 상세

| 항목 | 내용 |
|---|---|
| main 머지 여부 | **미머지** |
| main 대비 diff | 2파일 (nav_screen.dart +31/-12줄, PROGRESS_goal4.md +69줄) |
| 핵심 변경 | `_applyRouteGuidance` 추출 + 재탐색 후 maneuver/TTS 재빌드 |
| 폰 검증 여부 | 미확인 |

### D-3. 미머지·정리 후보

| 브랜치 | 상태 | 권고 |
|---|---|---|
| `feat/map-language` | main에 완전 머지됨 | 삭제 가능 |
| `feat/reroute-maneuver-fix` | nav_screen 버그픽스, 미머지 | **검토 후 머지 필요** |
| `feat/maplibre-migration` | main과의 관계 미확인 (MapLibre 이식 중간 브랜치로 추정) | main에 이미 반영됐으면 삭제 |
| `backup-osm-20260531` | 오래된 OSM 백업 | 보관 결정 후 삭제 가능 |

---

## E. 설정/도로선호도/라우팅 연동

### E-1. 도로 선호도 코드 존재 여부

**이미 존재함** — `lib/services/routing_service.dart`:

| 위치 | 내용 |
|---|---|
| `:71` | `static const _speedCountrysideKmh = 30.0;` |
| `:75-77` | `_courseNames = ['시골길', '지방도로', '국도']` |
| `:85-101` | `_ruralBalancedOpts` — 시골길 과다우회 완화 costing |
| `:156-199` | 코스별 `class_factors` (시골/지방/국도 각 상세 설정) |
| `:344-408` | 시골 1.3배 폴백 로직 (`_ruralDetourThreshold`) |

**현황**: 3가지 코스(시골/지방/국도)는 `fetchRoutes` 호출마다 병렬 계산됨. 그러나 어느 코스를 선호하는지 사용자 설정 연동이 없음 — 선택 UI는 경로 카드에서 좌우 스와이프 방식으로 구현된 것으로 보임(main_map_screen 내).

### E-2. SettingsScreen Phase 2 TODO 위치

모두 `lib/screens/settings_screen.dart`:
- `:38` 도로 선호도 — RoutingService costing 연동 가능 (인프라 준비됨)
- `:39` 내비뷰 설정
- `:40` 안내 음성 / 안내 언어
- `:43` 다크모드
- `:44` 지도 다운로드
- `:47` 약관 / 오픈소스 라이선스

---

## F. 종합: 남은 큰 작업

| # | 작업 | 상태 | 선행 작업 | 폰 검증 |
|---|---|---|---|---|
| 1 | **feat/reroute-maneuver-fix 머지** — 재탐색 후 maneuver/TTS 재빌드 | 부분 (브랜치 구현됨, 미머지) | 없음 | 필요 |
| 2 | **fetchRoutes heading 파라미터** — 재탐색 시 bearing 전달로 U-turn 방지 | 미착수 | #1 머지 후 | 필요 |
| 3 | **ETA 실효속도 보정** — nav_screen.dart:35 TODO, Valhalla time 보정 | 미착수 | 없음 | 필요 |
| 4 | **설정 Phase 2: 도로 선호도 UI 연동** — SettingsScreen → RoutingService costing 연결 | 미착수 (서버측 준비됨) | 없음 | 필요 |
| 5 | **설정 Phase 2: 기타** — 안내 음성/언어, 다크모드, 지도 다운로드, 약관 | 미착수 | #4 이후 | 필요 |
| 6 | **미아 화면 처리** — RouteOptionsScreen 연결 또는 삭제, DrivingScreen 삭제 | 미착수 | 없음 | 불필요 |
| 7 | **브랜치 정리** — feat/map-language 삭제, feat/maplibre-migration 관계 확인, backup 정리 | 미착수 | 없음 | 불필요 |

### 우선순위 근거

- **즉시 머지 가능**: #1 (`feat/reroute-maneuver-fix`) — diff가 2파일 31줄로 작고, 현재 내비에서 재탐색 후 maneuver/TTS가 구 경로 기준으로 동작하는 버그를 막고 있음
- **#1 이후 연속 작업**: #2 (heading) — 재탐색 품질 개선
- **독립 작업**: #4 (도로선호도 설정 연동) — RoutingService 인프라가 이미 있어 UI 연결만 필요
- **나중**: #3 (ETA 보정), #5 (기타 설정), #6 (화면 정리), #7 (브랜치 정리)
