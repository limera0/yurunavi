# REPORT_faststop — 정차 빠른 0 패치

날짜: 2026-06-12  
커밋: 5644e8e  
APK: build/app/outputs/flutter-apk/app-debug.apk

---

## 문제
정차 시 GPS fix가 최대 5초 지연되는 동안 `_moving=true` 상태가 유지되어
`_tickSpeed`가 마지막 측정 속도(11~13 km/h)로 선형 외삽을 계속함.
결과: 멈춰있는데도 속도계가 11~13 km/h 고착.

## 변경 라인 요약

### 추가: `_calcParkState()` 헬퍼 (nav_screen.dart:548~562)
```
({bool parked, double bufRadius, double parkThresh}) _calcParkState()
```
기존 `_onPosition` 내 posBuffer 군집반경 계산 블록을 그대로 추출.  
`_posBuffer.length < 3` → `(parked:false, bufRadius:0.0, parkThresh:6.0)` 조기반환.

### 변경: `_onPosition` parked 판정 (구 306~320 → 신 312)
```dart
// 전 (15줄)
double bufRadius = 0.0;
double parkThresh = 6.0;
final bool parked;
if (_posBuffer.length < 3) { ... } else { ... }

// 후 (1줄)
final (:parked, :bufRadius, :parkThresh) = _calcParkState();
```
로그(`bufRadius`, `parkThresh`, `parked`)는 그대로 유지됨.

### 변경: `_tickSpeed` 빠른 정차 조건 추가 (신 247~250)
```dart
if (sinceFix > 1500 && _calcParkState().parked) {
  if (_speedKmh != 0.0) setState(() => _speedKmh = 0.0);
  return;
}
```
- staleness(8000ms) 체크 **이후**, `!_moving` 체크 **이전**에 삽입.
- `_moving`은 건드리지 않음(히스테리시스 책임은 `_onPosition` 유지).
- 정지 기준: 기존 군집반경 식 그대로 (`bufRadius < parkThresh`).

## 정지 판정 공유 방식
`_calcParkState()`를 두 함수가 각각 호출.  
ticker는 200ms마다 호출하므로 posBuffer(최대 ~60개 샘플) 순회 비용이 생기나,
실측 fix 간격(500ms~1s) 사이에서만 의미 있으므로 실 영향 미미.

## 빌드 결과
- `flutter analyze`: 경고 1건 (`max` unused_shown_name, 기존)
- `flutter build apk --debug`: ✓ 성공

## 사용자 체크리스트
```
[ ] ★정차 시 11~13 고착 없이 1~2초 내 0
[ ] 주행 중 속도 정상(회귀 없음)
[ ] 재출발 시 음수/이상값 없이 0→정상 속도
[ ] bearing/카메라/재탐색 회귀 없음
로그: adb logcat -d | grep "SPD"
```
