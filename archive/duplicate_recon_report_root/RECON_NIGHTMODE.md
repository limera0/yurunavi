# RECON_NIGHTMODE (야간모드/일출일몰 버그)

## 0. 관련 파일 목록

| 파일 | 역할 |
|------|------|
| `lib/services/daylight_service.dart` | BMNT/EENT 계산 서비스 (API+로컬 fallback), isDay/사이클 판정 |
| `lib/features/map/providers/map_providers.dart` | Riverpod 프로바이더: clockTick, daylightCycle, isDayProvider, isNightProvider |
| `lib/core/widgets/daylight_bar.dart` | 일출일몰 게이지 위젯 (라벨 표시) |
| `lib/features/map/presentation/main_map_screen.dart` | 야간 디밍 오버레이(LAYER 8) + _RightPanel DaylightBar 호출 |
| `lib/features/navigation/presentation/nav_screen.dart` | 내비 화면 야간 디밍 오버레이 (동일 패턴) |
| `lib/main.dart` | isNightProvider → AppTheme.night 전환 (전체 테마) |
| `~/.pub-cache/hosted/pub.dev/sunrise_sunset_calc-3.0.0/` | 로컬 일출일몰 계산 패키지 |

---

## 1. 내부 시계 소스 (★)

**현재시각을 어디서/어떻게 얻나:**

- `map_providers.dart:194,197`: `clockTickProvider` — `DateTime.now()` 30초마다 emit
- `map_providers.dart:207`: `_daylightApiFetchProvider` — `DateTime.now()` (API fetch 날짜용)
- `map_providers.dart:219`: `daylightCycleProvider` — `DateTime.now()` (isDay 판정 `now` 인자)
- `map_providers.dart:235`: `daylightTimesProvider` — `DateTime.now()` (라벨 날짜용)
- `daylight_service.dart:140`: `DaylightService.cycleState()` 내부 — 전달받은 `now` 직접 사용

**DateTime.now() 그대로인가 / .toUtc() 변환인가:**
→ `DateTime.now()` 그대로. `.toUtc()` 변환 없음. **폰 현지시간(KST local-tagged).**

**판정: 폰 현지시간(KST)을 올바르게 쓰는가?**
→ **YES** — 시계 소스 자체는 정상. 버그는 시계 소스가 아니라 BMNT/EENT datetime 표현에 있음.

---

## 2. 일출일몰(BMNT/EENT) 계산 ★★★ 버그 위치

### 계산 위치
- `daylight_service.dart:84` — `DaylightService.calculate(lat, lng, date)`
  - API 캐시 → `fetchRemote()` (line 42)
  - 캐시 없으면 → `_localCalc(lat, lng, date)` (line 94)

### 입력 좌표
`daylightCycleProvider` (map_providers.dart:214-220):
```dart
final loc = ref.watch(currentLocationProvider);  // GPS 현위치
return DaylightService.cycleState(lat: loc.latitude, lng: loc.longitude, now: DateTime.now());
```
→ **현위치(_origin → currentLocationProvider) 사용. 하드코딩 아님.** ✓

### 입력 날짜·시간
→ `DateTime.now()` (local KST). 정상.

### UTC offset(KST +9) 처리 여부 — ★★★ 루트코즈

#### API 경로 (daylight_service.dart:65-71)
```dart
final bmntUtc = DateTime.parse(results['nautical_twilight_begin'] as String);
// API 반환: "2024-06-03T19:04:00+00:00" → isUtc=true, epoch=19:04Z June 3

const kst = Duration(hours: 9);
final r = (bmnt: bmntUtc.add(kst), eent: eentUtc.add(kst));
// bmnt = DateTime.utc(2024,6,4,4,4,0)  ← isUtc=true 유지, epoch=04:04Z June 4
```
코드 주석은 "toLocal() 하면 두 번 변환" 이라며 `.add(kst)` 사용을 정당화하지만
→ **이것이 잘못된 판단.** 결과 datetime은 UTC-tagged이므로 epoch = 04:04 UTC. **실제 KST 04:04의 epoch(= 19:04Z June 3)와 9시간 차이.**

