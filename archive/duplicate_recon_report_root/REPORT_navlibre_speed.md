# REPORT: 속도 재설계 — 위치 윈도우 기반 + 정지 판정

커밋: b985795  
날짜: 2026-06-10  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

| 항목 | 결과 |
|---|---|
| 현재 LocationSettings | `const LocationSettings(accuracy: bestForNavigation, distanceFilter: 0)` — intervalDuration 없음, Android 5초 기본값 |
| `AndroidSettings` 가용성 | `geolocator-14.0.2/lib/geolocator.dart:10`에서 re-export. 별도 import 불필요 |
| Dart SDK | `^3.11.4` — named record `({LatLng p, DateTime t})` 지원 |
| `_speedKmh` 바인딩 | `_Speedometer(speedKmh: _speedKmh)`, `_zoomForSpeed`, bearing 조건 `> 2.0` |
| `pos.timestamp` | `DateTime`, `required` 필드 (geolocator_platform_interface 4.2.6) |
| `Geolocator.distanceBetween` | `static double(lat1, lon1, lat2, lon2)` — haversine, 미터 |

---

## 윈도우 설계

### 방식 선택 이유

| 방식 | 문제 |
|---|---|
| 인접 2점 델타 (naive) | 3Hz에서 333ms × 5 km/h = 0.46m → 노이즈와 구분 불가, 걷기 오판 |
| 도플러 `pos.speed` | 정지/걷기 구분 불가 (로그 확인), 폐기 |
| **3초 윈도우 시작→끝 변위** | 정지: 진동하더라도 시작≈끝, dispM≈0 → 확실히 0 판정 |

5 km/h × 3초 = 4.2m → `_kStationaryM = 2.0` 임계를 넘어 정상 표시.  
GPS 정지 진동 ~1m 범위 → dispM ≈ 0~1m < 2m → 0 판정.

### 정지 판정 임계 튜닝 가이드

| 증상 | 조정 |
|---|---|
| 정지인데 속도 표시 (노이즈 돌파) | `_kStationaryM` ↑ (예: 3.0) |
| 걷는데 0으로 죽음 | `_kStationaryM` ↓ (예: 1.5) |

---

## 변경 요약

### 필드

| 제거 | 추가 |
|---|---|
| `_kSpeedAccuracyMaxMs = 1.0` | `_posWindow = <({LatLng p, DateTime t})>[]` |
| `DateTime? _lastSpeedAt` | `_kWindowSec = 3` |
| (적응 throttle 로직) | `_kStationaryM = 2.0` |

`_speedBuffer` / `_kBufSize` 유지 (이동평균 잔여 튐 완화).

### GPS 주기

```dart
// 이전
const LocationSettings(accuracy: bestForNavigation, distanceFilter: 0)
// → Android 기본 5000ms

// 이후
AndroidSettings(accuracy: bestForNavigation, distanceFilter: 0,
    intervalDuration: Duration(milliseconds: 333))  // ~3Hz
```

### `_onPosition` 구조

```
[매 이벤트]
  _recenter(moveCamera)
  _posWindow 추가 + 3초 이전 점 제거
  dispM = distanceBetween(윈도우.first, 윈도우.last)
  dispM < 2m → 0 / 그 외 → dispM/dtSec*3.6
  _speedBuffer 3샘플 평균 → _speedKmh
  setState(currentPos, speedKmh)
  bearing animateCamera (>2km/h)
  _checkArrival / _checkOffRoute / _updateStepByDistance
```

적응 throttle(500ms/1000ms) **제거** — 3Hz 매틱 setState 허용.  
`pos.timestamp` 사용으로 수신 지연 오차 제거.  
`avg < 2.0` 2차 dead zone **제거** — 정지 판정이 대체.

변경 파일: `nav_screen.dart` 1개, 31+/29−.

---

## 검증

```
flutter analyze  →  No issues found! (1.4s)
flutter build apk --debug  →  ✓ Built app-debug.apk (10.5s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| ① | 완전 정지 1분 | 0 km/h 유지 (최우선 기준) |
| ② | 정지→걷기 시작 | 1~2초 내 속도 표시 시작 (3Hz + 윈도우 채워지는 시간) |
| ③ | 걷다가 멈춤 | ~3초 내 0으로 감소 (윈도우 폭) |
| ④ | 10 km/h 이하 저속 | 튐 없이 안정적 |
| ⑤ | 카메라 추적/회전 | fix#2 회귀 없음 (moveCamera 유지 확인) |
| ⑥ 튜닝 | 정지인데 0 안 됨 | `_kStationaryM` 3.0으로 상향 (별도 커밋) |
| ⑥ 튜닝 | 걷는데 0으로 죽음 | `_kStationaryM` 1.5로 하향 (별도 커밋) |
