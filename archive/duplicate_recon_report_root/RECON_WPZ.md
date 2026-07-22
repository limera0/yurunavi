# RECON_WPZ (목적지핀 최상단 + 겹침 시 적층)

## 1. collision 끄기 (겹쳐도 안 사라지게)

- **SymbolOptions에 iconAllowOverlap 존재?**
  없음. `SymbolOptions` (platform_interface/lib/src/symbol.dart:93/125/200)에는 `zIndex: int?`만 있음.
  iconAllowOverlap/iconIgnorePlacement는 **레이어 레벨**인 `SymbolLayerProperties`에 있음
  (maplibre_gl-0.26.1/lib/src/layer_properties.dart:261, 271).

- **iconIgnorePlacement 존재?**
  `SymbolLayerProperties`에 있음 (layer_properties.dart:271). `SymbolOptions`에는 없음.

- **SymbolManager 레이어 차원에서 기본값/변경법:**
  `SymbolManager` 생성자 (annotation_manager.dart:313-320):
  ```
  bool iconAllowOverlap = false,   ← 기본 false (충돌 회피 ON)
  bool iconIgnorePlacement = false,
  ```
  `allLayerProperties`에서 `iconAllowOverlap: _iconAllowOverlap` 으로 레이어에 반영 (annotation_manager.dart:395).
  컨트롤러는 `setSymbolIconAllowOverlap(bool)` 공개 메서드 제공 (controller.dart:1661) →
  내부에서 `symbolManager?.setIconAllowOverlap(value)` → `_rebuildLayers()` 호출.

- **결론: 핀이 겹쳐도 둘 다 표시되게 하는 정확한 방법 (실파일 근거):**
  `onStyleLoadedCallback` 안에서 이미지 등록 직후:
  ```dart
  await _mlCtrl!.setSymbolIconAllowOverlap(true);
  ```
  이 한 줄로 SymbolManager 레이어 전체에 `icon-allow-overlap: true`가 적용됨.
  (별도 `iconIgnorePlacement` 설정 불필요 — 아이콘-전용 핀이라 텍스트 충돌 무관)

---

## 2. z-order — 목적지 최상단

- **SymbolOptions.zIndex 존재? (있으면 이걸로 해결):**
  **있음.** `final int? zIndex;` (symbol.dart:125). `toJson`에서 `'zIndex'` 키로 직렬화됨 (symbol.dart:200).
  `SymbolManager.allLayerProperties`에서 `symbolSortKey: [Expressions.get, 'zIndex']`로 연결됨
  (annotation_manager.dart:394).

- **symbolSortKey 동작 규칙 (layer_properties.dart:220-226 주석):**
  - `icon-allow-overlap = false` 시: 낮은 sortKey가 배치 우선순위 높음 (경쟁에서 승리)
  - **`icon-allow-overlap = true` 시: 높은 sortKey가 더 위에 렌더링됨 (시각적 최상단)**

- **추가 순서로만 결정되는가?**
  zIndex 미지정 시 null → 정렬 키 없음 → 추가 순서(GeoJSON feature 순서)로 결정.
  나중에 addSymbol된 심볼이 더 위에 렌더링됨.

- **현재 목적지/경유지 그려지는 순서 (탭 시나리오):**
  1. 지도 탭 → `_applyDestination` (main_map_screen.dart:477) → `_ensureDestMarker(dest)` (line 514) → 목적지 `addSymbol` 먼저
  2. 경유지 추가 → `ref.listen` waypoints 변화 감지 (line 713) → `_syncWaypointMarkers(next.waypoints)` → 경유지 `addSymbol` 나중
  - 결과: **경유지가 목적지보다 나중에 추가되어 시각적으로 위에 렌더링됨 → 목적지 가려짐**

- **목적지를 항상 위로 두는 방법:**
  `iconAllowOverlap=true` 활성화 후 `zIndex`를 명시적으로 지정:
  - 목적지: `zIndex: 10`
  - 경유지: `zIndex: 5` (또는 미지정)
  → `icon-allow-overlap=true`이면 높은 zIndex가 시각적 최상단에 렌더링됨.

---

## 3. 권장 구현 (실파일 근거 + 최소 변경)

- **collision: 목적지·경유지 둘 다 iconAllowOverlap=true 주면 적층되는가:**
  `iconAllowOverlap`은 레이어 단위 (SymbolManager 하나 = 레이어 하나).
  목적지/경유지 모두 같은 SymbolManager를 공유하므로
  `setSymbolIconAllowOverlap(true)` 한 번으로 **양쪽 모두** 적층 표시됨.

- **z: 어떻게 목적지를 최상단 고정:**
  목적지 `SymbolOptions`에 `zIndex: 10`, 경유지 `SymbolOptions`에 `zIndex: 5`.
  (allow-overlap=true 하에서 높은 zIndex = 위에 렌더링)

- **변경 범위 (메서드/라인):**

  **변경 1** — `onStyleLoadedCallback` (main_map_screen.dart ~line 790, 이미지 등록 직후):
  ```dart
  await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
  await _mlCtrl!.setSymbolIconAllowOverlap(true);  // ← 추가
  ```

  **변경 2** — `_ensureDestMarker` (main_map_screen.dart:302-308):
  ```dart
  _destMarker = await c.addSymbol(ml.SymbolOptions(
    geometry: geo,
    iconImage: _kDestIcon,
    iconSize: _kDestIconSize,
    iconAnchor: 'bottom',
    zIndex: 10,   // ← 추가
  ));
  ```

  **변경 3** — `_syncWaypointMarkers` (main_map_screen.dart:329-334):
  ```dart
  final s = await c.addSymbol(ml.SymbolOptions(
    geometry: _toMl(wp),
    iconImage: _kWpIcon,
    iconSize: _kWpIconSize,
    iconAnchor: 'bottom',
    zIndex: 5,    // ← 추가
  ));
  ```

---

## 4. 미확인/리스크

- **라벨 없는 아이콘 핀 + allow-overlap:** 두 핀 모두 `textField` 없음 → `textAllowOverlap` 무관.
  `iconAllowOverlap=true`만으로 충분, 텍스트 충돌 문제 없음.

- **`setSymbolIconAllowOverlap` 타이밍:** 내부에서 `_rebuildLayers()` 호출.
  스타일 로드 시점에 심볼 addSymbol 전에 호출하면 레이어 재빌드가 비어있는 상태에서 일어나 안전.
  단, 이미 심볼이 추가된 후 호출해도 재빌드 후 기존 심볼은 GeoJSON source에서 재로드되므로 문제 없음.

- **zIndex null vs 0:** SymbolOptions.zIndex 미지정 시 `toJson`에서 해당 키 누락.
  `symbolSortKey` expression이 `[Expressions.get, 'zIndex']`이므로 프로퍼티 없으면 null 취급.
  null과 숫자 5 비교 시 null이 낮은 키로 처리되는지는 MapLibre JS 스펙 의존 — 명시적으로
  `zIndex: 5`/`zIndex: 10`으로 모두 지정하는 것이 안전.

- **경유지 기존 updateSymbol 없음:** `_syncWaypointMarkers`는 매번 전체 remove→add.
  zIndex 추가는 신규 addSymbol 시에 적용되므로 기존 updateSymbol 경로와 무관, 영향 없음.

- **목적지 updateSymbol 경로 (geometry만 갱신):** (main_map_screen.dart:309)
  `updateSymbol(_destMarker!, SymbolOptions(geometry: geo))`만 호출 — zIndex는 copyWith로 유지됨.
  (SymbolOptions.copyWith: `zIndex: changes.zIndex ?? zIndex` → 기존값 유지)