#### 로컬 계산 경로 (sunrise_sunset_calc 패키지)
`getSunriseSunset` 반환 (sync.dart:125-127):
```dart
final defaultTime = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
// date = DateTime.now() → year/month/day = KST local date
// defaultTime = midnight UTC on that LOCAL date ← UTC midnight, NOT KST midnight

return SunriseSunsetResult(
  defaultTime.add(Duration(seconds: sunriseSeconds)),  // sunriseSeconds = KST local seconds
  defaultTime.add(Duration(seconds: sunsetSeconds)));
```
패키지가 KST local 초(예: 04시40분=16800s)를 UTC 자정(0:00Z)에 더함
→ `result.sunrise = DateTime.utc(date.year, date.month, date.day, 4, 40, 0)` — **isUtc=true, UTC clock=KST clock. epoch은 KST 04:40의 true epoch(前日 19:40Z)보다 9시간 뒤.**

### 판정: 현위치·현시간 기준이 맞는가?
→ **NO.** 좌표·날짜 입력은 맞지만, 결과 BMNT/EENT의 datetime epoch이 KST +9h 오차.

---

## 3. 야간모드 자동전환 트리거

### on/off 결정 조건
`daylight_service.dart:140`:
```dart
final bool isDay = now.isAfter(today.bmnt) && now.isBefore(today.eent);
```
`map_providers.dart:241`:
```dart
final isDayProvider = Provider<bool>((ref) {
  return ref.watch(daylightCycleProvider)?.isDay ?? true;
});
```
`map_providers.dart:247`:
```dart
final isNightProvider = Provider<bool>((ref) => !ref.watch(isDayProvider));
```

### 비교 오류의 실제 영향
- `now = DateTime.now()` at 12:00 KST → epoch = 2024-06-04T03:00:00Z
- `today.bmnt` (API path) = `DateTime.utc(2024,6,4,4,4,0)` → epoch = 04:04Z
- `now.isAfter(bmnt)`: 03:00Z > 04:04Z → **FALSE** → `isDay = false` → **정오에 밤 판정**

### 무엇에 묶여 있나
→ BMNT/EENT 계산 결과(DaylightService) 직결. 내부시계 자체는 정상, **계산 결과의 epoch 오류에 묶임.**

---

## 4. 화면 밝기 제어

### 밝기 깎는 코드 위치
`main_map_screen.dart:934-943` (LAYER 8):
```dart
if (!isDay)
  Positioned.fill(
    child: IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),  // 35% 검정 오버레이
      ),
    ),
  ),
```
동일 패턴: `nav_screen.dart:792-798`

→ 시스템 ScreenBrightness API 미사용. **Flutter UI 오버레이(35% 검정)로 화면을 어둡게 함.**
→ "화면 밝기 최소" 증상 = 이 오버레이가 정오에도 적용됨.

### 야간모드와 연동 지점
`!isDay` = `isNightProvider` → `isDayProvider` → `daylightCycleProvider` → 에포크 오류 경유.

---

## 5. 슬라이더 20:56/04:04 출처

`_RightPanel` (main_map_screen.dart:1143-1151):
```dart
final daylightCycle = ref.watch(daylightCycleProvider);
final topLabel = daylightCycle != null
    ? DateFormat('HH:mm').format(daylightCycle.topTime)
    : '--:--';
```

`daylightCycle.topTime = today.bmnt = DateTime.utc(2024,6,4,4,4,0)` (UTC-tagged)

Dart의 `DateFormat('HH:mm').format(utcDateTime)`:
→ UTC-tagged DateTime의 `.hour` 필드를 그대로 읽음 (UTC 시:분).
→ UTC 04:04 clock face = 의도한 KST 04:04와 우연히 일치 → **표시는 맞아 보임**

**표시가 맞아 보이는 이유**: UTC clock face = KST local clock face (버그에 의해). 표시만 맞고 epoch 비교는 틀림.

