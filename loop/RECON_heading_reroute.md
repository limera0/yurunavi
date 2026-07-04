# RECON — Reroute U-turn ignores travel heading

Read-only recon. No fixes applied. Valhalla tested live on `localhost:8002` (prod fork, motorcycle costing). Client code inspected via grep/read only.

## 0. What "the fork" actually is

`/data/projects/valhalla-src` is Valhalla `3.7.0` (`git describe` = `3.7.0`) with a **local diff limited to**:

```
 M proto/descriptors/options.proto     (+5 lines: class_factors, curvature_penalty, long_bridge_factor, long_tunnel_factor, span_min_length)
 M src/sif/motorcyclecost.cc           (+50 lines: fun-road costing knobs — curvature penalty, bridge/tunnel factor, per-class factor)
?? docker/Dockerfile.fork
```

`git diff 3.7.0 -- src/sif/motorcyclecost.cc proto/descriptors/options.proto` (full diff captured, see below) touches **only** `MotorcycleCost::EdgeCost` / `ParseMotorcycleCostOptions`. `src/loki/*` (location correlation, heading/type/radius handling), `src/thor/*` (path algorithm, U-turn costing), and `src/odin/*` (maneuver generation) are **untouched — byte-identical to upstream 3.7.0**.

**Implication:** every directional lever tested below (`heading`, `type`, `preferred_side`, `radius`, `minimum_reachability`, `exclude_polygons`) behaves exactly as it would on a stock, unmodified Valhalla 3.7.0 build. This is not a fork-specific bug — it is stock Valhalla location/costing behavior, and any fix has to work within that.

## 1. Does `heading` change the first maneuver? (re-verified on a concrete U-turn case)

Test route: `(37.569406, 126.977216)` → `(37.568884, 126.97722)`, motorcycle costing, on 세종대로/31 (Sejong-daero) in Seoul — a physically divided road, so this is a genuine U-turn-prone case (destination reachable only via a legal U-turn bay), not a synthetic one.

**A — no heading:**
```
curl -s http://localhost:8002/route --data '{"locations":[{"lat":37.569406,"lon":126.977216},{"lat":37.568884,"lon":126.97722}],"costing":"motorcycle","units":"kilometers"}'
```
→ maneuver[0] `type=1 "Drive north on 세종대로/31" len=0.045`
→ maneuver[1] `type=12 "Make a right U-turn to stay on 세종대로/31" len=0.575`

**B — heading=0 (matches actual travel direction, tolerance 45):**
```
curl -s http://localhost:8002/route --data '{"locations":[{"lat":37.569406,"lon":126.977216,"heading":0,"heading_tolerance":45},{"lat":37.568884,"lon":126.97722}],"costing":"motorcycle","units":"kilometers"}'
```
→ **identical**: maneuver[0] `type=1 "Drive north..." len=0.045`, maneuver[1] `type=12 U-turn len=0.575`

**C — heading=180 (opposite of travel, tolerance 45) and D — heading=180, tolerance=10 (tight):**
Both return the **exact same route**, including the same first maneuver `"Drive north"` — i.e. Valhalla starts you off in the direction 180° opposite the requested heading and doesn't even fail/reject despite `heading_tolerance:10`.

**Conclusion for (1): CONFIRMED — heading has zero measurable effect on this deployment**, at any tolerance, in either the matching or opposite direction, on a real U-turn-prone case. Prior RECON's finding stands.

## 2. Other directional levers (same origin/dest pair, one curl each)

