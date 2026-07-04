EXECUTION — edit and commit. Branch feat/nav-ui-redesign, HEAD c8bfd14. Two marker changes per RECON_markers.md. PREREQUISITE: assets/images/arrow_puck.png must exist (md5 e2b7967ae09efc409a858bed7c526487) and pointer_red.png/pointer_yellow.png already exist. One logical change per commit. flutter analyze zero new, flutter test green. Only nav_screen.dart + pubspec (if needed).

=== g1: destination/waypoint pins → teardrop PIN IMAGES ===
RECON: main_map_screen.dart already does addImage+addSymbol with iconAnchor:'bottom' for pointer_red/yellow. Replicate that EXACT pattern into nav_screen.dart, replacing the CircleLayer approach in _initDestLayer (nav_screen.dart:666-698).
- Register images: addImage('dest_pin', pointer_red bytes), addImage('wp_pin', pointer_yellow bytes) via rootBundle load (mirror main_map_screen's loader).
- Destination: addSymbol(SymbolOptions(geometry: widget.destination, iconImage:'dest_pin', iconAnchor:'bottom', iconSize: appropriate)). Tip sits on coord via iconAnchor bottom.
- Waypoints: same with 'wp_pin' for each widget.waypoints entry.
- Remove the old dest/waypoint CircleLayer/source created in _initDestLayer. Keep puck separate (handled in g2).
- Confirm pubspec assets already include assets/images/ (RECON said yes); if pointer_*.png not declared, add. arrow_puck.png must be declared too.
commit g1: "feat(nav): destination/waypoint teardrop pin images (match planning screen)"

=== g2: user puck → rotating arrow (heading cone) ===
RECON: must use raw addSymbolLayer (GeoJSON SymbolLayer) with iconRotationAlignment:'map' + icon-rotate bound to heading. NOT addSymbol (SymbolManager can't set rotation-alignment). Need arrow_puck.png (now added).
- addImage('nav_arrow', arrow_puck bytes).
- Replace the puck CircleLayer (_navLocSourceId/_navLocLayerId from commits 9ef4f74/697971c) with a GeoJSON SymbolLayer: source holds a Point feature with a 'bearing' property; layer uses iconImage:'nav_arrow', iconRotate:['get','bearing'], iconRotationAlignment:'map', iconSize tuned so arrow ~ Naver scale, iconAnchor:'center'.
- Thread heading: _ensureLocationMarker currently takes no heading param (RECON wiring gap). Add heading param; call it with the SAME effectiveHeadingDeg snapshot already resolved per tick (commit 9f3e1fb _resolveHeading). Update the feature's bearing property each tick via setGeoJsonSource.
- When heading frozen (stopped, <3km/h from earlier C work), arrow holds last heading (effectiveHeadingDeg already does this).
- Z-order: pins below, arrow on top, both above route line. Preserve ordering.
- Double-rotation: RECON confirms safe — map bearing is single-source (rotateGesturesEnabled:false), icon-rotate with 'map' alignment cancels correctly. Do not add extra compensation.
commit g2: "feat(nav): rotating arrow location puck (original heading-cone)"

=== AFTER ===
git log --oneline -3 (paste).
flutter analyze (report), flutter test (report). Do NOT merge/build.
Note desk limits: pin images + arrow presence are desk/screenshot-verifiable at rest; arrow ROTATION accuracy needs a drive.