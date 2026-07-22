# REPORT: 속도계 정지 노이즈 수정 (fix #3)

커밋: b438262  
날짜: 2026-06-10  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

| 항목 | 결과 |
|---|---|
| 속도 계산 블록 위치 | `_onPosition` lines 218-230 (throttle 통과 후) |
| `rawKmh` | `pos.speed * 3.6` — 도플러 GPS 속도, m/s→km/h |
| `clamped` dead zone | `rawKmh < 2.5 \|\| pos.accuracy > 20.0` → 0 |
| 이동평균 | `_speedBuffer` 3샘플 |
| 2차 dead zone | `avg < 2.0` → 0 |
| `Position.speedAccuracy` | `double`, m/s 단위, `required` 필드 (geolocator_platform_interface 4.2.6 확인) |
| 0.0 리턴 기기 | `0.0 > 1.0 = false` → 게이팅 통과 (별도 처리 불필요) |

---

## speedAccuracy 게이팅 구현

### 상수 추가 (`_kBufSize` 바로 아래)

```dart
// 속도 불확실도 임계 (m/s). 초과 시 노이즈로 판단 → 0 처리.
// 0.0 리턴 기기(미지원)는 0.0 > 1.0 = false 라 자연히 통과.
// 폰 실측 후 조정: 정지 떨림 → 낮춤(0.7), 저속 죽음 → 높임(1.5).
static const _kSpeedAccuracyMaxMs = 1.0;
```

### `clamped` 계산 변경

```dart
// 이전
final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0) ? 0.0 : rawKmh;

// 이후
final speedUnreliable = pos.speedAccuracy.isNaN
    || pos.speedAccuracy > _kSpeedAccuracyMaxMs;
final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0 || speedUnreliable)
    ? 0.0 : rawKmh;
```

### 게이팅 로직 전체 (수정 후)

| 단계 | 조건 | 처리 |
|---|---|---|
| ① 속도 유효성 | `pos.speed.isNaN or < 0` | → 0 |
| ② 위치 정확도 | `pos.accuracy > 20.0 m` | → 0 |
| ③ **속도 불확실도** | **`pos.speedAccuracy > 1.0 m/s`** | **→ 0 (신규)** |
| ④ 저속 dead zone | `rawKmh < 2.5 km/h` | → 0 |
| ⑤ 이동평균 | 3샘플 | 버퍼 평균 |
| ⑥ 평균 dead zone | `avg < 2.0` | → 0 |

정지 상태에서 `speedAccuracy`가 1.5~3 m/s로 높게 보고되면 ③에서 즉시 0 처리되어 dead zone ④에 도달하지 않는다.  
저속 실주행(4~5 km/h)에서 GPS가 신뢰도 있는 측정(speedAccuracy ≤ 1.0 m/s)을 보고하면 정상 통과.

### 0.0 리턴 기기 처리

`speedAccuracy == 0.0`은 기기가 속도 불확실도를 제공하지 않는 경우. `0.0 > 1.0 = false`이므로 `speedUnreliable = false` — 기존 dead zone(③④)에만 의존. 별도 분기 불필요.

변경 파일: `nav_screen.dart` 1개, 9+/2− lines.

---

## 검증

```
flutter analyze  →  No issues found! (1.5s)
flutter build apk --debug  →  ✓ Built app-debug.apk (10.4s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| ① | 완전 정지 상태 속도계 | 0 km/h 유지 (이전 3~4 떨림 사라짐) |
| ② | 저속 실주행 (걷기~서행 4~5 km/h) | 속도 정상 표시 (0으로 안 죽음) |
| ③ | 정상 주행 속도 | 정확한 표시 유지 |
| ④ 조정 | 정지인데 여전히 떨리면 | `_kSpeedAccuracyMaxMs` → 0.7 로 낮춤 (별도 커밋) |
| ④ 조정 | 저속(4~5 km/h)이 0으로 죽으면 | `_kSpeedAccuracyMaxMs` → 1.5 로 높임 (별도 커밋) |
| ⑤ | 기기가 speedAccuracy=0.0 리턴 | ①②③ 결과 이전과 동일 (게이팅 미작동, 기존 dead zone에 의존) |
