# REPORT: Doppler+Hysteresis Speed Gate

날짜: 2026-06-10  
브랜치: feat/maplibre-migration  
커밋: ced6a26

## 변경 요약

기존 군집반경 단독 판정기(`thresh = max(8.0, 1.5*medAcc)`, `isStationary = radius <= thresh`)를
도플러+히스테리시스 복합 게이트로 교체.

### 새 로직 (`nav_screen.dart:219-256`)

```
d = pos.speed  (m/s, geolocator 실측)

위치 앵커 (parked):
  parkThresh = max(6.0, 1.2 * medAcc)  ← 임계 낮춤(8.0→6.0, 1.5→1.2)
  parked = bufRadius < parkThresh  && _posBuffer.length >= 3

이동 상태(_moving):
  parked      → _moving = false   (위치 앵커 우선)
  d >= 2.0    → _moving = true    (도플러 바닥 1.2m/s 명확 초과)
  d < 1.5     → _moving = false
  1.5~2.0 비주차 → 직전 상태 유지  (히스테리시스)

speedKmh = _moving ? d*3.6 : 0.0
```

## 빌드
```
flutter build apk --debug  → ✓ build/app/outputs/flutter-apk/app-debug.apk
```

## 폰 실측 결과 (adb logcat | grep SPD)

> TODO: adb install 후 아래 슬롯에 실측 로그 붙일 것

### 정지 구간 (1분 이상 주차)
```
<SPD 로그 발췌>
```
기대: parked=true, mov=false, =>0.0km/h  (d=1.2 도플러 노이즈 있어도)

### 출발 직후 (1~2 fix)
```
<SPD 로그 발췌>
```
기대: d>=2.0 → mov=true 빠르게 전환, km/h 올라옴

## 검증 체크리스트

- [ ] req#1: 1분 정지 → 0 유지
- [ ] req#2: 출발 → 1~2 fix 안에 속도 빠릿하게 올라옴
- [ ] bearing: 주행 시 지도 회전 복귀
- [ ] 카메라/재탐색/TTS 회귀 없음

## 회귀 판단 기준
위 체크리스트 중 하나라도 실패 시 → 이 커밋 revert 후 보고.
