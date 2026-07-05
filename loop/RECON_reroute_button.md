# RECON — 재탐색 버튼 (Naver-style) 재배치 + 코스 재선택

Scope: read-only recon for moving the round ↻ reroute button out of the right
control column and into the bottom card as a "재탐색" text button that
zooms-to-fit the whole route and opens the 3-course chooser mid-navigation.

Files touched by this recon:
- `lib/features/navigation/presentation/nav_screen.dart` (1309 lines)
- `lib/features/map/presentation/main_map_screen.dart` (2020 lines)
- `lib/features/map/providers/map_providers.dart`
- `lib/services/routing_service.dart`

---

## 1. Current reroute button (right column) — what to remove

- `_NavIconBtn` widget class: `nav_screen.dart:1196-1232` (generic circular icon
  button, `icon`/`onTap`/`loading`/`enabled`). **Used twice** — do not delete
  the class, only one call site.
- Right control column: `nav_screen.dart:995-1038`, a `Column` inside
  `Positioned(right: 12, top: 200, bottom: 160, ...)` containing:
  - `DaylightBar` (Expanded)
  - `_NavIconBtn` recenter/GPS button — `nav_screen.dart:1014-1028` (icon
    toggles `gps_fixed`/`my_location`, resets `_isManualMode`) — **keep, not
    in scope**.
  - `_NavIconBtn` ↻ reroute button — `nav_screen.dart:1030-1035`:
    ```dart
    _NavIconBtn(
      icon: Icons.refresh_rounded,
      loading: _isRerouting,
      enabled: navState?.pos != null,
      onTap: _manualReroute,
    ),
    ```
    This is the one to **remove** (plus the `SizedBox(height: 10)` at
    `:1029` immediately above it, to avoid a dangling gap).
- Handler chain:
  - `_manualReroute()` — `nav_screen.dart:399-403`. Only caller is the button
    above (`:1034`). Body: reads current pos, calls `_reroute(pos, silent:
    true)`. **After removing the button this method becomes dead code** —
    delete it, or repurpose it if the new flow still wants a "silent
    re-fetch on same course" fallback (it won't; the new flow drives
    `_reroute` differently, see §5).
  - `_reroute(LatLng origin, {bool silent = false})` — `nav_screen.dart:336-397`.
    This is the real workhorse (fetch + apply + fallback bookkeeping) and
    **stays**, reused by the new flow (§5).
  - `_triggerReroute()` (`:322-334`, auto off-route reroute) also calls
    `_reroute` — unaffected by this change.
- No other references to `_NavIconBtn`'s refresh icon or `_manualReroute`
  elsewhere in the file or repo (`grep -rn "_manualReroute"` → only the two
  lines above).

**Removal is clean**: delete lines `:1029-1035`, delete `_manualReroute`
(`:399-403`) unless repurposed.

---

## 2. Bottom card — inserting "재탐색"

Bottom card: `nav_screen.dart:1041-1103` — `Positioned(bottom:0,left:0,right:0)`
→ `Container` (rounded top, `cs.surface`) → `SafeArea` → `Padding` → `Row`:

```
Row
 ├─ Expanded(Column[ETA text, Column[remaining+km]])   :1056-1078
 ├─ Container(width:1, height:40)  divider              :1079
 └─ GestureDetector → 종료 button (Container, red)       :1080-1097
```

There is no fourth element yet. To get `ETA | 재탐색 | 종료`:

**Proposal**: insert a second small `GestureDetector`/`Container` button
between the divider (`:1079`) and the 종료 `GestureDetector` (`:1080`), styled
as a neutral/secondary pill (not red, since it's not destructive) — e.g.
`cs.surfaceContainerHigh` background, `cs.tertiary` or `cs.onSurface` text,
`Icons.alt_route` or `Icons.route_outlined` + `재탐색` label, same
`padding/borderRadius` proportions as 종료 but narrower. A second thin
divider (or just `SizedBox(width: 10)`) between it and 종료 keeps the visual
grouping "ETA | 재탐색 | 종료".

Row-fit: the `Expanded` on the ETA column absorbs all leftover width, so
adding a third fixed-width child does **not** require restructuring the Row —
it only shrinks the Expanded region proportionally. Screen-width risk is low
given 종료 is already a fixed ~70-80px pill and phones targeted are ≥360dp
wide; worth a quick visual check on a narrow device (e.g. 360dp) once built,
but no structural Row change is needed. Disable state: mirror the existing
`enabled: navState?.pos != null` gate from the old icon button (no GPS fix →
재탐색 disabled/greyed), and gate on `!_isRerouting`/`!_showCourseSheet-ish`
similarly to avoid double-triggering while a fetch is in flight.

---

## 3. Zoom-to-fit whole route

Confirmed: `ml.CameraUpdate.newLatLngBounds(bounds, {left, top, right,
bottom})` is available and already used twice in this codebase, both in
`main_map_screen.dart`:

- `:441-452` — fits the full route polyline bounds (min/max lat/lng reduced
  from `points`) after `setRoutePolyline`, padding `left:50, top:110,
  right:80, bottom: _showCourseSheet ? 360 : 80`.
- `:664-675` — fits origin↔destination bounds (before any route is fetched)
  with `bottom: 260` (course sheet about to open).

Same pattern applies directly to nav: build bounds from
`_routePoints` (`nav_screen.dart:111`, the mutable copy of
`widget.routePolyline`, kept current across reroutes) exactly like
`main_map_screen.dart:436-439`:

```dart
final minLat = _routePoints.map((p) => p.latitude).reduce(min);
final maxLat = _routePoints.map((p) => p.latitude).reduce(max);
final minLng = _routePoints.map((p) => p.longitude).reduce(min);
final maxLng = _routePoints.map((p) => p.longitude).reduce(max);
_mlCtrl?.animateCamera(ml.CameraUpdate.newLatLngBounds(
  ml.LatLngBounds(southwest: ml.LatLng(minLat,minLng), northeast: ml.LatLng(maxLat,maxLng)),
  left: 50, top: 110, right: 80, bottom: <course-sheet-height>,
));
```
`_routePoints` already spans current-position→destination (it's the live
route, re-set on every `_reroute`), so no separate "current pos + dest only"
bounds calc is needed — using the polyline bounds is a superset and simpler.

**Overview-hold flag**: `_isManualMode` (`nav_screen.dart:82`) currently means
"user just panned the map manually":
- Set `true` on any map touch (`_onMapGesture`, `:709-724`), which also arms
  a 10s `_recenterTimer` that flips it back to `false` and force-recenters.
- While `true`, the location-tick handler **skips `_recenter`** (pan/zoom
  follow) at `:233-235`, but does **not** skip the bearing rotation call at
  `:236-238` (`animateCamera(bearingTo(...))` still runs whenever
  `speedKmh > 2`) — that's a gap for our purposes, see below.
- A banner "탭하여 복귀" (`:778-789`, `if (_isManualMode)`) is shown while in
  this mode.

It's reusable but not a perfect fit as-is:
- ✅ Reusing `_isManualMode = true` to suppress `_recenter` (so the overview
  camera position we set isn't immediately overwritten by the next GPS tick)
  works today.
- ⚠️ The 10s auto-revert timer (`_recenterTimer` in `_onMapGesture`) must
  **not** be armed for the reroute-overview case — we want the overview held
  until the user finishes the course sheet (pick or dismiss), which could
  take longer than 10s. So don't call `_onMapGesture()`; just set
  `_isManualMode = true` directly and cancel/skip `_recenterTimer`.
  Explicitly set it back to `false` (and re-`_recenter`) in the sheet's
  `onSelect-confirm`/`onClose` callbacks.
- ⚠️ Bearing auto-rotation (`:236-238`) is not gated by `_isManualMode`, so
  during the overview the camera could still rotate to heading while the
  user is trying to look at a bounds-fitted, presumably north-up-ish view.
  Needs an added `&& !_isManualMode` guard there (or a new dedicated
  `_overviewMode` bool instead of overloading `_isManualMode`, to avoid
  interference with the "탭하여 복귀" banner showing during a course-sheet
  interaction, which would be confusing UI clutter).

**Recommendation**: introduce a **new** flag, e.g. `_showCourseSheet` (mirror
naming from `main_map_screen.dart:135`) rather than overloading
`_isManualMode`, and gate both `_recenter` (`:233`) and the bearing rotate
call (`:236`) on `!_isManualMode && !_showCourseSheet`. This avoids changing
`_isManualMode`'s existing pan-gesture semantics/banner while still holding
the overview. Low complexity either way — reusing `_isManualMode` saves one
bool but couples two unrelated concerns.

---

## 4. Course-selection sheet — reuse vs. new

`_CourseSheet` (`main_map_screen.dart:1554-1666`), plus its private
dependents `_RouteInfo` (`:1668-1672`) and `_RouteCard` (`:1674+`), are all
**library-private** (`_`-prefixed) classes declared directly in
`main_map_screen.dart`. `nav_screen.dart` cannot import them as-is — Dart
privacy is per-file, not per-class-name.

**Dependencies are all public/importable**, so extraction is low-friction:
- `courseLineColor` — from `core/theme/app_theme.dart` (already imported by
  both files).
- `SliderStartButton` — `core/widgets/slider_start_button.dart` (already
  imported by `main_map_screen.dart`; trivial one-line add to
  `nav_screen.dart`).
- `AppColors`, `colorToHex` — same theme file.
- `_CourseSheet`'s constructor args (`routeMeta`, `selectedIdx`, `onSelect`,
  `onStart`, `onClose`) have **no hidden coupling** to `main_map_screen`
  state — it's a pure presentational widget driven entirely by callbacks.

**Proposal**: extract `_CourseSheet`/`_RouteInfo`/`_RouteCard` (rename to
public `CourseSheet`/`RouteInfo`/`RouteCard`) into a new shared file, e.g.
`lib/core/widgets/course_sheet.dart`, then have both `main_map_screen.dart`
and `nav_screen.dart` import it. This is a mechanical move (cut/paste +
rename + 2 import-line updates in the two call sites) — no behavior change
for the home screen.

**Does nav have the 3-course data today?** No — `nav_screen.dart` only ever
carries the single selected route (`_routePoints`, `_maneuvers`,
`_durationMin`). But the plumbing to get all 3 already exists and is
reachable from nav:
- `RoutingService.fetchRoutes(origin, destination, waypoints)` —
  `routing_service.dart:131` — **always returns all 3 costed routes** in one
  call (index 0=시골길, 1=지방도로, 2=국도; `routing_service.dart:83`
  comment). `nav_screen.dart`'s own `_reroute` (`:356-360`) already calls
  this and gets all 3 back, but only reads `routes[selIdx]`
  (`nav_screen.dart:362-363`) and discards the other two.
- `mapInteractionProvider` (`map_providers.dart`) is the **same shared
  Riverpod provider** already imported and read/written by `nav_screen.dart`
  (`:23`, and used at `:362` for `selectedRouteIdx`). It already has
  `setAllRoutes` (`:199-200`), `setAllRouteMeta` (`:202-203`), and
  `setSelectedRouteIdx` (`:205-206`) — exactly what `main_map_screen.dart`'s
  home-screen course sheet uses. Nav can call the same setters; no new
  provider state is needed.
- Fun-score metadata for the cards (`windingScore`) comes from
  `NativeEngine.scoreFunV2(points)` (`main_map_screen.dart:711`,
  `services/native_engine.dart` — not yet imported in `nav_screen.dart`, one
  import line to add).

So: nav can call `RoutingService.fetchRoutes` from the current position
(same as `_reroute` does, including its offset-origin logic at
`nav_screen.dart:352-354` to avoid snapping behind the rider), then
`notifier.setAllRoutes(...)`/`setAllRouteMeta(...)` exactly like
`main_map_screen.dart:698-732` (`_fetchAndStoreAllRoutes`), and render the
extracted `CourseSheet` with that data. **Nav does not need its own
sheet** — one shared widget, fed by the same provider, is sufficient and
keeps the two screens visually consistent for free.

---

## 5. Wiring course pick → re-navigate

`_reroute`'s current signature: `Future<void> _reroute(LatLng origin, {bool
silent = false})` (`nav_screen.dart:336`). It does **not** take a course
index — internally it always resolves the course via
`ref.read(mapInteractionProvider).selectedRouteIdx` (`:362`), clamped to the
freshly-fetched `routes.length`. This mirrors exactly how
`main_map_screen.dart`'s `_startNavigation` (`:822-823`) picks a route: by
reading `selectedRouteIdx` off the same provider, not via a parameter.

**Implication**: course selection can feed `_reroute` with **zero signature
changes** — the caller just needs to call
`ref.read(mapInteractionProvider.notifier).setSelectedRouteIdx(chosenIdx)`
before invoking `_reroute(currentPos)`, same as home's
`_onRouteCardSelect` (`main_map_screen.dart:842-850`) does for its own
selection flow. This is the simplest wiring and requires no changes to
`_reroute` itself.

**However**, that naive path double-fetches: once to populate the sheet's 3
cards (distance/time/fun-score), and again inside `_reroute` after the user
picks (since `_reroute` always re-calls `RoutingService.fetchRoutes`). Given
mid-ride GPS drift over the seconds spent choosing, a second fetch from a
*newer* origin is arguably correct behavior (not wrong) — but it does mean
one extra Valhalla round-trip and the user briefly sees stale card metadata
if they linger.

**Recommended (slightly more work, avoids double-fetch and staleness)**:
1. On 재탐색 tap: fetch all 3 routes once (§4), store via
   `setAllRoutes`/`setAllRouteMeta`, keep the raw `List<RouteResult>` in a
   local nav field (mirrors `main_map_screen.dart`'s `_fetchedRoutes` at
   `:723` — nav has no equivalent field yet, needs adding).
2. Course-card taps (`onSelect`) only flip `setSelectedRouteIdx` + recolor
   the route line from the already-fetched polylines (mirror
   `_onRouteCardSelect`/`_recolorRouteLayer`, `main_map_screen.dart:842-850`,
   `:308-...`) — no network call, instant.
3. Sheet confirm (`onStart`/slider) applies the already-fetched
   `RouteResult` for the selected index directly — i.e. factor out the
   "apply a fetched route" tail of `_reroute` (`nav_screen.dart:361-377`:
   `_routePoints = newPoints; _durationMin = ...; _applyRouteGuidance(...);
   setGeoJsonSource(...)`) into a small `_applyChosenRoute(RouteResult)`
   helper, call it directly with the stored route — bypassing a second
   `fetchRoutes` call entirely. `_reroute` itself is left untouched for the
   existing off-route/auto-reroute path.
4. Either way, also exit overview mode (`_isManualMode`/new
   `_showCourseSheet` flag → false) and re-`_recenter` to follow-mode on
   confirm or on sheet dismiss.

---

## Summary

**(a) Bottom-card layout**: `ETA (Expanded) | divider | 재탐색 (new pill,
neutral color) | divider/spacing | 종료 (existing red pill)`, inserted at
`nav_screen.dart:1079-1080`. No Row restructuring needed — `Expanded` on the
ETA column absorbs the layout; just watch narrow-screen (~360dp) fit once
built.

**(b) Zoom-to-fit**: fully feasible, same `newLatLngBounds` API and bounds
math already proven twice in `main_map_screen.dart` (`:441-452`,
`:664-675`), applied to `_routePoints`. Do **not** reuse `_isManualMode` as-is
(its 10s auto-revert timer and banner are wrong for this flow, and it
doesn't gate the bearing-rotate camera call at `:236-238`); introduce a
dedicated `_showCourseSheet` bool (naming mirrors
`main_map_screen.dart:135`) and gate both `_recenter` and `bearingTo` calls
on it, clearing it explicitly when the sheet closes/confirms.

**(c) Course sheet reuse**: `_CourseSheet`/`_RouteInfo`/`_RouteCard`
(`main_map_screen.dart:1554-1666+`) are purely callback-driven with no
hidden `main_map_screen` state coupling and only public dependencies
(`courseLineColor`, `SliderStartButton`, `AppColors`) — extract to a shared
public widget file (e.g. `lib/core/widgets/course_sheet.dart`) and import
from both screens. Nav does not need a separate implementation.

**(d) Pick → re-navigate wiring**: `_reroute(LatLng origin, {bool silent})`
already resolves its course purely by reading
`mapInteractionProvider.selectedRouteIdx` (`:362`), so course-pick →
`setSelectedRouteIdx` → `_reroute` works with **no signature change** to
`_reroute`. Better: fetch once when 재탐색 is tapped, keep the 3
`RouteResult`s locally (new field, mirrors `main_map_screen.dart`'s
`_fetchedRoutes`), let card taps just recolor/select instantly, and apply
the chosen route directly on confirm via a small extracted
`_applyChosenRoute` helper (from `_reroute`'s existing apply-tail,
`:361-377`) — avoiding a redundant second Valhalla fetch.

**(e) Complexity estimate**:
- Remove old ↻ button + dead `_manualReroute`: **trivial** (~5 min).
- Bottom-card 재탐색 button UI: **small** (~30 min incl. disabled/loading
  states).
- Zoom-to-fit + new `_showCourseSheet` overview-hold flag (incl. gating
  `_recenter`/`bearingTo`, wiring enter/exit): **small-medium** (~1-2 hr;
  the two extra gate points at `:233`/`:236` are easy to miss).
- Extract `CourseSheet` to shared widget + repoint two files' imports:
  **small** (~45 min, purely mechanical, low risk since callback-only API).
- Fetch-3/store/apply-chosen wiring in nav (new local field, reuse
  `setAllRoutes`/`setAllRouteMeta`/`setSelectedRouteIdx`, extract
  `_applyChosenRoute`): **medium** (~1.5-2 hr; the fiddly part is exit/entry
  timing between overview-hold, sheet visibility, and resuming follow-mode
  cleanly without a visual jump).
- **Total**: roughly a half-day to a day of focused work, no architectural
  blockers found — all required plumbing (bounds-fit API, 3-course fetch,
  shared provider, callback-only sheet widget) already exists in the
  codebase today.
