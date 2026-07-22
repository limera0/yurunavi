# REPORT: nav_screen 카메라 trailing 수정 (fix #2)

커밋: ee12245  
날짜: 2026-06-10  
브랜치: feat/maplibre-migration

---

## 0단계 사전검증

| 항목 | 결과 |
|---|---|
| `_recenter` 호출처 | Line 199 (GPS), Line 597 (10초 타이머), Line 844 (버튼) |
| `moveCamera` 시그니처 | `Future<bool?> moveCamera(CameraUpdate cameraUpdate)` — `animateCamera`와 동일 인자, 대체 가능 |
| heading bearing 호출 위치 | Line 231 — throttle 블록 **내부** (최대 2Hz). 이번 범위 제외 (아래 보고) |

---

## move/animate 분리 방식

`_recenter`에 `{bool animate = false}` 네임드 파라미터 추가:

```dart
void _recenter(LatLng loc, {bool animate = false}) {
  if (!_styleLoaded) return;
  final target = _zoomForSpeed(_speedKmh);
  final diff = target - _navZoom;
  _navZoom += diff.clamp(-0.3, 0.3);
  final update = ml.CameraUpdate.newLatLngZoom(_toMl(loc), _navZoom);
  if (animate) {
    _mlCtrl?.animateCamera(update);
  } else {
    _mlCtrl?.moveCamera(update);
  }
}
```

| 호출처 | animate 값 | 카메라 동작 |
|---|---|---|
| `_onPosition` (GPS 추적, line 199) | `false` (기본값) | `moveCamera` — 즉각 이동, 적층 없음 |
| 10초 타이머 자동 복귀 (line 597) | `true` | `animateCamera` — 수동모드 해제 부드러운 복귀 |
| 재중심 버튼 onTap (line 844) | `true` | `animateCamera` — 부드러운 스냅 |

변경 파일: `nav_screen.dart` 1개, 9+/4− lines.

---

## Heading bearing 현황 보고

```dart
// line 230-231 — throttle 블록 내부 (early return 이후)
if (pos.heading >= 0 && _speedKmh > 2.0 && _styleLoaded) {
    _mlCtrl?.animateCamera(ml.CameraUpdate.bearingTo(pos.heading));
}
```

- throttle 내부에 위치 → 최대 **2Hz**(저속) / **1Hz**(고속)로 제한됨
- `animateCamera(bearingTo)` + 1Hz: 애니 300ms, 간격 1000ms — 적층 없음, trailing 위험 낮음
- 단 위치 `moveCamera`와 bearing `animateCamera`가 동시에 발화되는 경우 경합 가능성 있음
  (속도 > 2 km/h이고 throttle 통과 시 동일 틱에서 둘 다 호출)
- → **현재 범위 제외**. 폰 실측 ④에서 bearing 회전 이상 시 다음 커밋에서 검토.

---

## 검증

```
flutter analyze  →  No issues found! (1.5s)
flutter build apk --debug  →  ✓ Built app-debug.apk (10.9s)
```

---

## 폰 실측 가이드 (마스터 직접)

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| ① | 주행 시 카메라 추적 | 내 위치에 즉각 붙어서 따라옴 (trailing 사라짐) |
| ② | 추적 부드러움 | distanceFilter:0 + 2Hz 수신이라 끊기 없이 부드러워야 함. 끊기면 보고 |
| ③ | 재중심 버튼 탭 | 부드러운 스냅 애니메이션 유지 (animateCamera 경로) |
| ④ | 주행 시 heading 회전 | bearing 안 건드렸으니 이전과 동일. 이상 시 보고 |
| (⑤) | trailing 잔존 시 | bearing animateCamera 경합 의심 → 다음 커밋에서 moveCamera 전환 |
