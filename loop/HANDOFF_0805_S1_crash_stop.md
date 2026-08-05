GOAL: 백화·크래시(`Invalid argument(s): 0.0`)를 완전히 멎게 한다 — daylight_bar 방어 + clamp 전수 감사 + 릴리스 ErrorWidget 폴백 + 크래시 로그 폭주 차단.

# HANDOFF — S1 · 백화·크래시 완전 정지

- 작성 2026-08-05 · 브랜치 `verify/ride-0711` · HEAD `e61e3ca`
- 근거: [RECON_0805_testride0802_master_plan.md](RECON_0805_testride0802_master_plan.md) §2 / §5-3
- 대장: [CHECKLIST_0805_testride0802.md](CHECKLIST_0805_testride0802.md) S1
- 실측 증거: 로그 `YNAV_CRASH` **56,789건 전부 동일 문자열** ·
  Firebase 362건/6명 · `daylight_bar.dart - DaylightBar.build` 지목

---

## 0. 착수 전 확정된 사실 (다시 조사하지 마라)

`num.clamp`는 **상한 < 하한이면 `ArgumentError(lowerLimit)`를 던진다.**
`lowerLimit`이 `0.0`이므로 메시지가 정확히 `Invalid argument(s): 0.0`.
로그 문자열과 일치 → 가설 아님, **확정**.

`build()`가 던지면 Flutter가 서브트리를 `ErrorWidget`으로 갈아끼우고,
릴리스 기본 빌더는 **회색/흰 박스**를 그린다 → 마스터가 본 "백화".

---

## 1. clamp 전수 재감사 결과 (Claude가 이미 수행 — 이 표를 그대로 따르라)

> ⚠️ **체크리스트의 줄번호는 S0 커밋으로 밀려 낡았다.** 아래가 현재 HEAD 기준 실측이다.
> 그리고 체크리스트가 "위험"으로 적어둔 것 중 **절반은 이미 가드되어 있다.**
> 멀쩡한 코드를 건드려 회귀를 만들지 마라.

### 1-A. 반드시 고쳐야 하는 곳 (상한 < 하한 도달 가능)

| # | 위치 | 문제 | 비고 |
|---|---|---|---|
| 1 | `lib/core/widgets/daylight_bar.dart:109` | `handleY.clamp(0.0, totalH - 24)` — `totalH < 24`면 폭발 | **주범. 56,789건의 출처** |
| 2 | `route_progress_provider.dart:320` | `_clampIdx`: `i.clamp(0, _pts.length - 1)` — `_pts` 빈 경우 상한 -1 | 재탐색 중 경로 일시 소멸 |
| 3 | `route_progress_provider.dart:374` | `_cumFromStartM.length - 1` — 빈 리스트 가드 없음 | `hasNonTrivial` 체크는 비어있음을 안 막는다 |
| 4 | `route_progress_provider.dart:378` | 같음 (`_zones[z].beginShapeIdx`) | 3번과 같은 루프 |
| 5 | `nav_screen.dart:563` | `prog.activeStepIdx.clamp(0, _steps.length - 1)` — `_steps` 빈 경우 | **매 progress 틱마다 호출** — 폭주 경로 |
| 6 | `nav_screen.dart:3031` | `.clamp(0.0, p.nextCameraPostZoneM.toDouble())` — 음수면 폭발 | 현재 기본 0. 방어만 |
| 7 | `main_map_screen.dart:1455` | `idx.clamp(0, routes.length - 1)` 후 `routes[selIdx]` | `routes` 빈 가드 없음 |
| 8 | `main_map_screen.dart:1623` | `.clamp(0, _fetchedRoutes.length - 1)` | **바로 다음 줄이 `selIdx < _fetchedRoutes.length`를 검사** — 작성자도 빈 경우를 알고 있었는데 clamp가 먼저 터진다 |
| 9 | `waypoint_management_sheet.dart:49` | `idx.clamp(0, routes.length - 1)` 후 `routes[selIdx]` | `routes` 빈 가드 없음 |

### 1-B. **이미 안전 — 손대지 마라** (확인 완료)

| 위치 | 왜 안전한가 |
|---|---|
| `routing_service.dart:935, 941` | 함수 진입부 `if (cumFromStartM.isEmpty) return null;` |
| `nav_screen.dart:850` | `if (mounted && routes.isNotEmpty)` 안쪽 |
| `nav_screen.dart:1700` | `if (_fetchedRoutes.isNotEmpty)` 안쪽 |
| `nav_screen.dart:1785, 1800` | `if (_routePoints.length < 2) return;` 이후 |
| `main_map_screen.dart:1649` | `if (allRoutes.isNotEmpty)` 안쪽 |
| `user_profile.dart:26` | `bikes.isNotEmpty ? ... : null` |
| `map_providers.dart:478` | 상한이 `current.length`(≥0), 하한 0 |
| `native_engine.dart:339`, `rear_camera_gauge.dart:67/310`, `slider_start_button.dart:126`, `nav_state_provider.dart:192/216`, `_currentZoom.clamp(10.0,14.0)` 계열 | 상한이 상수 또는 `double.maxFinite/infinity` |

