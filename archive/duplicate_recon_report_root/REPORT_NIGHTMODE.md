# REPORT_NIGHTMODE — 야간모드 9시간 오차 수정 보고

## 0단계 게이트 판정

### (b) 패키지 반환 epoch 분석
`sunrise_sunset_calc-3.0.0/lib/src/sunrise_sunset_calc_sync.dart:125-127`:
```dart
final defaultTime = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
return SunriseSunsetResult(defaultTime.add(Duration(seconds: sunriseSeconds)), ...);
```
`isUtc=true` (UTC-tagged) 반환 확인.

### (c) 실측 프로브 결과 (프로젝트 루트에서 dart run)
```
[KST offset=9] sunrise=2026-06-05 05:12:01.000Z isUtc=true hour=5 toLocalHour=5
[KST offset=9] sunset =2026-06-05 19:49:18.000Z  isUtc=true  hour=19 toLocalHour=19
```

**판정: Judgment A 확정**
- `sunrise.hour=5` = KST 실제 일출시각(05:12). UTC-tagged에 LOCAL clock 저장.
- `toLocalHour=5` (서버가 UTC 환경이라 변환 없음 — 패키지가 UTC epoch을 쓰는 게 아님)
- **채택: ② `DateTime(date.year,..,sunrise.hour,sunrise.minute,sunrise.second)` local 재포장**

---

## 변경 전/후 diff

### ① API 경로 (daylight_service.dart:65-76)

**Before:**
```dart
const kst = Duration(hours: 9);
final r = (bmnt: bmntUtc.add(kst), eent: eentUtc.add(kst));
// bmnt = DateTime.utc(..., 4, 4, 0) — isUtc=true, epoch=04:04Z ← KST 13:04에 해당
```

**After:**
```dart
final bmnt = bmntUtc.toLocal();   // isUtc=false, epoch=19:04Z June prev ← KST 04:04 정확
final eent = eentUtc.toLocal();
final r = (bmnt: bmnt, eent: eent);
debugPrint('[daylight] path=api bmnt=$bmnt eent=$eent isUtc=${bmnt.isUtc}');
```

### ② 로컬 계산 경로 (daylight_service.dart:97-115)

**Before:**
```dart
return (
  bmnt: sunrise.subtract(civilOffset),  // sunrise isUtc=true, epoch=05:12Z ← KST 14:12에 해당
  eent: sunset.add(civilOffset),
);
```

**After:**
```dart
// UTC-tagged에 KST clock값 저장 → local-tagged로 재포장
final sunriseLocal = DateTime(date.year, date.month, date.day,
    sunrise.hour, sunrise.minute, sunrise.second);   // isUtc=false, epoch=KST 05:12 정확
final sunsetLocal = DateTime(date.year, date.month, date.day,
    sunset.hour, sunset.minute, sunset.second);
final bmnt = sunriseLocal.subtract(civilOffset);
final eent = sunsetLocal.add(civilOffset);
debugPrint('[daylight] path=local bmnt=$bmnt eent=$eent isUtc=${bmnt.isUtc}');
return (bmnt: bmnt, eent: eent);
```

**불변식 만족**: 두 경로 모두 `bmnt.isUtc == false` → `DateTime.now()`(local)와의 `isAfter` 비교 정상화.

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.6s)

---

## 폰 실측 체크리스트

- [ ] 현재(낮) 시각에 야간 디밍 오버레이 사라짐 (화면 정상 밝기)
- [ ] 일출일몰 슬라이더의 해/달 인디케이터가 '낮' 위치
- [ ] logcat 확인: `adb logcat | grep daylight`
      - `isUtc=false` 확인 (두 경로 모두)
      - `path=api` 또는 `path=local` 어느 경로가 실제로 동작하는지 확인
- [ ] 슬라이더 라벨(상단 BMNT / 하단 EENT)이 한국 KST 표준 시각으로 표시 (깨짐 없음)
- [ ] (밤시간대 또는 기기시계 저녁으로 변경 후) 야간 디밍 오버레이 정상 진입

## 진단 분기 (만약 여전히 이상)
| 증상 | 원인 | 대응 |
|------|------|------|
| `logcat isUtc=true` | 캐시에 이전 UTC-tagged 값 남아있음 | 앱 완전 재시작 (캐시 클리어) |
| 라벨 시각 9시간 틀림 | DateFormat이 local 변환 중 | `DateFormat(...).format(bmnt.toUtc())` 방어코드 (별도 작업) |
| 여전히 낮인데 야간 | `isDayProvider` fallback이 false | `daylightCycleProvider` null 반환 여부 확인 (loc==null) |
