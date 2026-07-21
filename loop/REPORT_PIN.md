# REPORT_PIN — 목적지 마커 물방울핀 교체 보고

## 0단계 게이트 3개 판정

| 항목 | 결과 |
|------|------|
| `updateSymbol(symbol, SymbolOptions(geometry:...))` geometry-only 갱신 가능 | **PASS** — `copyWith(changes)` 방식으로 null 필드 무시, geometry만 전달 시 위치만 갱신 |
| `SymbolOptions`에 `iconImage`/`iconAnchor`/`iconSize`/`geometry` 필드 존재 | **PASS** — 전 필드 확인됨 (symbol.dart:67-92) |
| 스타일에 sprite URL 존재 → `'marker'` 직접 참조 가능 | **PASS** — `assets/images/osm_liberty_yurunavi.json:23` `"sprite": "https://maputnik.github.io/osm-liberty/sprites/osm-liberty"` 확인 |

→ 전원 PASS. 구현 진행.

---

## 변경 전/후 diff

### 필드/상수

**Before:**
```dart
ml.Circle? _destMarker;
static const String _kDestColor = '#E53935';
```

**After:**
```dart
ml.Symbol? _destMarker;
static const String _kDestIcon = 'marker';
static const double _kDestIconSize = 1.6;
```
- `_kDestColor` 제거 (유일한 사용처 `_ensureDestMarker` 내 — 교체 후 미참조)
- `_kLocColor` / `ml.Circle? _locMarker` 유지 (스코프 하드락)

### `_ensureDestMarker`

**Before:**
```dart
Future<void> _ensureDestMarker(LatLng dest) async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;
  final geo = _toMl(dest);
  if (_destMarker == null) {
    _destMarker = await c.addCircle(ml.CircleOptions(
      geometry: geo,
      circleRadius: 8,
      circleColor: _kDestColor,
      circleStrokeWidth: 3,
      circleStrokeColor: '#FFFFFF',
    ));
  } else {
    await c.updateCircle(_destMarker!, ml.CircleOptions(geometry: geo));
  }
}
```

**After:**
```dart
Future<void> _ensureDestMarker(LatLng dest) async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;
  final geo = _toMl(dest);
  if (_destMarker == null) {
    _destMarker = await c.addSymbol(ml.SymbolOptions(
      geometry: geo,
      iconImage: _kDestIcon,
      iconSize: _kDestIconSize,
      iconAnchor: 'bottom',
    ));
  } else {
    await c.updateSymbol(_destMarker!, ml.SymbolOptions(geometry: geo));
  }
}
```

### `_removeDestMarker`

**Before:**
```dart
await c.removeCircle(_destMarker!);
```

**After:**
```dart
await c.removeSymbol(_destMarker!);
```

### 호출처 (변경 없음)
- `_applyDestination:495` → `_ensureDestMarker(dest); // unawaited — B2` 유지
- `_clearDestination:603` → `_removeDestMarker(); // unawaited — B2` 유지

---

## 현위치 마커 비변경 확인

| 항목 | 라인 | 상태 |
|------|------|------|
| `ml.Circle? _locMarker` | 88 | 유지 |
| `_kLocColor = '#00C853'` | 90 | 유지 |
| `addCircle(CircleOptions(...))` in `_ensureLocationMarker` | 283 | 유지 |
| `updateCircle(_locMarker!, ...)` | 291 | 유지 |

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.3s)

---

## 폰 실측 체크리스트

- [ ] 지도 탭 시 목적지에 물방울 핀 표시 (원이 아니라 핀 모양)
- [ ] 핀의 뾰족한 끝이 정확히 탭한 좌표를 가리킴 (`iconAnchor: 'bottom'` 동작)
- [ ] 핀 크기가 적절 (현재 `_kDestIconSize = 1.6` — 작으면 2.0, 크면 1.2로 조정)
- [ ] 현위치 초록 원은 그대로 (회귀 없음)
- [ ] 목적지 해제/내비 종료 시 핀 사라짐 (`removeSymbol` 동작)
- [ ] 경로 표시 시 핀이 경로선 위 (z-order — `addCircle` z-order 수정이 symbol에도 적용되는지 확인)

## 만약 핀이 안 보이면

| 증상 | 원인 | 대응 |
|------|------|------|
| 탭해도 아무것도 안 나옴 | sprite 'marker' 키 미존재 | logcat에서 `icon-image` 에러 확인 후, curl로 sprite JSON 키 목록 조회 |
| 핀 모양이 아닌 네모 | iconImage null 처리 | sprite 로드 성공 여부 logcat 확인 |
| 핀이 너무 작음 | `_kDestIconSize` 조정 필요 | `1.6` → `2.0` or `2.4` |
| 핀이 경로선에 가려짐 | symbol도 belowLayerId 영향 / z-order | symbolManager 레이어가 route 레이어 위인지 확인 |

## z-order 참고사항

현재 `_initRouteLayer`에서 `belowLayerId: circleLyr` (circleManager 레이어 아래에 route 삽입) 설정됨.
symbolManager도 circleManager와 동일 레벨 또는 위에 초기화되므로, symbol(핀)이 route 위에 표시될 가능성이 높다.
단, symbolManager가 circleManager보다 낮게 초기화된 경우 route 레이어에 가려질 수 있음 — 폰 실측으로 확인 필요.

## logcat 확인 명령
```
adb logcat -d | grep -iE "symbol|marker|sprite|icon"
```
