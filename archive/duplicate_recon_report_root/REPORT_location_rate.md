# REPORT: High-Rate Location Updates

날짜: 2026-06-10  
브랜치: feat/maplibre-migration  
커밋: 5a877ea

## 변경 요약

`LocationSettings` (base) → `AndroidSettings` 교체 + `intervalDuration` 333ms 추가.

### 변경 전 (`nav_screen.dart:188-193`)
```dart
locationSettings: const LocationSettings(
  accuracy: LocationAccuracy.bestForNavigation,
  distanceFilter: 0,
)
```

### 변경 후
```dart
locationSettings: AndroidSettings(
  accuracy: LocationAccuracy.bestForNavigation,
  intervalDuration: const Duration(milliseconds: 333), // ~3Hz 목표
  distanceFilter: 0,
)
```

## 0단계 확인 사항

- `LocationSettings` (base class) 사용 중 → HALT 조건 트리거
- `intervalDuration`은 `AndroidSettings`에만 존재 (geolocator_android 5.0.2)
- `AndroidSettings`는 `package:geolocator/geolocator.dart`에서 re-export → 추가 import 불필요
- 2단계 지시에 AndroidSettings 교체 명시 → 의도된 교체로 진행

## 빌드
```
flutter build apk --debug  → ✓ build/app/outputs/flutter-apk/app-debug.apk
```

## 폰 실측 결과 (adb logcat | grep SPD)

> TODO: adb install 후 아래 슬롯에 실측 로그 붙일 것

### 저속 보행 중 연속 SPD 로그 (타임스탬프 간격 측정)
```
<10줄 이상 연속 로그 + 타임스탬프>
```
기대: 333ms~500ms 간격 (3Hz 목표)

### 정지 구간
```
<SPD 로그 발췌>
```
기대: r > 0 (위치앵커 동작), parked=true → mov=false → 0.0km/h

## 검증 체크리스트

- [ ] ★저속 보행 수신 간격 (ms): 실측값 = ___ms
- [ ] 정지 시 r이 0이 아닌 값으로 표시됨 (위치앵커 정상)
- [ ] req#1: 1분 정지 → 0 유지
- [ ] req#2: 출발/정지 반응 빨라짐
- [ ] ★bearing: 주행 시 지도 회전 정상 (b985795 증상 재발 없음)
- [ ] ★카메라 추적/재중심 정상
- [ ] ★재탐색·TTS 이전과 동일 (회귀 없음)

## 판단 기준
- 수신 간격 333~700ms 근처 + 회귀 없음 → PASS
- 수신 간격 여전히 ~1000ms → 2단계 보간/IMU 보조 검토
- 회귀 발생 → 이 커밋 revert 후 보고
