# REPORT_WPZ — 목적지핀 최상단 + 겹침 적층 구현

## 0단계 게이트 판정

| 게이트 | 판정 | 근거 |
|--------|------|------|
| (a) `setSymbolIconAllowOverlap(bool)` 시그니처 | PASS | controller.dart:1661 `Future<void> setSymbolIconAllowOverlap(bool enable)` |
| (b) `SymbolOptions.zIndex: int?` 존재 | PASS | symbol.dart:125 `final int? zIndex;` |
| (c) 삽입 지점 3곳 확정 | PASS | allowOverlap→line779下, dest addSymbol→line302, wp addSymbol→line329 |

---

## 변경 diff

파일: `lib/features/map/presentation/main_map_screen.dart` (3줄 추가)

**① onStyleLoadedCallback — allowOverlap 활성화 (line 782)**
```dart
 await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
+await _mlCtrl!.setSymbolIconAllowOverlap(true);
 // B1: 현위치 마커 — 경로 레이어 위에 그려지도록 마지막에 추가
```

**② _ensureDestMarker addSymbol — 목적지 zIndex:10 (line 307)**
```dart
 _destMarker = await c.addSymbol(ml.SymbolOptions(
   geometry: geo,
   iconImage: _kDestIcon,
   iconSize: _kDestIconSize,
   iconAnchor: 'bottom',
+  zIndex: 10,
 ));
```

**③ _syncWaypointMarkers addSymbol — 경유지 zIndex:5 (line 335)**
```dart
 final s = await c.addSymbol(ml.SymbolOptions(
   geometry: _toMl(wp),
   iconImage: _kWpIcon,
   iconSize: _kWpIconSize,
   iconAnchor: 'bottom',
+  zIndex: 5,
 ));
```

손대지 않은 것:
- `updateSymbol(_destMarker!, SymbolOptions(geometry: geo))` — copyWith로 zIndex:10 유지되므로 변경 불필요
- `_locMarker`, `_initRouteLayer`, `_updateRouteLayer`, provider 일체 — 미변경

---

## analyze · build 결과

```
flutter analyze → No issues found! (ran in 2.3s)
flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

---

## 커밋

```
e4255f5 fix(map): 목적지핀 최상단(zIndex10)+겹침 적층(allowOverlap), 경유지 zIndex5
```

---

## 폰 실측 체크리스트

- [ ] 목적지 근처에 경유지 찍어도 목적지 빨강핀 안 사라짐 (둘 다 보임)
- [ ] 목적지 빨강핀이 경유지 노랑핀보다 위에 (겹칠 때 빨강이 앞)
- [ ] 경유지 여러 개 겹쳐도 모두 표시
- [ ] 핀이 경로선 위 z-order 유지(회귀 없음)
- [ ] 목적지 해제 시 전부 사라짐, 현위치 초록원·목적지 빨강핀 정상