> `tour_summary_detail_screen.dart:199` `.clamp(squareMapHeight, screenWidth*3.0)`은
> `screenWidth < 33.3` 논리픽셀에서만 역전된다 — 실기기에서 도달 불가.
> **이번 스코프 밖.** 고치지 말고 보고서에만 한 줄 남겨라.

---

## 2. 해야 할 일

### 2-1. 공용 안전 clamp 헬퍼 신설

`lib/core/utils/safe_clamp.dart` 신설 (`lib/core/utils/`는 없으니 만들어라):

```dart
extension SafeClamp on num {
  /// 상한이 하한보다 작으면 하한을 반환한다 — dart:core `clamp`는 이 경우
  /// ArgumentError를 던진다. 렌더·인덱스 경로에서 그 예외는 프레임 전체를
  /// ErrorWidget으로 날려버리므로, 값이 뭉개지더라도 던지지 않는 쪽이 옳다.
  num clampSafe(num lower, num upper) =>
      upper < lower ? lower : clamp(lower, upper);
}
```

- 반환 타입은 `clamp`와 동일하게 `num`. 호출부에서 `.toDouble()`/`.toInt()`로 받아라.
- **주의**: 이건 "의미가 없는 값이라도 던지지만 않으면 되는" 자리에만 쓴다.
  리스트가 비었으면 인덱싱 자체가 틀린 자리는 아래 2-3처럼 **조기 반환**이 정답이다.

### 2-2. `daylight_bar.dart` — 주범 수정

두 겹으로 막아라.

**(a) 게이지 내부 방어** (`:95`, `:109`)

- `totalH`가 유한하지 않거나 `<= 0`이면 게이지 스택을 그리지 말고
  `SizedBox.shrink()` 반환.
- 핸들 `top`은 `clampSafe(0.0, totalH - 24)` 사용.
- `totalH < 24`면 핸들 아이콘 자체를 생략(24px 아이콘이 들어갈 자리가 없다).
  바(bar)만 그린다.

**(b) 위젯 전체 최소높이 보장 — 축약형 렌더**

`build()` 최상단을 `LayoutBuilder`로 감싸고 가용높이로 분기:

| 가용높이 | 렌더 |
|---|---|
| `< 60px` | `SizedBox.shrink()` — 아무것도 안 그린다 |
| `60 ~ 118px` | **축약형**: 상/하단 시간 라벨(fontSize 7) 생략, 아이콘 18px 2개 + 게이지만 |
| `>= 118px` | 현행 전체 렌더 |

- 118px 근거: 고정 크롬(아이콘 18 + 라벨 ~9 + 패딩·간격) 상하 합 ≈ 94px + 게이지 24px.
  상수로 뽑고 주석에 이 계산을 적어라 (`_kFullRenderMinH`, `_kAbbrevMinH`).
- 축약형에서도 `Expanded` + `LayoutBuilder` 경로가 (a)의 방어를 그대로 타야 한다.
- 폭(38)·모양·색은 바꾸지 마라. **이건 버그픽스지 리디자인이 아니다.**

### 2-3. 나머지 8곳 — 자리마다 맞는 방식으로

**리스트 인덱싱이 뒤따르는 곳(2·3·4·5·7·8·9)은 `clampSafe`로 때우지 마라.**
빈 리스트를 clamp로 0으로 만들어봐야 바로 다음 줄 `list[0]`이 `RangeError`로 터진다.
→ **빈 경우 조기 반환**이 정답.

- `route_progress_provider.dart:320` `_clampIdx` — `_pts.isEmpty`면 0 반환하되,
  **호출부가 `_pts[idx]`를 하는지 확인**하고 하면 그 호출부에서 막아라.
- `:374/:378` — 루프 진입 전에 `if (_cumFromStartM.isEmpty) return null;`(또는 빈 Set).
- `nav_screen.dart:563` — `_steps.isEmpty`면 `_stepIdx = 0`으로 두고 clamp 건너뛰기.
- `main_map_screen.dart:1455` / `waypoint_management_sheet.dart:49` —
  `routes.isEmpty`면 폴리라인 갱신을 건너뛰고 조기 반환.
- `main_map_screen.dart:1623` — `_fetchedRoutes.isEmpty`면 `durationMin = 0`으로
  가고 clamp를 타지 않게. (바로 아래 `selIdx < _fetchedRoutes.length` 검사와
  중복되지 않게 정리해라.)
