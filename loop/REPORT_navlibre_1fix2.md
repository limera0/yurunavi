# REPORT: nav_screen 카메라 추적 복구 (1/4 hotfix2)

커밋: 7018e5b  
날짜: 2026-06-10  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

| 항목 | 결과 |
|---|---|
| `_programmaticCamera` 사용처 | L52(필드), L216/218(heading), L518/520(recenter), L574-576(onCameraMove) — 전부 제거 대상 확인 |
| `MapLibreMap.gestureRecognizers` 파라미터 | 존재 (`maplibre_map.dart:21, 279`) — 그러나 네이티브 뷰에 전달할 제스처 등록용, 수동모드 감지에 부적합 |
| `getLastKnownPosition` 레퍼런스 | `main_map_screen.dart:162-173` 패턴 확인 |
| `_mapCtrl` 잔존 참조 | 없음 |

---

## 구현 내용 (B안)

### 1. `_programmaticCamera` 완전 제거
- 필드 삭제 (L52)
- heading rotation에서 `_programmaticCamera = true` + `bf?.then(...)` 제거, `animateCamera` 직접 호출만 유지
- `_recenter`에서 동일하게 제거

### 2. `onCameraMove` 콜백 제거 → `Listener` 교체

**제거**:
```dart
onCameraMove: (_) {
    if (!_programmaticCamera) _onMapGesture();
},
```

**추가**:
```dart
Listener(
  behavior: HitTestBehavior.translucent, // MapLibre 네이티브 패닝/줌 제스처 보존
  onPointerDown: (_) => _onMapGesture(),
  child: ml.MapLibreMap(...),
),
```

**제스처 경합 처리**: `Listener`는 제스처 아레나에 참여하지 않는 raw pointer 수신자. `HitTestBehavior.translucent`로 MapLibre 네이티브 뷰가 모든 제스처를 그대로 수신. 패닝/핀치줌 정상 동작 보장.

### 3. `getLastKnownPosition` 초기 스냅

```dart
// _startLocation() 앞부분에 추가
try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && mounted && _currentPos == null) {
        final loc = LatLng(last.latitude, last.longitude);
        setState(() => _currentPos = loc);
        _mlCtrl?.animateCamera(
            ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom),
        );
    }
} catch (_) {}
```

주의: `_mlCtrl`이 null이면 스냅 무시 (스타일 로드 전 호출 가능). 이후 GPS 스트림 첫 이벤트에서 `_recenter` 재호출.

---

## 검증

```
flutter analyze  →  No issues found! (1.5s)
flutter build apk --debug  →  ✓ Built app-debug.apk  (22.0s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| ① | 내비 시작 직후 카메라 | 서울 아닌 실제 위치 (getLastKnownPosition → 캐시 위치로 즉시 스냅) |
| ② | 주행 시 카메라 | GPS 따라 계속 이동 (수동모드 아닌 한) |
| ③ | 손으로 드래그 | 수동모드 진입 ("10초 후 현위치 복귀" 배너) → 10초 후 자동 복귀 |
| ④ | 재중심 버튼 탭 | 즉시 현위치 스냅 + GPS 추적 재개 (이전처럼 즉시 풀리지 않아야 함) |
| ⑤ | 지도 핀치줌/패닝 | 정상 동작 (Listener translucent → 네이티브 제스처 보존) |
| ⑥ | 주행 시 지도 회전 | 진행방향으로 bearing 회전 확인. 반대면 보고 (heading 부호 검토 필요) |
