# REPORT_SUNTIME — 박명→일출일몰 전환 보고

## 0단계 게이트 결과

### (a) 수정 지점 확인
| 항목 | 라인 |
|------|------|
| `fetchRemote` twilight 파싱 | 66-67 (교체 대상) |
| `_localCalc` civilOffset 가감 | 113-114 (제거 대상) |
| `calculate()` → null 시 `_localCalc` fallback | 93 (흐름 확인됨) |

### (b) API sunrise/sunset 키 확인
**확인됨** (curl 직접 응답):
```json
{"results":{"sunrise":"2026-06-04T20:10:31+00:00","sunset":"2026-06-05T10:50:25+00:00",...},"status":"OK"}
```
- `results['sunrise']` UTC 20:10 = KST 05:10 (한국 일출 ✓)
- `results['sunset']` UTC 10:50 = KST 19:50 (한국 일몰 ✓)

**채택: `sunrise`/`sunset` 키로 교체** + 방어코드(`sRaw == null` 시 return null) 추가.

---

## 변경 전/후 diff

### ① API 경로 (fetchRemote)

**Before:**
```dart
// API 반환 형식: ISO 8601 UTC (e.g. "2024-06-03T20:17:00+00:00")
// nautical_twilight_begin = BMNT, nautical_twilight_end = EENT
final bmntUtc = DateTime.parse(results['nautical_twilight_begin'] as String);
final eentUtc = DateTime.parse(results['nautical_twilight_end'] as String);
```

**After:**
```dart
// API 반환 형식: ISO 8601 UTC (e.g. "2026-06-05T20:10:31+00:00")
// sunrise/sunset 키 사용 (0단계 curl로 존재 확인됨)
final sRaw = results['sunrise'];
final eRaw = results['sunset'];
if (sRaw == null || eRaw == null) {
  debugPrint('[daylight] api missing sunrise/sunset keys, fallback to local');
  return null;
}
final bmntUtc = DateTime.parse(sRaw as String);
final eentUtc = DateTime.parse(eRaw as String);
```

`.toLocal()` 변환은 기존 그대로 유지 (isUtc=false 보장).

### ② 로컬 경로 (_localCalc)

**Before:**
```dart
const civilOffset = Duration(minutes: 30);
...
final bmnt = sunriseLocal.subtract(civilOffset);  // 일출 - 30분 = BMNT
final eent = sunsetLocal.add(civilOffset);         // 일몰 + 30분 = EENT
```

**After:**
```dart
// civilOffset 제거 — 패키지가 주는 일출/일몰 그대로 사용
final bmnt = DateTime(date.year, date.month, date.day,
    sunrise.hour, sunrise.minute, sunrise.second);
final eent = DateTime(date.year, date.month, date.day,
    sunset.hour, sunset.minute, sunset.second);
```

(sunriseLocal/sunsetLocal 중간변수 제거, bmnt/eent로 직접 재포장)

### ③ _fallback 하드코딩 조정

**Before:**
```dart
bmnt: base.add(const Duration(hours: 6)),   // BMNT 근사
eent: base.add(const Duration(hours: 20)),  // EENT 근사
```

**After:**
```dart
// 일출/일몰 근사 (API·로컬 계산 모두 실패 시만 사용)
bmnt: base.add(const Duration(hours: 5, minutes: 30)),
eent: base.add(const Duration(hours: 19, minutes: 30)),
```

### 불변식 확인
- 반환 필드명: `(bmnt:, eent:)` 유지 — 소비처(map_providers, driving_screen) 무수정
- cycleState/isDaytime의 `isAfter`/`isBefore` 식: 수정 없음 (값 교체로 자동 적용)
- 두 경로 모두 `isUtc == false` 유지

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.2s)

---

## 폰 실측 체크리스트

- [ ] 슬라이더 상단/하단이 일출 05:10 / 일몰 19:50 표시 (박명 04:40/20:20에서 변경됨)
- [ ] 현재(낮 13시대) 인디케이터 낮 위치, 디밍 없음
- [ ] logcat: `adb logcat -d | grep daylight`
      - `path=api` 또는 `path=local` 확인
      - `bmnt` 값이 05:10 / `eent` 값이 19:50 류인지 확인
      - `isUtc=false` 확인 (두 경로 모두)
- [ ] driving_screen(주행화면) 일출일몰 라벨도 동일하게 변경 (daylightTimesProvider 경유, bmnt/eent 필드명 그대로)
- [ ] 박명 구간(일출 전 30분, 일몰 후 30분)이 이제 "밤"으로 분류됨 — 의도된 동작

## 진단 분기

| 증상 | 원인 | 대응 |
|------|------|------|
| 값이 여전히 04:40/20:20 | API 캐시에 구 값 남음 | 앱 완전 종료 후 재시작 |
| `path=api, missing sunrise/sunset keys` | API 구조 변경 | `civil_twilight_begin/end` 키로 전환 고려 |
| 로컬 경로 bmnt가 이상한 값 | 패키지 `sunrise.hour` 필드 != KST | RECON_NIGHTMODE 프로브 재실행으로 확인 |
