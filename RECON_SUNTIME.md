# RECON_SUNTIME (박명→일출일몰 기준 전환)

## 1. daylight_service 반환 구조

### 반환 타입/필드명 (정확히)

| 함수 | 반환 타입 | 필드명 |
|------|-----------|--------|
| `fetchRemote()` | `({DateTime bmnt, DateTime eent})?` | `bmnt`, `eent` |
| `calculate()` | `({DateTime bmnt, DateTime eent})` | `bmnt`, `eent` |
| `_localCalc()` | `({DateTime bmnt, DateTime eent})` | `bmnt`, `eent` |
| `_fallback()` | `({DateTime bmnt, DateTime eent})` | `bmnt`, `eent` |
| `cycleState()` | `DaylightCycleState` | `isDay`, `progress`, `topTime`, `bottomTime` |
| `isDaytime()` | `bool` | — |
| `daylightProgress()` | `double` | — |

### DaylightCycleState 클래스 (line 8-24)
```dart
class DaylightCycleState {
  final bool isDay;
  final double progress;
  final DateTime topTime;    // 낮=BMNT, 밤=EENT (현재)
  final DateTime bottomTime; // 낮=EENT, 밤=익일BMNT (현재)
}
```

**핵심**: Dart record의 `bmnt`/`eent` 필드는 `daylight_service.dart` 내부에서만 사용. 외부에 노출되는 공개 인터페이스는 `DaylightCycleState.topTime/.bottomTime` (cycleState 소비자) 와 `daylightTimesProvider`의 `({DateTime bmnt, DateTime eent})` record 타입 (driving_screen 소비자).

---

## 2. API 경로

### API URL/제공자
`https://api.sunrise-sunset.org/json?lat=...&lng=...&date=...&formatted=0`
(sunrise-sunset.org, 무료 공개 API)

### 현재 파싱 키 (daylight_service.dart:65-67)
```dart
final bmntUtc = DateTime.parse(results['nautical_twilight_begin'] as String);
final eentUtc = DateTime.parse(results['nautical_twilight_end'] as String);
```

### 그 API가 `sunrise`/`sunset` 키도 주는가?
**리스크 항목 — 코드 내 확인 불가.** 코드 주석은 `nautical_twilight_begin/end`만 언급. API URL이 `api.sunrise-sunset.org`이고 `formatted=0` 파라미터를 사용하며, 이 제공자는 일반적으로 `sunrise`, `sunset`, `civil_twilight_*`, `nautical_twilight_*`, `astronomical_twilight_*` 등을 함께 반환하는 것으로 알려짐. **그러나 실코드에서 `results['sunrise']` 키가 동작하는지 런타임 확인 전까지는 불확실.** → 실행 턴에서 `dart run` 프로브 또는 curl로 확인 필수.

---

## 3. 로컬 패키지 (sunrise_sunset_calc)

### sunrise/sunset 직접 제공 여부
**YES — 기확인.** `SunriseSunsetResult` (sunrise_sunset_calc_result.dart:2-10):
```dart
class SunriseSunsetResult {
  DateTime sunrise;   // ← 직접 일출 제공
  DateTime sunset;    // ← 직접 일몰 제공
}
```
프로브 결과: KST offset=9, 서울 좌표 → `sunrise.hour=5` (05:12, 6월 한국 일출 KST ✓).

### 현재 _localCalc가 civilOffset을 가감하는 이유
`_localCalc` (line 98, 113-114):
```dart
const civilOffset = Duration(minutes: 30);
final bmnt = sunriseLocal.subtract(civilOffset);  // 일출 - 30분 = BMNT
final eent = sunsetLocal.add(civilOffset);         // 일몰 + 30분 = EENT
```
→ **박명(BMNT/EENT)을 만들기 위해** civil_twilight 근사값으로 ±30분을 가감하는 것.

### 일출일몰로 전환하려면?
`civilOffset` 가감을 제거하면 됨:
```dart
// AFTER:
return (bmnt: sunriseLocal, eent: sunsetLocal);  // civilOffset 없음
```
`sunriseLocal`/`sunsetLocal`는 이미 local-tagged로 정상. 추가 작업 없음.

---

## 4. 필드 소비처 목록 — 필드명 변경 시 영향 범위

### Record `({DateTime bmnt, DateTime eent})` `.bmnt`/`.eent` 직접 접근
| 파일 | 라인 | 용도 |
|------|------|------|
| `daylight_service.dart` | 72, 116, 125-126, 148, 151-152, 157-158, 162, 164, 171-172, 184 | 내부 계산/판정 |
| `map_providers.dart` | 228-236 (`daylightTimesProvider` 반환 타입 `({DateTime bmnt, DateTime eent})`) | Provider 반환 타입 |
| `driving_screen.dart` | 384 `.bmnt`, 387 `.eent` | DaylightBar 라벨 |

### `DaylightCycleState.topTime`/`.bottomTime` 접근 (필드명 변경 무관)
| 파일 | 라인 | 용도 |
|------|------|------|
| `main_map_screen.dart` | 1148 `.topTime`, 1151 `.bottomTime` | DaylightBar 라벨 |
| `nav_screen.dart` | 702 `.topTime`, 705 `.bottomTime` | DaylightBar 라벨 |

