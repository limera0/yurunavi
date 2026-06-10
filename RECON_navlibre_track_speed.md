# RECON: nav_screen 카메라 trailing + 속도계 노이즈 원인 격리

날짜: 2026-06-10  
브랜치: feat/maplibre-migration  
커밋 기준: b3a853c (커밋 ②)

---

## 조사 A — 카메라 trailing

### 1. `_onPosition` → `_recenter` 호출 경로

```dart
void _onPosition(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    ...
    if (!_isManualMode) _recenter(loc);   // ← line 199 — throttle 체크 전에 호출!

    // 적응 갱신 throttle (저속 2Hz, 고속 1Hz)
    if (elapsedMs < intervalMs) {
        setState(() => _currentPos = loc);
        return;   // ← 이 early return은 _recenter 이후에 실행
    }
    ...
    // heading animateCamera (speed > 2 km/h)
}
```

**핵심**: `_recenter(loc)` 는 throttle 로직 **이전** (line 199)에서 무조건 호출된다. throttle(2Hz / 1Hz)은 속도 갱신·heading 회전에만 적용되고 **카메라 이동에는 적용되지 않는다.**

### 2. `_recenter` — `animateCamera` 사용 확정

```dart
void _recenter(LatLng loc) {
    if (!_styleLoaded) return;
    ...
    _mlCtrl?.animateCamera(ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom));
    //        ^^^^^^^^^^^^^ 애니메이션 (기본 ~300ms)
}
```

**재중심 버튼도 동일 함수 호출** (line 844): `_recenter(pos)` — 버튼/GPS 추적이 같은 `animateCamera` 경로.

### 3. trailing 발생 메커니즘

`distanceFilter: 0` + `bestForNavigation` 조합은 Android 기기에 따라 1~10 Hz로 GPS 이벤트를 전달한다. 많은 기기에서 실질적으로 2~5 Hz.

MapLibre `animateCamera` 기본 애니메이션 지속 시간 ≈ **300~500 ms**.

| GPS 주기 | 애니 지속 | 결과 |
|---|---|---|
| 1000 ms | 300 ms | 정상 — 애니 완료 후 700ms 여유 |
| 500 ms (2Hz) | 300 ms | 경계 — 이전 애니 완료 전 새 애니 시작 가능 |
| 200 ms (5Hz) | 300 ms | **적층** — 항상 이전 애니가 미완료, trailing 발생 |

재중심 버튼이 "즉각 스냅"처럼 보이는 이유: **단발 호출**이라 애니메이션이 적층되지 않음. GPS 추적은 고빈도 연속 호출이므로 trailing 발생.

### 4. `loc` — 생값(raw) vs 평균값

`_recenter(loc)` 에 넘기는 `loc` = **생값 `LatLng(pos.latitude, pos.longitude)`** (line 197-199).  
이동평균은 속도(`_speedBuffer`)에만 적용되고, 위치 좌표에는 적용되지 않는다.  
→ 위치 자체의 노이즈는 GPS 정확도에 의존 (GPS 정확도가 좋으면 문제 없음).

### 5. main_map_screen 대조

```dart
// main_map_screen: GPS 스트림 listener
_locationSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
        distanceFilter: 10,  // ← 10m 이동 시에만 이벤트 (≪ nav의 0)
    ),
).listen((pos) {
    final isFirstFix = _origin == null;
    setState(() => _origin = loc);
    if (isFirstFix) {
        _mlCtrl?.animateCamera(...);  // 첫 fix에만 animate, 이후 GPS 이벤트는 animateCamera 없음
    }
    _ensureLocationMarker(); // 마커 갱신만
});
```

main_map_screen은 **GPS 이벤트마다 `animateCamera`를 호출하지 않는다.** 첫 fix에만 한 번, 이후는 재중심 버튼(`_recenterMap`)에서만 호출. trailing 발생 구조 자체가 없음.

---

## (A) 원인 확정