| Lever | Request | First 2 maneuvers | Honored? |
|---|---|---|---|
| `type:"through"` on locations[0] | `{"lat":...,"type":"through"}` | identical to baseline (`Drive north` → `U-turn right`) | **No effect** |
| `preferred_side:"same"` | `{"lat":...,"preferred_side":"same"}` | identical to baseline | **No effect** |
| `radius:5, minimum_reachability:50` on origin | `{"lat":...,"radius":5,"minimum_reachability":50}` | identical to baseline | **No effect** (only one edge candidate here regardless) |
| `exclude_polygons` over the actual U-turn loop (`126.977–126.9773 / 37.5696–37.56995`) | small box drawn around the real median-break geometry (found via shape decode) | `{"error_code":442,"error":"No path could be found for input"}` | **Honored** — but as a hard fail, not a reroute-around. There's no other legal path once that bay is excluded, so it just breaks routing entirely rather than producing a "go around the block" alternative. |
| Larger forward offset: 80m | origin pushed 80m along heading 0 before calling `/route` (no heading param) | `Drive east on 종로/6` → `...` → still ends in `U-turn right` then `U-turn left` before arrival | **No improvement** — bigger offset just prepends a detour through side streets; the same two U-turns near the destination remain, because they're required by the destination's position relative to the median, not by the origin snap. |
| Larger forward offset: 120m | same, 120m | `Drive north 0.536km` → `U-turn left` → `U-turn left` → arrive | **No improvement** — same story, still 2 U-turns before arrival. |

**Conclusion for (2): the only lever this fork honors is `exclude_polygons`, and it's not usable as a live anti-U-turn fix** — it requires knowing the exact geometry of the U-turn bay in advance and, when that bay is the only legal way to reach the destination (common on divided roads), excluding it just returns "no path" instead of finding an alternative. `heading`, `type`, `preferred_side`, `radius`, `minimum_reachability`, and bigger client-side offsets all failed to change the outcome in every test above.

Caveat: in this specific test road (divided highway), the "U-turn" Valhalla proposes may be the objectively correct maneuver (crossing via a legal median break) rather than an illegal in-place reversal — increasing the offset distance doesn't remove it because it isn't an origin-snap artifact, it's dictated by where the destination sits relative to the carriageway. That doesn't fix the field symptom (a U-turn maneuver appears immediately after a moving-reroute), it just narrows where the actual defect has to be: it's not fixable by tweaking the `/route` request at all, on this Valhalla build.

## 3. Client reroute logic

**Origin offset + speed gate** — `lib/features/navigation/presentation/nav_screen.dart:296-301`
```dart
final navState = ref.read(navStateProvider);
final heading = (navState != null && navState.speedKmh > 2) ? navState.headingDeg : null;
debugPrint('YNAV_REROUTE hdg_src spd=${navState?.speedKmh} rawHdg=${navState?.headingDeg} used=$heading');
final off = offsetOrigin(origin.latitude, origin.longitude, heading, 40);
```
`offsetOrigin` itself (`lib/features/route/offset_origin.dart:8-15`) just early-returns the unmodified `(lat, lng)` when `headingDeg == null` — so at `speedKmh <= 2` the offset is a no-op and Valhalla gets the raw current position as origin, free to snap onto whichever edge (including one behind current position).

**Why a valid `rawHdg` is discarded when stopped** — `lib/features/navigation/providers/nav_state_provider.dart:128-144`:
```dart
final double d = (pos.speed.isNaN || pos.speed < 0) ? 0.0 : pos.speed;
...
_speedKmh = _moving ? d * 3.6 : 0.0;
_pos = loc;
_headingDeg = pos.heading >= 0 ? pos.heading : null;
```
`_headingDeg` is set unconditionally from `pos.heading` (the platform GPS "course over ground") on every fix, independent of `_moving`/`_speedKmh` — it is **not** cleared when the rider stops. That's why the log shows `rawHdg=278 used=null` at `spd=0`: the field is just the last GPS-reported course, still populated, but `_reroute`'s `speedKmh > 2` gate (line 297) throws it away before use.

The gate itself is a defensible-but-blunt heuristic: GPS course-over-ground is derived from consecutive position deltas, so at near-zero speed it's dominated by GPS position noise rather than actual travel direction, and can flip wildly fix-to-fix. The gate doesn't distinguish "genuinely stale/noisy heading" from "rider slowed/stopped 1 second ago and this heading is still trustworthy" — it just always nulls heading below 2 km/h, which is exactly the state a rider is in right after passing a destination and slowing to a stop. Combined with §1/§2 (heading has no effect on this Valhalla build anyway), nulling it changes nothing about whether a U-turn appears, but it does remove the only input the 40m `offsetOrigin` push relies on, so the origin point doesn't move at all — origin stays exactly on the passed-destination edge, maximizing the chance Valhalla snaps onto the backward-facing edge.

