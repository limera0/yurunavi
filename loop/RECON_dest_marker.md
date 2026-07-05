# RECON: destination pin stuck at pre-nav position

Read-only recon. No edits made.

## 1. Where the destination marker is drawn

`lib/features/navigation/presentation/nav_screen.dart:717-754` — the "임시 오버레이" block:
overlays a **second, separate map widget** (`flutter_map`'s `FlutterMap`, wrapped in
`IgnorePointer`) on top of the native `MapLibreMap`, purely to keep the old
`MarkerLayer`/`PolylineLayer` API until it's ported to GeoJSON symbol layers
(comment at :715-716 says the polyline part was already ported "커밋 ②", markers not yet).

```
717  IgnorePointer(
718    child: FlutterMap(
719      options: MapOptions(
720        backgroundColor: Colors.transparent,
721        initialCenter: ref.read(navStateProvider)?.pos ?? _kInitialMapView,
722        initialZoom: _navZoom,
723        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
724      ),
...
729      MarkerLayer(markers: [
730        ...widget.waypoints.map((wp) => Marker(point: wp, ...)),      // :730-742
743        if (widget.destination != null)
744          Marker(
745            point: widget.destination!,                               // :744-750  ← red pin
749            child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 38),
750          ),
751      ]),
```

**The coordinate the red pin is given (`widget.destination!` at :745) is correct** — it is
the same `LatLng` object passed in from `main_map_screen.dart` (see §2). The bug is not a
wrong coordinate value; it's that this `FlutterMap`'s own camera never moves after first
build, so the marker is *projected* to the wrong screen position.

## 2. Destination flow main_map_screen → nav_screen

- `main_map_screen.dart:595-599` `_applyDestination(dest, ...)` → `setDestination(dest, dist)`
  writes the tapped/picked point into `mapInteractionProvider`.
- `main_map_screen.dart:323-338` `_ensureDestMarker(dest)` draws the main-screen red pin as a
  **native MapLibre symbol** (`c.addSymbol`/`updateSymbol`), called from `_applyDestination`
  flow (:632).
- `main_map_screen.dart:753-756` `_startNavigation()`: `final dest = state.destination;` — same
  provider value, no transformation.
- `main_map_screen.dart:778-784` `NavScreen(destination: dest, waypoints: state.waypoints, ...)`
  — passed straight into the widget constructor.
