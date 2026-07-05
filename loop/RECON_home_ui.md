# RECON: Home-screen UI parity + course→color wiring

Read-only recon. No edits made.

---

## (1) Arrow puck still looks small on nav_screen

**Current values** — `lib/features/navigation/presentation/nav_screen.dart:66-75`
- `_kDestIcon` = `pointer_red`, canvas 96×96, `_kDestIconSize = 1.05` → on-screen canvas footprint `96 × 1.05 = 100.8px`
- `_kWpIcon` = `pointer_yellow`, same 96×96 asset, `_kWpIconSize = 1.05` → same 100.8px
- `_kArrowIcon` = `nav_arrow` (`assets/images/arrow_puck.png`), canvas 144×144, `_kArrowIconSize = 0.7` → on-screen canvas footprint `144 × 0.7 = 100.8px`

The size-match commit (4b64525) did the canvas-px math correctly — both symbols occupy the **same 100.8px canvas footprint** on screen. The bug is downstream of that: canvas footprint ≠ visible-ink footprint, because the two PNGs use very different amounts of internal padding.

Measured actual alpha-channel bounding boxes (`python3 -c PIL`):

| asset | canvas | visible bbox (non-transparent) | visible size | coverage (h) |
|---|---|---|---|---|
| `pointer_red.png` / `pointer_yellow.png` | 96×96 | (16,0)-(80,96) | 64×96 | **100%** of canvas height |
| `arrow_puck.png` | 144×144 | (22,16)-(122,132) | 100×116 | **80.6%** of canvas height |

The teardrop pin art fills its canvas edge-to-edge vertically (bottom-anchored tip touches y=96), while the arrow art has ~16px of transparent margin top and bottom baked into the 144px canvas.

**Result at current sizes:** pin visible height = 100.8px (100% of 100.8), arrow visible height = 100.8 × 0.806 ≈ **81.2px** — the arrow is ~20% shorter on screen than the pin despite identical canvas iconSize math. This is the "looks smaller" the user is seeing; it's not a units/math bug, it's a content-padding mismatch between the two source PNGs.

**Fix options:**
- **(a) Bump `_kArrowIconSize`** to compensate for the 80.6%-coverage discrepancy: `1.05 × (96/144) / 0.806 ≈ 0.869`. Raising `_kArrowIconSize` from `0.7` → **~0.87** makes the arrow's *visible* height match the pin's visible height (~100.8px). Zero-risk, one-line change, no asset regeneration. Width will end up slightly wider than the pin's (arrow bbox is wider relative to its own canvas: 69% vs pin's 67%), but that's expected/fine for an arrow glyph vs a narrow teardrop.
- **(b) Regenerate `arrow_puck.png`** with the arrow art cropped tighter to the canvas (less transparent padding) so canvas-px scaling alone stays accurate. More correct long-term (keeps the `0.7` ratio meaningful) but requires touching the asset, not just code.
- Recommend (a) first as the immediate fix since it's a single constant change; consider (b) later if the asset gets reused elsewhere.

---

## (2) `main_map_screen.dart` (home) vs `nav_screen.dart` (nav) — parity gaps

### User-location marker
- **Home** (`lib/features/map/presentation/main_map_screen.dart:304-321`, `_ensureLocationMarker`): draws an `ml.Circle` (`addCircle`/`updateCircle`), `circleRadius: 8`, `circleColor: _kLocColor` (`#00C853` green), white stroke. **No heading/bearing, no rotation, no arrow_puck reference anywhere in the file** (confirmed via grep — zero hits for `arrow_puck`, `iconRotate`, `headingDeg`, `bearing`).
- **Nav** (`nav_screen.dart:606-657`): raw GeoJSON symbol layer with `iconImage: nav_arrow` (arrow_puck.png), `iconRotate: ['get','bearing']`, `iconRotationAlignment: 'map'`, driven by live heading off `navStateProvider`.
- So home currently shows a **static, non-rotating green dot** for the user, not the arrow puck at all. This is the biggest visual mismatch.

