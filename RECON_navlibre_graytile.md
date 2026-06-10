# RECON: nav_screen 회색 지도 원인 격리

날짜: 2026-06-09  
브랜치: feat/maplibre-migration  
커밋 기준: afa8b76 (커밋 ① 직후)

---

## 1. styleString 비교

```
main_map_screen.dart:765  styleString: 'assets/images/osm_liberty_yurunavi.json'
nav_screen.dart:564       styleString: 'assets/images/osm_liberty_yurunavi.json'
```

**결론: 완전 동일.** 스타일 경로 오타 아님.

---

## 2. onStyleLoadedCallback 연결

**nav_screen.dart**
```dart
onStyleLoadedCallback: _onStyleLoaded,   // line 573
// _onStyleLoaded:
void _onStyleLoaded() {
    setState(() => _styleLoaded = true);
}
```

**main_map_screen.dart**
```dart
onStyleLoadedCallback: () async {        // line 776
    _styleLoaded = true;
    await _initRouteLayer();
    ...
},
```

`OnStyleLoadedCallback = void Function()` (controller.dart:51) — 양쪽 모두 시그니처 일치.  
nav_screen의 콜백 연결 자체는 정상. 스타일 로드 문제 아님.

---

## 3. 위젯 레이아웃 구조 — ✅ 원인 확정

### pubspec.yaml asset 등록
```yaml
assets:
  - assets/images/   # wildcard 등록 (line 45)
```
wildcard로 포함되므로 asset 미등록 아님.

### 레이아웃 구조 비교

**main_map_screen** (`Scaffold.body: Stack`):
```
Stack
  └── ml.MapLibreMap(styleString: ...)  ← 화면 전체, 타일 정상 표시
  └── Positioned(...)                   ← UI 레이어들 (투명 배경)
```

**nav_screen** (`Scaffold.body: Stack`, 커밋 ① 이후):
```
Stack
  └── ml.MapLibreMap(styleString: ...)  ← 화면 전체 (타일 정상 로드 중)
  └── IgnorePointer(                    ← ★ 문제 레이어
        child: FlutterMap(
          options: MapOptions(           ← backgroundColor 미지정
            ...
          ),
          children: [PolylineLayer, MarkerLayer],
        ),
      )
  └── Positioned(...)                   ← UI 레이어들
```

### 원인: FlutterMap.backgroundColor 기본값 = `Color(0xFFE0E0E0)`

`flutter_map-8.2.2/lib/src/map/options/options.dart:153`:
```dart
this.backgroundColor = const Color(0xFFE0E0E0),
```

`flutter_map-8.2.2/lib/src/map/widget.dart:88`:
```dart
child: ColoredBox(color: widget.options.backgroundColor),
```

`FlutterMap`은 내부적으로 `ColoredBox(Color(0xFFE0E0E0))`를 그린다. `IgnorePointer`는 **포인터 이벤트만 차단**하고 렌더링은 그대로 통과시킨다. Stack에서 두 번째 자식인 `IgnorePointer(FlutterMap)` 이 화면 전체를 **불투명 회색(`#E0E0E0`)으로 덮어** 아래의 `ml.MapLibreMap`을 완전히 가린다.

---

## 4. 가장 유력한 원인 — 단 1개

> **`IgnorePointer(FlutterMap)` 오버레이의 기본 배경색 `Color(0xFFE0E0E0)`이 `ml.MapLibreMap` 전체를 덮는다.**

MapLibreMap 자체는 정상 동작하고 있을 가능성이 높다 (styleString 동일, 콜백 연결 정상, asset 등록 정상). 회색은 MapLibre의 "스타일 로딩 중" 색이 아니라 FlutterMap의 `ColoredBox` 색(`#E0E0E0`)이다.

---

## 수정 방향 (RECON이므로 코드 수정 금지 — 다음 실행 턴에서 적용)

`MapOptions`에 `backgroundColor: Colors.transparent`를 추가하면 MapLibreMap이 그대로 보인다:

```dart
IgnorePointer(
  child: FlutterMap(
    options: MapOptions(
      backgroundColor: Colors.transparent,  // ← 이 한 줄
      initialCenter: _currentPos ?? _kInitialMapView,
      initialZoom: _navZoom,
      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.none,
      ),
    ),
    children: [PolylineLayer(...), MarkerLayer(...)],
  ),
),
```

단, 투명 배경이면 PolylineLayer/MarkerLayer 렌더링(스크린 좌표 프로젝션)이 MapLibreMap 카메라와 동기화되지 않으므로 마커/경로 위치가 어긋난다. 이는 ②③ 이전까지 허용되는 임시 상태.
