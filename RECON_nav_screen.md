# RECON: nav_screen.dart 현재 상태

조사일: 2026-06-09  
대상: `lib/features/navigation/presentation/nav_screen.dart` (926 lines)

---

## 1. 지도 위젯: 구형 FlutterMap

**결론: 구형 `flutter_map` 사용. MapLibre 미사용.**

```
line 12:  import 'package:flutter_map/flutter_map.dart';
line 491: FlutterMap(mapController: _mapCtrl, ...)
line 509: TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', ...)
```

- `maplibre_gl: ^0.26.1`은 pubspec.yaml(line 33)에 선언되어 있으나, nav_screen.dart에서는 import하지 않음
- 타일 소스도 로컬 tileserver-gl(192.168.0.57:8080)이 아닌 OSM 공개 타일 → CLAUDE.md의 인프라와 불일치
- MapController = `flutter_map`의 `MapController` (MapLibre의 MaplibreMapController가 아님)

---

## 2. 경로/턴 데이터: 실제 Valhalla 연동 (더미 폴백 있음)

**결론: 실제 Valhalla 연동. 단, maneuvers 미전달 시 더미 3개로 폴백.**

```
line 124: _steps = widget.maneuvers.isNotEmpty
line 125:     ? widget.maneuvers.map(_TurnStep.fromManeuver).toList()
line 126:     : const [
line 127:         _TurnStep(Icons.play_arrow_rounded, '경로 안내 시작', '', 0),
line 128:         _TurnStep(Icons.straight_rounded,   '직진',         '', 0),
line 129:         _TurnStep(Icons.flag_rounded,        '목적지 도착',  '', 0),
line 130:     ];
```

- `ManeuverStep`은 routing_service.dart에서 `https://valhalla.westinx.com` 실제 호출 후 파싱됨
- `_TurnStep.fromManeuver()` (line 873): Valhalla type int → icon/label 완전 매핑 (type 1~28)
- `_formatDist()` (line 920): km < 1 → "XXXm", 이상 → "X.Xkm" 포맷

---

## 3. 구현 현황

### ✅ 구현 완료

| 항목 | 위치 | 내용 |
|------|------|------|
| maneuvers 파싱/표시 | line 873, 882~924 | Valhalla type 1-28 전체 icon+label 매핑, 상단 카드 UI 표시 |
| GPS 위치 추적 | line 158-214 | `Geolocator.getPositionStream()`, 적응 갱신(≤10km/h→2Hz, 나머지→1Hz), 이동평균 3샘플 노이즈 제거 |
| 재탐색/이탈 감지 | line 264-319 | `_checkOffRoute()`: 경로 이탈 20m 판정, 3초 디바운스 후 `RoutingService.fetchRoutes()` 재호출 |
| wakelock | line 120, 154 | `WakelockPlus.enable()` init / `WakelockPlus.disable()` dispose |
| 도착 이벤트 | line 342-450 | 30m 반경 도달 시 Overpass API POI 조회 후 AlertDialog |
| 줌 제어 (속도 연동) | line 453-464 | 0→18, 20→16, 60+→14 선형 보간, GPS 이벤트당 ±0.3 부드러운 수렴 |
| 수동모드 복귀 | line 467-475 | 지도 조작 감지 시 10초 타이머 후 자동 재중심 |
| TTS 음성 안내 | line 322-340 | ko-KR, 400m 예비 발화 + 50m 자동 진행, 중복 방지 |
| heading 회전 | line 205-207 | `_mapCtrl.rotate(-pos.heading)` — 진행 방향 보정 |

### ❌ 미완성 / 하드코딩

| 항목 | 위치 | 내용 |
|------|------|------|
| ETA 도착시각 | line 750 | `'14:32 도착'` 하드코딩 — 실제 계산 없음 |
| 남은 시간 | line 759 | `'38분'` 하드코딩 |
| 뒤로가기 인터셉트 | 없음 | WillPopScope/PopScope 미구현 — 안드로이드 Back 버튼으로 내비 도중 이탈 가능 |
| 지도 타일 | line 509-515 | OSM 공개 타일 사용 (로컬 tileserver-gl 미연동) |
| MapLibre 미이관 | — | pubspec에 maplibre_gl 있으나 nav_screen은 여전히 flutter_map 사용 중 |

---

## 4. 의존성 확인 (pubspec.yaml)

```yaml
flutter_map: ^8.2.2      # line 16  → 실제 사용 중 (nav_screen)
geolocator: ^14.0.2      # line 20  → 실제 사용 중
wakelock_plus: ^1.2.10   # line 31  → 실제 사용 중
maplibre_gl: ^0.26.1     # line 33  → 선언되어 있으나 nav_screen에서 미사용
```

---

## 요약

nav_screen은 **FlutterMap(구형) 기반**으로 동작 중. maplibre_gl로의 이관이 pubspec에서 시작됐으나 nav_screen 자체는 미이관 상태.  
GPS, 재탐색, 이탈감지, wakelock, TTS, 도착 다이얼로그 등 핵심 로직은 **실제 구현 완료**.  
**ETA 계산(하드코딩)**, **뒤로가기 인터셉트**, **MapLibre 이관** 이 세 가지가 주요 미완성 항목.