**Reroute trigger / debounce / stutter** — `lib/features/navigation/presentation/nav_screen.dart:230-235, 278-285` and `route_progress_provider.dart:46,124`:
```dart
if (prog.offRoute) {
  _triggerReroute();
} else {
  _offRouteDebounce?.cancel();
  _offRouteDebounce = null;
}
...
void _triggerReroute() {
  if (_isRerouting) return;
  _offRouteDebounce ??= Timer(const Duration(seconds: 3), () {
    _offRouteDebounce = null;
    final current = ref.read(navStateProvider)?.pos;
    if (current != null) _reroute(current);
  });
}
```
`offRoute` itself is a stateless perpendicular-distance check (`route_progress_provider.dart:124`, `bestPerp > _kOffRouteM (50.0)`) recomputed on every position fix — no hysteresis, no minimum on-route hold time. The only debounce is the 3-second one-shot `_offRouteDebounce` timer, and it is fully torn down (`= null`) the instant `offRoute` flips false even momentarily, and also fully consumed (fires once, sets itself back to `null`) the instant it fires. There is **no cooldown after a completed reroute** — `_isRerouting` only guards against overlapping in-flight fetches, and resets to `false` in the `finally` block (line 328) the moment the previous fetch returns.

Root cause of the "3+ pass" stutter: each `_reroute()` call (per §1/§2) can itself return a route whose very first maneuvers point the rider further away from where they currently are (e.g. "drive forward 45m, then U-turn") — see the divided-road case above. If the rider doesn't follow that geometry (e.g. keeps riding past the point where the U-turn bay was, or just stays stopped past the corridor), `bestPerp` exceeds 50m against the *new* route almost immediately, `offRoute` flips true again, a fresh 3s timer starts, and `_reroute()` fires again — computing yet another "forward-then-U-turn" route from the rider's now-further-forward position. Nothing in this loop converges: each pass is an independent recompute with no memory of prior attempts, no growing debounce/backoff, and no counter to detect "we've rerouted N times in the last M seconds without going on-route" and fall back to a different strategy (e.g. holding the previous route, widening the corridor tolerance, or forcing a stationary re-anchor).

## Answers

**(a) Which directional lever does the fork actually honor?** None of the location-hint parameters (`heading`, `type`, `preferred_side`, `radius`, `minimum_reachability`) changed the first maneuver in any test, matching or opposing the real travel direction, tight or loose tolerance. Only `exclude_polygons` is honored, but it's a hard exclusion (produces "no path" rather than a routed-around alternative) and requires advance knowledge of the U-turn bay's geometry — not usable as-is for a live "forbid backward edge" fix. This matches stock Valhalla 3.7.0 behavior; the local fork diff never touches `loki`/`thor`/`odin`, only `MotorcycleCost` fun-road scoring.

**(b) Why does stopped-state discard a valid `rawHdg`?** `nav_state_provider.dart:144` always records `pos.heading` (GPS course-over-ground) regardless of speed, so the value is still populated at `spd=0`. But `nav_screen.dart:297`'s `speedKmh > 2` gate unconditionally nulls it before use in `_reroute`, on the reasoning that GPS course-over-ground is noise-dominated at near-zero speed. That heuristic doesn't special-case "rider just slowed down 1s ago, heading is still meaningful" — and since heading has no routing effect anyway (§1), nulling it just means `offsetOrigin` becomes a no-op and the origin never moves off the passed-destination edge.

**(c) Root cause of 3+ pass stutter?** No cooldown/backoff after a completed reroute — only a one-shot 3s pre-fetch debounce that's fully reset every time `offRoute` toggles. Each reroute can return a route that itself requires the rider to move further before turning around (a real Valhalla U-turn-bay maneuver), and if the rider's actual movement doesn't match that geometry, the 50m corridor check (`route_progress_provider.dart:124`) flips `offRoute` true again almost immediately, re-arming the 3s timer and firing another independent `_reroute()` call with no memory of the prior attempts.
