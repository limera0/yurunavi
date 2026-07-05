# RECON — pin images (dest/waypoint) + rotating heading-arrow puck

Scope: `lib/features/navigation/presentation/nav_screen.dart` (nav screen, the target of
this change). `lib/features/map/presentation/main_map_screen.dart` (planning screen) is
included because **it already implements pin images** — it's the reference pattern, not
a green field.

---

## 1. Current dest/waypoint markers on nav screen (CircleLayer, native GeoJSON)

Confirms prior RECON: markers are native `CircleLayer`s, not FlutterMap overlay.

- Source/layer id constants: `nav_screen.dart:70-77`
  - `_navRouteSourceId`/`_navRouteLayerId` (route line)
  - `_navLocSourceId`/`_navLocLayerId` (puck)
  - `_navDestSourceId`/`_navDestLayerId` (destination)
  - `_navWaypointSourceId`/`_navWaypointLayerId` (waypoints)
- GeoJSON builder (single/multi point): `_buildPointsGeoJson` — `nav_screen.dart:599-613`
- Creation, one-shot, gated by `_destLayerReady`: `_initDestLayer` — `nav_screen.dart:666-698`
  - waypoints: `addGeoJsonSource(_navWaypointSourceId, …)` + `addCircleLayer(circleRadius:10, circleColor:_kWaypointColor …)` — `nav_screen.dart:671-682`
  - destination: `addGeoJsonSource(_navDestSourceId, …)` + `addCircleLayer(circleRadius:15, circleColor:_kDestColor …)` — `nav_screen.dart:686-696`
- Call order (this fixes z-order today): `_onStyleLoaded` — `nav_screen.dart:700-712`
  `_initRouteLayer()` → `_initDestLayer()` (waypoint layer, then dest layer, in that order inside the function) → `_initLocationLayer()` → `_ensureLocationMarker()`.
  Later-added layer paints on top in MapLibre, so today's stack bottom→top is: route < waypoint < dest < puck.

### maplibre_gl 0.26.1 API check (verified in pub-cache sources, not docs)

`~/.pub-cache/hosted/pub.dev/maplibre_gl-0.26.1` and `maplibre_gl_platform_interface-0.26.1`:

- `MapLibreMapController.addImage(String name, Uint8List bytes, [bool sdf=false])` — `controller.dart:1656`. Registers a named sprite from raw PNG bytes. Must run once per style load (style reinjection wipes the sprite atlas — see main_map_screen's own comment, §2 below).
- Two independent paths to render an icon at a point, **both exist and both work**:
  1. **`addSymbolLayer(sourceId, layerId, SymbolLayerProperties, {belowLayerId, filter, …})`** — `controller.dart:611-633`. GeoJSON-source-driven, exactly parallel to the `addCircleLayer` calls already in `_initDestLayer`. `SymbolLayerProperties` has `iconAnchor`, `iconOffset`, `iconRotate`, `iconRotationAlignment`, `iconAllowOverlap` as raw style-spec fields (`layer_properties.dart:261-443`, `806-811`), each of which also accepts a `[Expressions.get, 'propName']` data-expression bound to per-feature GeoJSON properties.
  2. **`addSymbol(SymbolOptions)`** (annotation API) — `controller.dart:1123`, options class `maplibre_gl_platform_interface/lib/src/symbol.dart:61-127`. This is a managed annotation (`SymbolManager`) that keeps a Dart-side `Symbol` handle you `updateSymbol()`/`removeSymbol()` on. `SymbolOptions` has `iconAnchor`, `iconRotate` — **but no `iconRotationAlignment`**. Checked `SymbolManager.allLayerProperties` (`annotation_manager.dart:361-390`): it hardcodes every layer property except a rotation-alignment override, so it falls back to the MapLibre style-spec default (`icon-rotation-alignment: "auto"`, which resolves to **viewport**-relative rotation for point placement, not map-relative). This matters for §3/§5.

### Which API for pins

**`addSymbol` (annotation), matching the pattern main_map_screen.dart already uses — recommended for dest/waypoint pins.** Reasons:
- Already proven in this exact codebase: `main_map_screen.dart:323-338` (`_ensureDestMarker`) and `:348-365` (`_syncWaypointMarkers`) call `c.addSymbol(SymbolOptions(iconImage:_kDestIcon, iconSize:_kDestIconSize, iconAnchor:'bottom', zIndex:10))` / same for waypoints with `_kWpIcon`, `zIndex:5`.
- Pins are static (never rotate), so the annotation manager's fixed viewport-alignment default is irrelevant — no rotation is requested.
- `addSymbol` gives you a handle to `updateSymbol`/`removeSymbol` individually, which is nicer than rebuilding a whole FeatureCollection for 1-2 static points (though nav_screen's dest/waypoints are `widget.destination`/`widget.waypoints`, both `final`, set once — so a raw `SymbolLayer` + one-shot GeoJSON would work equally well here and would be more consistent with the CircleLayer code it's replacing. Either is fine; **addSymbol matches the sibling screen's existing convention**, which is the stronger argument.)
- `iconAnchor: 'bottom'` is exactly the anchor needed to put the teardrop **tip** (not center) on the coordinate, and it's already validated at 96×96 in the sibling screen (see §2).

## 2. Asset registration — already done, reusable as-is

- `pubspec.yaml:38-41` — `assets:` already lists the whole `assets/images/` directory (not per-file), so no pubspec edit is needed for new PNGs.
- The two PNGs the task describes **already exist**, already at spec: `assets/images/pointer_red.png` and `assets/images/pointer_yellow.png`, both confirmed 96×96 8-bit RGBA via `file(1)`.
- They are **already wired and in production use on the planning screen** (`main_map_screen.dart`), not just present as unused assets:
  - Icon name constants: `main_map_screen.dart:106-109` (`_kDestIcon='pointer_red'`, `_kDestIconSize=1.5`, `_kWpIcon='pointer_yellow'`, `_kWpIconSize=1.5` — sized 1.5x per an on-phone visual calibration comment).
  - Registration, inside `onStyleLoadedCallback`, **after** `_styleLoaded=true` and **before** any `addSymbol` call: `main_map_screen.dart:925-930`
    ```
    final pinBytes = await rootBundle.load('assets/images/pointer_red.png');
    await _mlCtrl!.addImage('pointer_red', pinBytes.buffer.asUint8List());
    final wpBytes = await rootBundle.load('assets/images/pointer_yellow.png');
    await _mlCtrl!.addImage(_kWpIcon, wpBytes.buffer.asUint8List());
    await _mlCtrl!.setSymbolIconAllowOverlap(true);
    ```
  - `rootBundle` import: `main_map_screen.dart:5` (`import 'package:flutter/services.dart' show SystemNavigator, rootBundle;`).
- **Wiring needed for nav_screen.dart**: none at the asset level. Code-level, `_onStyleLoaded` (`nav_screen.dart:700-712`) needs the identical `rootBundle.load` + `addImage('pointer_red', …)` / `addImage('pointer_yellow', …)` pair inserted before `_initDestLayer()` runs, and `nav_screen.dart` needs a `rootBundle` import (currently only `flutter/material.dart` and `flutter/services.dart` — check: `nav_screen.dart:10-11` imports `flutter/services.dart` already for `SystemChrome`/similar, need to confirm `rootBundle` is exposed via that same import, which it is, since it's the same package).

## 3. User puck arrow

- Current puck: native `CircleLayer`, `_initLocationLayer` — `nav_screen.dart:635-651` (`circleRadius:12, circleColor:_kLocColor='#2D7DF6', circleStrokeWidth:4, circleStrokeColor:'#FFFFFF'`), position refreshed every GPS tick via `_ensureLocationMarker` — `nav_screen.dart:653-661` (`setGeoJsonSource(_navLocSourceId, _buildLocGeoJson(p))`), called from the location subscription at `nav_screen.dart:236`.
- `_buildLocGeoJson` — `nav_screen.dart:584-597` — currently emits a bare Point with empty `properties: {}`. No bearing/heading is threaded into it today.

### (a) CircleLayer can't rotate — confirmed, need SymbolLayer

Correct. `CircleLayerProperties` has no rotation-capable field (circles are radially symmetric); style spec has no such property for circle layers either. A rotating icon requires `SymbolLayer` (icon-image + icon-rotate), matching the task's proposed approach.

Given the rotation-alignment gap in the annotation manager (§1), **the puck must use `addSymbolLayer` (raw GeoJSON-backed SymbolLayer), not `addSymbol`** — `addSymbol`'s `SymbolManager` cannot express `icon-rotation-alignment: map`, and defaulting to viewport-alignment breaks the heading-up behavior (see §5). This is a real functional difference from the pins, not just a style preference.

### (b) Heading source reuse

Yes — `effectiveHeadingDeg` is already computed once per tick at `nav_screen.dart:229` via `_resolveHeading(next.speedKmh, next.headingDeg)` — `nav_screen.dart:516-519`. It's already the single source used both for camera bearing (`nav_screen.dart:234`) and for the `_recenter` offset math (`nav_screen.dart:231`), specifically to avoid "two heading generations" divergence between frames (existing comment at `nav_screen.dart:225-228`, `511-515`).

**Important wiring gap for implementation**: `_ensureLocationMarker()` (`nav_screen.dart:653-661`, called at `nav_screen.dart:236`) currently takes **no heading parameter** — it only re-reads `pos` from `navStateProvider` (`nav_screen.dart:658`). To stamp a `bearing` property into the puck's GeoJSON feature, `effectiveHeadingDeg` must be threaded into `_ensureLocationMarker` as a parameter from the same tick (same pattern already used for `_recenter(loc, speedKmh:…, headingDeg: effectiveHeadingDeg)` at line 231) — not recomputed inside `_ensureLocationMarker` from a fresh `ref.read`, or it risks exactly the stale/reordered-heading bug the existing comments already call out.

### (c) `icon-rotate` + `icon-rotation-alignment: map` in SymbolLayer — confirmed supported

Both are real `SymbolLayerProperties` fields, serialized straight to style-spec JSON keys: `icon-rotate` (`layer_properties.dart:365`, serialized `layer_properties.dart:941`) and `icon-rotation-alignment` (`layer_properties.dart:303`, serialized `layer_properties.dart:936`). Both accept either a literal or a data-expression (`[Expressions.get, 'bearing']`) bound to a per-feature GeoJSON property — same pattern the built-in `SymbolManager` itself uses internally (`annotation_manager.dart:365`, `iconRotate: [Expressions.get, 'iconRotate']`), just not exposed through `addSymbol`'s public API for rotation-alignment.

### (d) Asset need — yes, an original arrow PNG must be generated

No SVG/vector icon path exists in this stack: `addImage` takes raw pixel bytes (`Uint8List`) for a sprite atlas entry (`controller.dart:1656`), and no SVG-to-sprite conversion utility appears anywhere in this codebase's map code. A triangle/arrow must be rasterized to a PNG (transparent RGBA, consistent with the 96×96 teardrop pins) and added at e.g. `assets/images/nav_arrow.png`, then `addImage('nav_arrow', bytes)` alongside the pin registrations in `_onStyleLoaded`. Must be an original design per the task (no Naver asset copy) — a simple chevron/cone shape pointing "up" in the source image (rotation reference = 0° = up) is the standard convention and is what `icon-rotate` values are measured against.

## 4. Z-order with SymbolLayers

Confirmed the existing call-order-only z-ordering approach (`nav_screen.dart:633-634` comment: "belowLayerId 없이 call order만으로 z-order를 확정") carries over unchanged to `SymbolLayer`s — MapLibre layer paint order is purely insertion order regardless of layer *type*, so swapping `addCircleLayer` → `addSymbolLayer` at the same call sites in the same sequence (`_initRouteLayer` → `_initDestLayer` [waypoint, then dest] → `_initLocationLayer`) preserves route < waypoint < dest < puck without needing `belowLayerId` (which main_map_screen.dart *does* use, at `main_map_screen.dart:285,298`, to interleave route lines under its annotation-manager-owned circle/symbol layers — a different constraint from nav_screen's pure native-layer stack, not applicable here since nav_screen owns all its layers directly).

## 5. Heading-up double-rotation analysis — verdict: not a risk, but alignment mode must be explicit

Key fact not obvious from the task prompt: `rotateGesturesEnabled: false` is set on nav_screen's `MapLibreMap` (`nav_screen.dart:774`), so **the user can never manually rotate the map** (two-finger rotate gesture is disabled). The *only* thing that ever changes map bearing is the app's own `animateCamera(CameraUpdate.bearingTo(effectiveHeadingDeg))` call at `nav_screen.dart:234`, and that call is **not** gated by `_isManualMode` (only the pan/recenter at line 231 is) — so map bearing is single-source-of-truth: it always equals the last `effectiveHeadingDeg` seen while `speedKmh > 2`, and freezes otherwise (line 233's guard). `_isManualMode` (set on touch, `nav_screen.dart:714-719`) only pauses camera *panning*, not bearing rotation.

Given that:
- Map bearing = `effectiveHeadingDeg` (or frozen at last value) — always.
- If the puck's `icon-rotate` is bound to the **same** `effectiveHeadingDeg` value **with `icon-rotation-alignment: 'map'`**, the two rotations are applied in the same reference frame and cancel exactly: the arrow, which is rotated by `heading` *within* the map's north-referenced frame, ends up screen-vertical once the map itself is rotated by `heading`. Net visual: arrow always points up while moving, holds last direction while stopped — exactly the desired Naver-style behavior, and it degrades gracefully (no visible lag/mismatch) through the `animateCamera` transition because both values are driven by the same tick's variable, not independently re-derived.
- Using the default/viewport alignment instead (i.e. accidentally going through `addSymbol`, §1/§3a) would decouple icon rotation from map rotation — the icon would rotate against the *screen*, and since nothing else on screen counter-rotates, this would produce a **static up-pointing arrow that never reflects a heading change relative to the rotated map** (it would look "right" only by coincidence, since gestures are disabled — but it's not deriving correctness from heading at all, it'd be equally "right" if heading input were disconnected entirely). This is the double-rotation trap the task is asking about — but the actual failure mode here is closer to "silently ignores heading" than "double-rotates", precisely because gestures are locked out. **Must use raw `SymbolLayer` with `iconRotationAlignment: 'map'` explicitly**, not `addSymbol`.

---

## Summary / recommendations

**(a) Pins (dest/waypoint):** use `addSymbol` (annotation API), mirroring `main_map_screen.dart:323-365` exactly. `iconAnchor: 'bottom'` puts the teardrop tip on the coordinate. Assets (`pointer_red.png`, `pointer_yellow.png`) and pubspec wiring already exist — zero new asset work, only need to replicate the `rootBundle.load` + `addImage` + `addSymbol` calls into `nav_screen.dart`'s `_onStyleLoaded`/`_initDestLayer`, replacing the current `addCircleLayer` calls there.

**(b) Puck arrow:** feasible in 0.26.1, but **must** go through raw `addSymbolLayer` (GeoJSON `SymbolLayer`) — not `addSymbol` — because only the raw `SymbolLayerProperties` path exposes `iconRotationAlignment`, which is required (`'map'`, not the annotation manager's implicit viewport default). Needs a new **original arrow/chevron PNG asset** generated (no SVG path available; raster only, matching 96×96 RGBA convention of the pins). Also needs `_buildLocGeoJson` (`nav_screen.dart:584-597`) extended to carry a `bearing` property, and `_ensureLocationMarker` (`nav_screen.dart:653-661`) extended to accept the tick's `effectiveHeadingDeg` as a parameter (currently missing — it only re-reads position), threaded from the subscription callback (`nav_screen.dart:229-236`) the same way `_recenter` already receives it, to avoid a stale-heading mismatch between the puck and the camera bearing.

**(c) Asset/pubspec wiring:** none needed for pins (already present, already used elsewhere). One new PNG needed for the arrow; pubspec needs no edit (directory-level asset glob already covers `assets/images/`).

**(d) Double-rotation caveat verdict:** not an actual double-rotation bug given `rotateGesturesEnabled:false` locks bearing to a single code-controlled source — but it *will* silently misbehave (arrow decoupled from true heading, "accidentally" looking fine only because gestures are off) if implemented via `addSymbol`'s default viewport alignment instead of an explicit `iconRotationAlignment:'map'` raw `SymbolLayer` bound to the exact same `effectiveHeadingDeg` value already used for the camera's `bearingTo` call.