### `DaylightCycleState.isDay` 접근
| 파일 | 라인 |
|------|------|
| `main_map_screen.dart` | 1145 |
| `nav_screen.dart` | 479 |
| `map_providers.dart` | 241 (`isDayProvider`) |

---

## 5. 야간판정 식 위치 + 현재 기준

**위치 1**: `daylight_service.dart:148` (`cycleState` 내부)
```dart
final bool isDay = now.isAfter(today.bmnt) && now.isBefore(today.eent);
```
→ `today` = `calculate()` 반환 record. `today.bmnt`/`today.eent`로 박명 기준 판정.

**위치 2**: `daylight_service.dart:184` (`isDaytime` 내부)
```dart
return now.isAfter(r.bmnt) && now.isBefore(r.eent);
```
→ 동일 패턴. 박명 기준.

**현재 판정 기준**: BMNT/EENT (박명). 일출일몰로 바꾸면 `calculate()` 반환값이 바뀌므로 **판정 코드 자체는 수정 불필요** — 담는 값만 교체하면 자동 적용.

---

## 6. 슬라이더 위젯이 읽는 필드

`DaylightBar` 위젯 파라미터 (daylight_bar.dart:12-13):
```dart
final String sunriseLabel;  // 상단 표시 (이미 의미상 "일출/시작시각")
final String sunsetLabel;   // 하단 표시 (이미 의미상 "일몰/종료시각")
```

호출부에서 `DateFormat('HH:mm').format(daylightCycle.topTime)` → `sunriseLabel`로 전달.
`DaylightBar`는 string만 받으므로 **위젯 자체는 수정 불필요**.

소비처별 라벨 공급:
- `main_map_screen.dart:1147-1151`: `daylightCycle.topTime`/`bottomTime` → format → string
- `nav_screen.dart:701-705`: 동일
- `driving_screen.dart:383-387`: `daylightTimes.bmnt`/`.eent` → format → string (별도 provider 사용)

---

## 7. 결론 — 스코프 판단

### 옵션A: 필드명 유지(`bmnt`/`eent`), 담는 값만 일출/일몰로 교체
- 수정 파일: **`daylight_service.dart` 단 1개**
- 변경 지점:
  - `_localCalc`: `civilOffset` 가감 제거 (2줄 제거)
  - `fetchRemote`: `results['nautical_twilight_begin/end']` → `results['sunrise/sunset']` 교체 (2줄)
  - `_fallback`: `hours:6`/`hours:20` → `hours:6`/`hours:19` 등 미세 조정 (선택)
  - 클래스 주석/변수명 내 "BMNT/EENT" 텍스트 업데이트 (옵션)
- 단점: `bmnt`/`eent` 필드명이 "BMNT/EENT 박명"을 의미하는데 실제로는 일출/일몰 저장 → 명칭 불일치

### 옵션B: 필드명 `bmnt`→`sunrise`, `eent`→`sunset`으로 개명
- 수정 파일 N개: `daylight_service.dart`, `map_providers.dart`, `driving_screen.dart` (최소 3개)
- `daylightTimesProvider` 반환 타입 `({DateTime bmnt, DateTime eent})` → `({DateTime sunrise, DateTime sunset})`로 변경
- `driving_screen.dart:384/387` `.bmnt`/`.eent` → `.sunrise`/`.sunset`
- 장점: 의미 일치, 기술부채 해소

### 정찰자 권장
**옵션A 채택** — daylight_service 단일 파일 수정, 회귀 위험 최소. `bmnt`/`eent`는 내부 record 필드(private 준하는 범위)이고 `DaylightBar`의 공개 파라미터는 이미 `sunriseLabel`/`sunsetLabel`로 올바름. 명칭 불일치는 주석으로 보완 가능.

### 일출/일몰 값 확보 방법 (경로별)
| 경로 | 방법 |
|------|------|
| 로컬 (`_localCalc`) | `civilOffset` subtract/add 제거 → `sunriseLocal`/`sunsetLocal` 그대로 반환. 패키지가 이미 일출/일몰 제공. |
| API (`fetchRemote`) | `results['nautical_twilight_begin/end']` → `results['sunrise']`/`results['sunset']` 교체. **단, 런타임 전 키 존재 미확인 — 리스크.** |

### 미확인/리스크

1. **API `sunrise`/`sunset` 키 런타임 존재 여부 미확인** (★최우선 실행 턴 확인 필요)
   - 확인 방법: `curl "https://api.sunrise-sunset.org/json?lat=37.27&lng=127.0&date=today&formatted=0"` 또는 `dart run` 프로브
   - 만약 `sunrise` 키 없으면 → civil_twilight 키(`civil_twilight_begin/end`)로 대체 또는 로컬 패키지 값만 사용

2. **`_fallback` 하드코딩값 조정**: 현재 `hours:6`(BMNT 근사)→`hours:5:30`(일출 근사), `hours:20`(EENT 근사)→`hours:19:30`(일몰 근사). 미세 차이이므로 옵션.

3. **`cycleState` 야간 로직 경계**: 일출/일몰 기준으로 바꾸면 박명 구간(일출 전 30분, 일몰 후 30분)이 "밤"으로 분류. 기어라이더 UX상 이 시간대 디밍 오버레이 적용이 맞는지 확인 필요.

4. **`driving_screen.dart`**: `daylightTimesProvider`를 소비하며 `.bmnt`/`.eent`를 직접 참조. 옵션A라면 필드명 그대로이므로 수정 불필요.
