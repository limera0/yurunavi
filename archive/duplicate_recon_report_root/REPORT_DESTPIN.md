# REPORT_DESTPIN — 목적지 핀 자작 PNG 교체 보고

## 0단계 게이트 결과

| 항목 | 결과 |
|------|------|
| `pointer_red.png` 실존 | **확인** — `assets/images/pointer_red.png` 4341 bytes, **96×96 RGBA PNG** |
| `pointer_yellow.png` 실존 | 확인 (4431 bytes, 폴더에만 보관, 이번 스코프 외) |
| pubspec `assets/images/` 등록 | **확인** — `pubspec.yaml:45` `- assets/images/` (폴더 전체 등록, 개별 파일 불필요) |
| `addImage` 시그니처 | **확정** — `Future<void> addImage(String name, Uint8List bytes, [bool sdf = false])` |
| `rootBundle` import | **필요** — 기존 `show SystemNavigator`에 `rootBundle` 추가 |
| addImage 등록 위치 | **onStyleLoadedCallback**, `_initRouteLayer()` 이후·`_ensureLocationMarker()` 직전 |
| 스타일 재로드 시나리오 | **없음** — `setStyleString`/`setStyle` 호출 없음 → 1회 등록으로 충분 |
| 컨트롤러 변수명 | `_mlCtrl` (`onMapCreated` 이후 콜백 발화 → non-null 보장) |

→ 전원 PASS.

---

## 변경 diff

### ① import (line 5)

**Before:**
```dart
import 'package:flutter/services.dart' show SystemNavigator;
```

**After:**
```dart
import 'package:flutter/services.dart' show SystemNavigator, rootBundle;
```

### ② 상수 (line 91-92)

**Before:**
```dart
static const String _kDestIcon = 'marker';
static const double _kDestIconSize = 1.6;
```

**After:**
```dart
static const String _kDestIcon = 'pointer_red';
static const double _kDestIconSize = 0.5; // 96px PNG 기준, 폰 실측으로 조정
```

### ③ onStyleLoadedCallback 내 addImage 등록 (line 753-754)

**Before:**
```dart
// B1: 현위치 마커 — 경로 레이어 위에 그려지도록 마지막에 추가
await _ensureLocationMarker();
```

**After:**
```dart
// B2: 목적지 핀 이미지 1회 등록 (addSymbol 호출보다 먼저)
final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
// B1: 현위치 마커 — 경로 레이어 위에 그려지도록 마지막에 추가
await _ensureLocationMarker();
```

### ④ `_ensureDestMarker` (변경 없음 — `_kDestIcon` 상수 값만 교체로 자동 반영)

```dart
_destMarker = await c.addSymbol(ml.SymbolOptions(
  geometry: geo,
  iconImage: _kDestIcon,      // 'pointer_red' (변경됨)
  iconSize: _kDestIconSize,   // 0.5 (변경됨)
  iconAnchor: 'bottom',
));
```

---

## 선택한 `_kDestIconSize` 초기값 근거

- PNG 원본: 96×96 px
- `iconSize = 0.5` → 약 48px 표시 (XHDPI 2x 기기에서 약 24dp)
- MapLibre sprite 기본 아이콘(21px, iconSize=1.0)보다 큰 편이므로 폰에서 잘 보일 예상
- **폰 실측 후 조정 권장**: 너무 크면 `0.3`, 작으면 `0.7` 또는 `1.0`

---

## analyze · build 결과
- `flutter analyze`: **No issues found!**
- `flutter build apk --debug`: **✓ Built app-debug.apk** (Gradle 10.3s)

---

## 폰 실측 체크리스트

- [ ] 탭 시 빨강 물방울 핀(자작 PNG) 표시 (osm-liberty 회색핀 아님)
- [ ] 핀 끝이 탭한 좌표를 정확히 가리킴 (`iconAnchor: 'bottom'` 동작)
- [ ] 핀 크기 적절 — 부적절 시 `_kDestIconSize` 권장값:
  - 너무 큼 → `0.3` (32px 표시)
  - 적당 → `0.5` (48px 표시, 현재값)
  - 너무 작음 → `0.7` (67px) 또는 `1.0` (96px)
- [ ] 핀 배경 투명 (검은 사각형 없음 — PNG가 RGBA이므로 정상이면 투명 처리됨)
- [ ] 현위치 초록 원 유지 (회귀 없음)
- [ ] 목적지 해제 시 핀 사라짐 (`removeSymbol` 동작)
- [ ] 경로선 위에 핀 표시 (z-order 정상)

## 안 보이면 진단

| 증상 | 원인 | 확인 방법 |
|------|------|----------|
| 탭해도 핀 없음 | addImage 등록 실패 | `adb logcat -d \| grep -iE "image\|symbol\|pointer"` |
| 검은 사각형 | RGBA 투명처리 실패 | `addImage(name, bytes, false)` — sdf=false 확인 (현재 기본값) |
| 스타일 재시작 후 핀 없음 | addImage는 1회 — 스타일 재로드 시 재등록 필요 | 현재 재로드 시나리오 없으므로 무관 |
| 핀이 경로선에 가려짐 | symbolManager z-order 문제 | `logcat` 에서 layer 순서 확인 |

```
adb logcat -d | grep -iE "image|symbol|sprite|pointer"
```
