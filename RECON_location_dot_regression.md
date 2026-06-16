# RECON: 현위치 초록점 소실 회귀
작성일: 2026-06-14 | 브랜치: feat/map-language

---

## A. 현위치 마커 렌더링 방식

- **타입**: MapLibre 서클 어노테이션 (`ml.Circle`)
- **Dart 참조**: `main_map_screen.dart:92` — `ml.Circle? _locMarker;`
- **색상 상수**: `:95` — `static const String _kLocColor = '#00C853';`
- **생성 메서드**: `_ensureLocationMarker()` (`:296-313`)
  - `c.addCircle(CircleOptions(circleRadius:8, circleColor:_kLocColor, ...))` 로 생성
  - `_locMarker == null` 이면 `addCircle` → 새 Circle 반환 후 `_locMarker`에 저장
  - `_locMarker != null` 이면 `c.updateCircle(_locMarker!, ...)` 로 위치 갱신만 수행
- **호출 지점**:
  - `onStyleLoadedCallback` 맨 끝 (`:818`)
  - GPS 스트림 최초 픽스 시 (`:189`)
  - GPS 스트림 갱신마다 (`:209`)

어노테이션은 Flutter 위젯이나 Overlay가 아닌 **네이티브 CircleManager** 가 관리하며,
스타일이 교체되면 CircleManager는 네이티브 레벨에서 완전히 파괴·재생성된다.

---

## B. onStyleLoadedCallback 발화 타이밍

`onStyleLoadedCallback`은 두 경우 모두 발화한다.

| 트리거 | `onMapCreated` 재호출 | `onStyleLoadedCallback` 재호출 |
|---|---|---|
| 최초 지도 생성 | ✅ (1회만) | ✅ |
| `setStyle()` (스타일 재주입) | ❌ | ✅ |

언어 변경 시 흐름:
```
ref.listen fires
  → setState(() => _styleJson = applyMapLanguageToStyle(...))
  → Flutter가 MapLibreMap.didUpdateWidget 호출
  → 네이티브 mapLibreMap.setStyle(newJson) 호출
  → 네이티브 CircleManager / SymbolManager 파괴 + 재생성 (어노테이션 전부 소멸)
  → onStyleLoadedCallback 발화
```

`onMapCreated` 는 재호출되지 않으므로 `_mlCtrl`(컨트롤러 참조)는 유지된다.  
그러나 네이티브 매니저 내부 상태(모든 Circle/Symbol)는 **빈 상태로 초기화**된다.

---

## C. C6 커밋이 변경한 내용 (e3e43ec)

C6 이전: 디버그 버튼 → `_applyMapLanguage()` → `setState()` (수동 토글)  
C6 이후: `ref.listen<AsyncValue<MapLanguage>>` → `setState(() => _styleJson = ...)` (자동 반응)

C6가 추가한 `ref.listen` 코드:
```dart
// main_map_screen.dart (build 내부)
ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
  final raw = _rawStyle;
  if (raw == null) return;
  final lang = next.value ?? MapLanguage.korean;
  if (mounted) setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
});
```

스파이크(Plan α) 당시에도 `_applyMapLanguage()`가 동일하게 `setState`를 호출해  
스타일 재주입이 발생했으므로 회귀는 C6 이전 스파이크 단계부터 잠재해 있었다.  
(스파이크에서는 현위치 마커를 직접 테스트하지 않아 발견되지 않음)

---

## D. 근본 원인 (Root Cause)

**파일**: `lib/features/map/presentation/main_map_screen.dart`  
**메서드**: `_ensureLocationMarker()` `:296-313`  
**문제 코드**:

```dart
Future<void> _ensureLocationMarker() async {
  final c = _mlCtrl;
  if (c == null || !_styleLoaded) return;
  final p = _origin ?? _lastKnown;
  if (p == null) return;
  final geo = _toMl(p);
  if (_locMarker == null) {
    _locMarker = await c.addCircle(...);   // 신규 생성
  } else {
    await c.updateCircle(_locMarker!, ...); // ← 문제
  }
}
```

**시나리오**:
1. 최초 스타일 로드 → `onStyleLoadedCallback` → `_ensureLocationMarker()` → `_locMarker == null` → `addCircle()` → `_locMarker` 저장됨
2. 언어 변경 → 스타일 재주입 → 네이티브 CircleManager 파괴 → 초록점 소멸  
   (`_locMarker` Dart 변수는 여전히 비-null 이지만 이미 소멸된 Circle 의 dead reference)
3. `onStyleLoadedCallback` 재발화 → `_ensureLocationMarker()` → `_locMarker != null` 분기 진입  
   → `c.updateCircle(_locMarker!, ...)` 호출  
   → 네이티브 매니저에 해당 ID가 없음 → 업데이트 무시/silent-fail  
4. 결과: **초록점이 재생성되지 않고 화면에서 사라진 채 유지**

같은 이유로 `_destMarker`, `_waypointMarkers`도 스타일 재주입 후 stale 상태가 된다  
(목적지 핀, 경유지 핀도 소멸됨 — 현재는 확인되지 않았으나 동일 패턴).

---

## 수정 후보

### 후보 1 (권장): `onStyleLoadedCallback` 진입 시 모든 마커 레퍼런스 초기화

```dart
onStyleLoadedCallback: () async {
  _styleLoaded = true;
  // 스타일 재주입 시 네이티브 매니저가 초기화되므로 Dart 레퍼런스도 초기화
  _locMarker = null;
  _destMarker = null;
  _waypointMarkers = [];

  await _initRouteLayer();
  // ... 기존 나머지 코드 ...
  await _ensureLocationMarker();
}
```

- 언어 변경, 향후 다른 스타일 재주입 원인 모두 처리
- 단일 책임 위치 (콜백 안에서 완결)
- `_ensureLocationMarker()`의 `if (_locMarker == null)` 경로가 정상 실행됨

### 후보 2: `ref.listen` 콜백에서 마커 null 처리

```dart
ref.listen<AsyncValue<MapLanguage>>(mapLanguageProvider, (_, next) {
  final raw = _rawStyle;
  if (raw == null) return;
  final lang = next.value ?? MapLanguage.korean;
  if (mounted) {
    _locMarker = null;       // stale 레퍼런스 해제
    _destMarker = null;
    _waypointMarkers = [];
    setState(() => _styleJson = applyMapLanguageToStyle(raw, lang));
  }
});
```

- 언어 변경 트리거에만 작동하는 좁은 범위 수정
- 다른 스타일 재주입 경로를 커버하지 못함

**후보 1을 권장**: `onStyleLoadedCallback`은 스타일 교체의 최종 단계이므로  
어떤 경로로 스타일이 바뀌더라도 항상 올바른 초기화가 수행된다.