### Dest/waypoint pins
- **Home** (`main_map_screen.dart:106-109, 323-365`): already uses the same `pointer_red` / `pointer_yellow` images (loaded at `main_map_screen.dart:926-929`), anchor `bottom`. **But `_kDestIconSize = 1.5` and `_kWpIconSize = 1.5`** — i.e. canvas footprint `96 × 1.5 = 144px`.
- **Nav**: same images, but `_kDestIconSize = _kWpIconSize = 1.05` → canvas footprint `100.8px` (this is what the "-30%" tuning commit, 4b64525, was for).
- So the pin **images** already match between screens (good, this was done in an earlier commit per the CLAUDE.md/commit history), but the **sizes do not** — home's pins render ~43% larger (144px vs 100.8px footprint) than nav's. This is a leftover from before the nav-side "-30%" tune; home was never updated to match.

### "Does home even show a user-location arrow during planning?"
Currently: no — home shows only the static green circle for the rider's own position, and (once a destination is set) the red/yellow pins for dest/waypoints. There is no heading-arrow concept on home at all today. "Home matches nav" concretely means:
1. Replace the green `Circle` user marker with the same `nav_arrow` (arrow_puck.png) symbol-layer approach nav_screen uses — raw GeoJSON source + `addSymbolLayer` with `iconRotate`/`iconRotationAlignment: 'map'`, fed by heading from `navStateProvider` (home already subscribes to `navStateProvider` at `main_map_screen.dart:203-219`, so heading data is already flowing in, just unused for rotation/marker choice).
2. Apply the same fixed `_kArrowIconSize` (whatever nav lands on, e.g. the ~0.87 from item 1) so puck size matches.
3. Reduce `_kDestIconSize`/`_kWpIconSize` on home from `1.5` down to `1.05` to match nav's pin scale.
4. (Cosmetic, not requested but adjacent) home's `circleColor`/origin marker concept disappears entirely once replaced by the arrow puck — no separate "origin dot" is needed post-change, matching how nav has no dot, only the arrow.

---

## (3) Route-line color should reflect selected course, on both screens

### Where the 3 course options are defined
- `MapInteractionState.selectedRouteIdx` — `lib/features/map/providers/map_providers.dart:104` — comment states the index meaning explicitly: **`0: 시골길(rural/scenic), 1: 지방도로(regional), 2: 국도(national/fast)`**. Default `selectedRouteIdx = 2` (line 116).
- This is a `Notifier<MapInteractionState>` (`MapInteractionNotifier`, `map_providers.dart:159`) — a global Riverpod provider (`mapInteractionProvider`), not screen-local state. `setSelectedRouteIdx(idx)` mutates it (`map_providers.dart:206`).
- The course *labels/colors used for the selector UI* live separately in `_CourseSheet._routes` (`main_map_screen.dart:1512-1516`):
  ```
  index 0: '시골길로\n느긋하게' → AppColors.mapCourse   (0xFF4CAF50, green)
  index 1: '지방도로\n여유롭게' → AppColors.tertiary     (0xFF00B1F0, light blue)
  index 2: '국도로\n빠르게'   → AppColors.primary       (0xFF F28C28, orange)
  ```
  These are only used for the course-selector **card badges**, not the polyline. Note the requested target mapping (국도=blue, 지방도=green, 시골길=dark yellow) does **not** match either the current card-badge colors above or the current line colors below — all three need remapping, not just wiring-through.

### Where route LineLayer color is currently set
- **`main_map_screen.dart` `_initRouteLayer` (lines 266-300):** selected-route layer (`_routeLayerId`) hardcoded `lineColor: '#1E5AFF'` (blue), width 6. Non-selected routes drawn on a separate bg layer (`_routeBgLayerId`) hardcoded grey `#9E9E9E`, width 4. Color is **not** re-set anywhere when `selectedRouteIdx` changes — `_updateRouteLayer` (line 367) only calls `setGeoJsonSource`, never touches paint properties. So today home's selected route is **always blue regardless of which course is chosen.**
- **`nav_screen.dart` `_initRouteLayer` (lines 606-620):** hardcoded `lineColor: '#F28C28'` (nav orange), width 6, with a code comment "`// nav 오렌지색 유지`" (keep nav orange) — i.e. this was deliberately fixed, not yet meant to vary. Also never updated after set.