- `nav_screen.dart:3031` — `clampSafe` 적용 (순수 수치, 인덱싱 없음).

### 2-4. 릴리스 `ErrorWidget.builder` 폴백

`lib/main.dart` `main()`에서 `runApp` 전에:

- `kReleaseMode`일 때만 커스텀. **디버그는 기본 빨간 박스를 유지**해라 —
  개발 중 에러를 숨기면 안 된다.
- 폴백은 **무해한 투명 위젯**(`SizedBox.shrink()`). 흰/회색 박스 금지 —
  마스터가 본 백화가 정확히 그 박스다.
- Crashlytics 보고 경로(`FlutterError.onError`)는 건드리지 마라. 별개 배관이다.

### 2-5. 크래시 로그 폭주 차단 (RECON §2-3 근거)

초당 2~3회 예외마다 ① 스택트레이스 ② **디스크 append** ③ **Crashlytics 업로드**가
반복돼 4시간에 36,680회 — 발열·배터리의 직접 원인이다. 예외를 없애도
다른 예외가 같은 패턴을 만들 수 있으니 배관 자체에 상한을 둬라.

`lib/core/crash_reporting.dart`:

- 동일 예외 문자열(truncate 후)에 대해 **중복 억제**: 같은 시그니처는
  최초 1회 + 이후 60초에 1회까지만 `debugPrint` / `recordError`.
- 억제된 건수는 다음 발행 시 `suppressed=N`으로 함께 남겨 정보가 사라지지 않게.
- 전체 시그니처 맵이 무한 증식하지 않도록 상한(예 50개) 두고 초과 시 가장 오래된 것 제거.

### 2-6. `lib/widgets/daylight_bar.dart` shim 판단

`export '../core/widgets/daylight_bar.dart';` 한 줄짜리 re-export.
**`lib/`·`test/` 전체에서 이 경로를 import하는 코드가 0건임을 이미 확인했다.**
→ **삭제해라.** 삭제 후 `flutter analyze`로 참조 0건 재확인.

---

## 3. 검증 (전부 통과해야 PASS)

### 3-1. 주 검증 — 위젯 테스트 (기기 없이 결정론적)

`test/core/widgets/daylight_bar_test.dart` 신설:

```
높이 = [0, 10, 24, 60, 90, 118, 120, 285, 300, 800] px
각 케이스: ConstrainedBox(maxHeight: h)에 DaylightBar를 넣고 pumpWidget
합격: 전 케이스 expect(tester.takeException(), isNull)
```

- **285px = 갤럭시 플립7 커버화면 논리높이 근사** — 마스터의 그 기기가 없어도 커버된다.
- `progress` 값도 `[0.0, 0.5, 1.0]` 조합으로 돌려라 (핸들이 상/하단 끝일 때가 경계).
- 축약형 분기가 실제로 갈리는지도 단정해라: 높이 90px에서 시간 라벨 텍스트가
  **없고**, 300px에서는 **있음**.

### 3-2. 회귀 테스트 — 빈 리스트 경로

2-3에서 고친 자리 중 **순수 로직으로 도달 가능한 것**에 테스트를 붙여라
(최소: `route_progress_provider`의 빈 `_pts`/빈 `_cumFromStartM`,
`user_profile`은 이미 안전하니 제외).
UI 위젯 안쪽이라 테스트가 과한 자리는 억지로 만들지 말고 보고서에 적어라.

### 3-3. 정적 검사

```
flutter analyze          → 이슈 0
flutter test             → 전건 통과 (현재 314건 + 신규)
```

**기존 314건 중 하나라도 깨지면 그건 회귀다. 테스트를 고치지 말고 코드를 고쳐라.**

### 3-4. 실기기 (마스터 몫 — 코더는 하지 마라)

- A34 `adb shell wm size 720x748` → 커버화면 흉내 → 실렌더 확인 → **`wm size reset` 필수**
- 세로/가로 × 코스시트 열림·닫힘 × 일반/PIP/분할화면에서
  `YNAV_CRASH ... Invalid argument(s): 0.0` **0건**

---

## 4. 지켜야 할 선

- **S1 스코프만.** S2(네트워크)·S3(라이프사이클)은 이 세션에서 건드리지 마라.
  clamp를 보다가 POI 디바운스나 PIP 코드가 눈에 띄어도 손대지 마라.
- `git add -A` 금지. **수정한 파일만 이름으로 스테이징.** 브랜치를 다른 세션과 공유 중이다.
- 1-B의 "이미 안전" 목록을 예방적으로 `clampSafe`로 바꾸지 마라 — 노이즈 디프다.
- 디자인 변경 금지. DaylightBar의 색·폭·아이콘·라운드는 그대로.
- 막히면 추측하지 말고 멈추고 보고해라.
