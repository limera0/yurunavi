# REPORT: 현위치 초록점 소실 회귀 수정
작성일: 2026-06-14 | 브랜치: feat/map-language

---

## [0] 게이트 결과

### 0-1. onStyleLoadedCallback 실제 위치 및 본문

`lib/features/map/presentation/main_map_screen.dart:804-823`

```dart
onStyleLoadedCallback: () async {
  _styleLoaded = true;                                  // :805
  // [fix 삽입 위치 — 상세 0-2 참조]
  await _initRouteLayer();                              // :811
  final poly = ref.read(mapInteractionProvider).routePolyline;
  if (poly.isNotEmpty) _updateRouteLayer(poly);         // :815
  final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
  await _mlCtrl!.addImage('pointer_red', ...);          // :818
  final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
  await _mlCtrl!.addImage(_kWpIcon, ...);               // :820
  await _mlCtrl!.setSymbolIconAllowOverlap(true);       // :821
  await _ensureLocationMarker();                        // :823 ← 마커 생성 (최후)
},
```

### 0-2. 마커 선언부 및 타입

| 변수 | 파일:라인 | 타입 | 빈 리터럴 |
|---|---|---|---|
| `_locMarker` | `:92` | `ml.Circle?` | `null` |
| `_destMarker` | `:93` | `ml.Symbol?` | `null` |
| `_waypointMarkers` | `:94` | `List<ml.Symbol>` | `<ml.Symbol>[]` |

`_waypointMarkers`는 `List<ml.Symbol>` (Circle 아님). 타입 불일치 없음.

### 0-3. _ensureLocationMarker 재생성 경로 확인

`:302` `if (_locMarker == null)` → `:303` `addCircle(...)` 실행 후 `_locMarker`에 저장.
null 초기화 후 이 분기를 정상으로 타는 것 확인.

---

## 수정 내용

**파일**: `lib/features/map/presentation/main_map_screen.dart`  
**변경 위치**: `onStyleLoadedCallback` 진입부, `_styleLoaded = true` 다음  
**삽입 코드** (`:806-810`):

```dart
// 스타일 재주입 시 네이티브 어노테이션 매니저가 파괴·재생성되므로
// Dart 레퍼런스를 초기화해 재생성 경로를 타도록 한다.
_locMarker = null;
_destMarker = null;
_waypointMarkers = <ml.Symbol>[];
```

이 세 줄로 스타일 재주입 이후 `_ensureLocationMarker()` 가 `addCircle` 경로를 타게 된다.

---

## 커밋 해시

| # | 해시 | 메시지 |
|---|---|---|
| 체크포인트 | `d495f6f` | checkpoint: before location-dot regression fix |
| 수정 | `7f95dac` | fix(map): re-add location/dest/waypoint markers after style re-injection |

---

## analyze / 빌드 결과

```
flutter analyze → error 0, warning 0
  info 2개: settings_screen.dart Radio.groupValue / Radio.onChanged deprecated
  (기존 info, 이번 수정과 무관)

flutter build apk --debug → ✓ Built build/app/outputs/flutter-apk/app-debug.apk
```

---

## 폰 검증 절차

```powershell
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### ① 앱 첫 실행 (기본 한국어)
- 홈 지도에 **현위치 초록점(반경 8, 흰 테두리)** 표시되는지 확인
- GPS 픽스까지 수 초 소요될 수 있음

### ② English 전환 → 초록점 유지 ★핵심
- ⚙️ 탭 → 설정 → "지도 표기 언어" → **English** 선택 → 뒤로
- 홈 화면 지도 라벨이 로마자로 바뀐 후 **현위치 초록점이 사라지지 않고 그대로 남아있는지** 확인
- 이전: 언어 변경 시 초록점 소멸. 수정 후: 스타일 재로드 완료 후 점 재생성

### ③ 한국어 재전환 → 초록점 유지
- 설정 → 한국어 → 뒤로 → 초록점 확인 (재현)

### ④ 잠재버그 동시 검증 — 목적지/경유지 핀
- English 상태에서 지도 탭(목적지 지정) → **빨간 목적지 핀 표시 확인**
- 언어 전환 후 다시 핀 있는 화면으로 → 핀 재생성 확인
- 경유지 추가된 경우 노란 경유지 핀도 동일 확인

### ⑤ logcat
```powershell
.\adb logcat -d | Select-String -Pattern "MapLibre|Circle|exception"
```
- exception 없어야 통과
- Circle-관련 native error 없어야 통과