> **`_recenter`가 `animateCamera`(~300ms 애니메이션)를 사용하면서, GPS 이벤트마다 무제한 호출된다. `distanceFilter: 0` + `bestForNavigation`의 고빈도 이벤트(2~5 Hz)에서 애니메이션이 연속 적층되어 카메라가 항상 현재 위치를 따라가지 못하고 뒤처진다. 재중심 버튼은 단발 호출이라 완료되고 정상으로 보임.**

**수정 방향 후보**:

**A1 (권장)**: GPS 추적에는 `moveCamera`(즉각 이동), 재중심 버튼에는 `animateCamera`(부드러운 스냅) — 기능별 분리.  
```dart
// _recenter: GPS 추적용
_mlCtrl?.moveCamera(ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom));

// 재중심 버튼 onTap:
_mlCtrl?.animateCamera(ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom));
```

**A2**: `_recenter` 호출을 throttle 블록 안으로 이동 (최대 2Hz로 제한).  
trailing은 줄지만 이벤트 간격만큼의 지연은 남음.

**A3**: `animateCamera`에 `duration` 파라미터 0ms 또는 매우 짧게 — MapLibre API에서 `duration` 지원 여부 확인 필요.

---

## 조사 B — 속도계 노이즈

### 7. 속도 소스

```dart
// line 215-216
final rawKmh = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed * 3.6;
final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0) ? 0.0 : rawKmh;
```

- **소스**: `pos.speed` — Geolocator의 **도플러 GPS 속도** (m/s). 위치 델타 계산 아님.
- `pos.speedAccuracy` **미사용** — 속도 측정 불확실도 무시.
- dead zone: `rawKmh < 2.5` → 0 (clamped 단계)
- 2차 dead zone: `avg < 2.0` → 0 (평균 단계)

### 8. 현재 게이팅 로직

| 단계 | 조건 | 처리 |
|---|---|---|
| ① 속도 유효성 | `pos.speed.isNaN or < 0` | → 0 |
| ② 위치 정확도 | `pos.accuracy > 20.0 m` | → 0 |
| ③ 저속 dead zone | `rawKmh < 2.5` | → 0 |
| ④ 이동평균 | 3샘플 평균 | 버퍼 [clamped, clamped, clamped] |
| ⑤ 평균 dead zone | `avg < 2.0` | → 0 |
| **speed accuracy** | **미체크** | **노이즈 통과** ← 문제 |

### 9. 이동평균 적용 여부

`_speedBuffer` (3샘플 이동평균)는 속도에만 적용. 위치 좌표에는 적용 없음.

### (B) 원인 확정

> **`pos.speedAccuracy` (속도 불확실도, m/s 단위) 를 체크하지 않는다. 정지 상태에서 Android GPS는 종종 `pos.speed ≈ 0.9~1.1 m/s` (~3~4 km/h)를 보고하는데, 이 값이 dead zone 임계값 2.5 km/h를 넘어 그대로 표시된다.**

실제 Android GPS에서 정지 시 `speedAccuracy`는 종종 1.5~3 m/s (5.4~10.8 km/h)로 크다 — "이 속도는 신뢰할 수 없다"는 신호. 이를 무시하므로 노이즈 속도가 통과.

**수정 방향 후보**:

**B1 (권장)**: `pos.speedAccuracy` 체크 추가. `speedAccuracy > 1.0 m/s` (또는 `rawKmh`보다 크면) → 신뢰 불가 → 0 처리.
```dart
final rawKmh = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed * 3.6;
final speedUnreliable = pos.speedAccuracy > 1.0; // m/s 불확실도 임계
final clamped = (rawKmh < 2.5 || pos.accuracy > 20.0 || speedUnreliable)
    ? 0.0 : rawKmh;
```

**B2**: dead zone 임계값 상향. `rawKmh < 5.0` → 0 (현재 2.5 km/h → 5.0 km/h).  
단순하지만 저속 실주행(4~5 km/h 서행) 시에도 0 표시되는 부작용.

**B3**: B1 + 이동평균 샘플 수 증가(3→5). 노이즈 평균화 강화.