- `nav_screen.dart:37,46` `widget.destination` stores exactly that value for the widget's
  lifetime (it's a `final` ctor field, never reassigned).
- `nav_screen.dart:331-343` `_reroute()` also reads `widget.destination` directly (`dest = widget.destination` at :331) and passes it to `RoutingService.fetchRoutes` — so **routing and
  the marker share the exact same coordinate value**. There is no second/cached copy of the
  destination anywhere in nav_screen (`grep` for `_dest`, `Symbol`, `destGeoJson` in
  nav_screen.dart returns nothing besides the FlutterMap marker itself).

So: no stale-provider / no wrong-source-of-truth bug. `widget.destination` is correct and
consistent everywhere it's read.

## 3. Is the coordinate ever fixed at init from camera/main-screen position?

No — `widget.destination` itself is never touched after construction. What *is* fixed at
init and never updated is the **FlutterMap overlay's camera** that renders the marker:

- `FlutterMap(options: MapOptions(initialCenter: ..., initialZoom: ...))` at
  `nav_screen.dart:718-723` has no `mapController:` argument, so flutter_map creates its own
  internal `MapControllerImpl` in `initState` and never re-seeds it from `initialCenter` on
  rebuild — confirmed in the package source,
  `flutter_map-8.2.2/lib/src/map/widget.dart:64-72` (`didUpdateWidget` only re-assigns
  `_mapController.options`, it does not move the camera even if `initialCenter` changes).
- Nothing in nav_screen ever calls a `MapController.move(...)` on this `FlutterMap` — there is
  no `MapController` field at all (`grep -n "MapController" nav_screen.dart` → no matches).
- Meanwhile `_recenter()` (`nav_screen.dart:510-550`), which runs on every `navStateProvider`
  tick to follow the bike, **only drives the native map**: `_mlCtrl?.animateCamera(update)` /
  `_mlCtrl?.moveCamera(update)` (:546,548), plus `_mlCtrl?.animateCamera(bearingTo(...))`
  at :227 for rotation. `_mlCtrl` is the `MapLibreMapController`, a completely different map
  instance from the `FlutterMap` overlay.

Net effect: the `FlutterMap` overlay's camera is captured once at first build — at
`ref.read(navStateProvider)?.pos` at that moment, i.e. essentially wherever the GPS/camera was
when navigation started (close to what main_map_screen was last showing) — and is then frozen
for the rest of the session while the real (native) map underneath pans, zooms and rotates.
Every `Marker` inside that `FlutterMap`'s `MarkerLayer` is screen-positioned relative to that
frozen camera, so visually it appears to stay "stuck" at the pre-navigation screen spot even
though `widget.destination` itself never changes and was always correct.

## 4. Red pin vs green puck

- Green puck: `nav_screen.dart:625-633` `_ensureLocationMarker()` → `c.setGeoJsonSource(_navLocSourceId, _buildLocGeoJson(p))` where `p = ref.read(navStateProvider)?.pos` — this
  writes into a **native MapLibre GeoJSON circle layer** (`_navLocLayerId`, created at
  `_initLocationLayer` :607-623) attached to `_mlCtrl`. It correctly rides the same camera that
  `_recenter` moves, so it tracks correctly (per C4, already fixed/verified).
- Red pin: reads `widget.destination` (correct value) but is rendered through the **separate,
  camera-frozen `FlutterMap` overlay** (§1/§3), so it visually desyncs from the native map as
  soon as `_recenter` starts moving/rotating `_mlCtrl`'s camera.

The asymmetry is the root of the bug: green puck moved from the old `flutter_map` overlay to a
native GeoJSON layer in commit `9ef4f74`/`0935f5d` ("raw-layer location puck above route line");
the destination/waypoint markers were never migrated off the old `FlutterMap` overlay, so they
kept the pre-migration camera-desync behavior that the puck used to have too.

## 5. Waypoints affected too?

Yes. `nav_screen.dart:730-742` — the waypoint markers (`Icons.location_pin`, amber, 34px) are
in the exact same `MarkerLayer` as the destination pin, subject to the identical frozen-camera
`FlutterMap`. Any waypoints will visually drift/stick the same way, just less noticeable since
routes commonly have zero waypoints.

## ROOT CAUSE

- **Wrong (visual) source:** the destination pin's *value* is right, but it is rendered inside
  the `FlutterMap` overlay at `nav_screen.dart:718-751`, whose own camera
  (`MapOptions.initialCenter/initialZoom`, :721-722) is set once at first build and never
  updated — no `mapController` is attached and nothing calls `.move()`/`.rotate()` on it. That
  frozen camera is what actually determines the marker's screen position, so it "sticks" at
  wherever the map was pointed at navigation start (≈ the pre-navigation / main-screen view).
- **Correct source (already used for the coordinate value, just needs the render side fixed):**
  `widget.destination` (`nav_screen.dart:37,745`), fed from `main_map_screen.dart:754-756,778-784` via `mapInteractionProvider.destination` — this value is correct throughout and is
  the same value `_reroute` uses for routing (`nav_screen.dart:331,343`).
- **Fix direction (not implemented — recon only):** move the destination/waypoint markers off
  the legacy `FlutterMap` overlay onto native MapLibre symbol/circle layers driven by `_mlCtrl`
  (the same pattern already used for the green puck, `_navLocSourceId`/`_navLocLayerId` at
  :607-633), the way the code comment at :715-716 already says is the plan ("② GeoJSON
  LineLayer로, ③ Circle/Symbol로 교체 후 이 블록 제거").