→ **20:56 / 04:04는 정상 KST BMNT/EENT 표시이나, 그 값들의 내부 epoch이 9시간 틀려서 낮밤 판정이 반대.**

---

## 6. 결론 — 가설 검증

### 마스터 가설(단일 시간소스 오류 → 셋 다 깨짐)이 맞는가?
→ **부분적으로 맞음.** 단, "시계 소스"가 아니라 "BMNT/EENT를 담는 DateTime의 UTC/local 태그 오류"가 단일 원인. 시계(`DateTime.now()`) 자체는 정상.

### 루트코즈 한 줄
> `DaylightService`가 반환하는 BMNT/EENT DateTime이 KST clock face를 **UTC-tagged**로 저장해, `DateTime.now()`(local-tagged)와의 `isAfter` 비교 시 epoch 기준으로 9시간 차이 발생 → 정오(KST 03:00 UTC)가 BMNT(04:04 UTC)보다 앞으로 판정돼 밤으로 인식.

### 수정해야 할 최소 지점 (파일:라인)

**`lib/services/daylight_service.dart` 단 1개 파일, 2개 지점:**

**① API 경로 — line 71:**
```dart
// BEFORE (버그):
final r = (bmnt: bmntUtc.add(kst), eent: eentUtc.add(kst));

// AFTER (수정):
final r = (bmnt: bmntUtc.toLocal(), eent: eentUtc.toLocal());
// bmntUtc.toLocal() on KST device: 2024-06-03T19:04:00Z → 2024-06-04T04:04:00+09:00
// isUtc=false, epoch = 19:04Z = KST 04:04의 correct epoch ✓
```
(Duration(hours:9) const 및 주석도 제거)

**② 로컬 계산 경로 — lines 105-107:**
```dart
// BEFORE (버그):
return (
  bmnt: sunrise.subtract(civilOffset),  // sunrise = UTC-tagged, wrong epoch
  eent: sunset.add(civilOffset),
);

// AFTER (수정):
// sunrise/sunset의 .hour/.minute는 KST local clock값 (패키지 설계상)
// DateTime(...)로 local-tagged datetime 재포장 → correct epoch
final sunriseLocal = DateTime(date.year, date.month, date.day,
    sunrise.hour, sunrise.minute, sunrise.second);
final sunsetLocal = DateTime(date.year, date.month, date.day,
    sunset.hour, sunset.minute, sunset.second);
return (
  bmnt: sunriseLocal.subtract(civilOffset),
  eent: sunsetLocal.add(civilOffset),
);
```

### 한 곳 수정으로 셋(시계·일출일몰·야간모드) 다 잡히는가?
→ **YES.** `daylight_service.dart` 2줄 수정으로:
- BMNT/EENT epoch 정상 → `isDay` 비교 정상 → 야간모드 정상
- `isDayProvider/isNightProvider` 정상 → 테마 전환 정상
- 디밍 오버레이 정상 → 화면 밝기 정상
- 라벨 표시: local-tagged DateTime을 DateFormat → 동일하게 "04:04" 표시 (변화 없음)

### 미확인/리스크 항목 (실행 턴에서 먼저 풀 것)

1. **`_fallback` 함수 (line 114-119)**: `DateTime(date.year, month, day)` + `Duration(hours:6/20)` → local-tagged이므로 정상. 수정 불필요 확인됨.

2. **API 캐시 키 `_cacheKey`**: 날짜를 `date.year/month/day` (local)로 씀 → KST date 기준. 수정 후에도 동일 → 문제없음.

3. **날짜 경계 케이스**: KST 자정 직후(00:00~00:59)에 `date.year/month/day` = 오늘 KST이지만 UTC는 전날. 수정 후 `bmntUtc.toLocal()`은 올바른 KST로 변환되므로 안전.

4. **API 미응답 시**: 로컬 fallback(`_localCalc`) 경로만 동작. 위 ② 수정으로 커버.

5. **실기기 재확인**: 수정 후 `logcat`에서 `DaylightService API fetch OK: BMNT=` 로그로 변환된 datetime의 `isUtc` 여부 확인 권장.