### Is selected-course info available at both draw sites?
- **Home:** yes, trivially — `_initRouteLayer`/`_updateRouteLayer` run inside `_MainMapScreenState`, which already does `ref.read(mapInteractionProvider)` elsewhere in the same class (e.g. `_updateRouteLayer` line 372, `_onRouteCardSelect` line 792). Wiring color-by-course here only requires reading `state.selectedRouteIdx` at paint/update time — no new plumbing needed.
- **Nav:** `NavScreen`'s constructor does **not** receive a course index/enum — `_startNavigation` (`main_map_screen.dart:753-789`) passes only `destination, waypoints, routePolyline, maneuvers, durationMin`, no `selectedRouteIdx`/course label. However, `nav_screen.dart` already reads the same global `mapInteractionProvider` in `_reroute` (`nav_screen.dart:362`: `ref.read(mapInteractionProvider).selectedRouteIdx`) — so the course index **is** reachable from NavScreen today via the shared provider, without adding a constructor param. Caveat: this only works because `mapInteractionProvider` isn't reset/cleared before `NavScreen` reads it; confirm `_clearDestination()` (called in the `.then()` after `Navigator.push` returns, i.e. only after nav closes) doesn't fire earlier — it doesn't, it's post-pop, so state should still hold the right `selectedRouteIdx` for the whole nav session. One risk: if the user reroutes mid-navigation, `_reroute` re-reads `selectedRouteIdx` from the same provider (line 362) — so course identity survives reroutes for free.

---

## Summary of fix approach (not applied — recon only)

**(a) Arrow size:** bump `_kArrowIconSize` in `nav_screen.dart:75` from `0.7` to `~0.87` to match visible (not canvas) height against the pins. Cheap, no asset changes. Longer-term, consider re-cropping `arrow_puck.png` to reduce internal padding so the canvas-ratio math is trustworthy again.

**(b) Home parity checklist:**
1. Swap home's `_ensureLocationMarker` (Circle) for a nav-style GeoJSON symbol layer using `nav_arrow` / arrow_puck.png, rotated by heading from the already-subscribed `navStateProvider`.
2. Match `_kArrowIconSize` between screens.
3. Shrink home's `_kDestIconSize`/`_kWpIconSize` from `1.5` to `1.05` to match nav's pin scale.

**(c) Course→color wiring:**
- Source of truth: `mapInteractionProvider` (`MapInteractionState.selectedRouteIdx`, `map_providers.dart:104`), global Riverpod state, index `0=시골길/rural, 1=지방도로/regional, 2=국도/national`.
- Define a `{0: darkYellow, 1: green, 2: blue}` color map (per the requested 국도=blue/지방도=green/시골길=dark yellow scheme) as a shared constant (e.g. in `app_theme.dart` alongside `AppColors.mapCourse` etc., since that file is already imported by both screens) — note this differs from `_CourseSheet`'s existing card-badge colors, which should probably be updated too for consistency (not currently in scope but flagged since they'll visually contradict the line color otherwise).
- **Home:** read `selectedRouteIdx` in `_initRouteLayer`/`_updateRouteLayer` and set `_routeLayerId`'s `lineColor` from the map instead of the hardcoded `#1E5AFF`; needs a `setLayerProperties`-style call (or layer recreation) since MapLibre line paint isn't set via `setGeoJsonSource`.
- **Nav:** same map, keyed off `ref.read(mapInteractionProvider).selectedRouteIdx` (already proven reachable per `_reroute`'s existing usage) instead of the hardcoded `#F28C28` / the "nav 오렌지색 유지" comment — that comment signals this was an intentional placeholder, not a hard requirement to keep orange.
