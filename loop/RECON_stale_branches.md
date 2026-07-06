# RECON — 4 dangling branches (2026-06-17 ~ 06-26), stale-vs-main audit

Read-only recon. No branches touched, no checkouts (`git diff main <branch>` / `git log` / `git show` by name only).
Scope: `feat/arrival-fix`, `phase2/heading-fix`, `phase2/marker-fix`, `debug/fix-rate-probe` — 4 branches ahead of
`main` that are absent from the current HANDOFF chain. None of the 4 touch `rust/` (`git diff --stat main..<branch> -- rust/` empty for all four).

Method: for each branch, diffed the branch's **own** commits only (`git diff <merge-base> <branch> -- lib/ rust/`,
not `git diff main <branch>`, since `main` has moved ~substantially since these forked and a main-vs-tip diff is
dominated by unrelated main-side churn). Merge-base for `feat/arrival-fix`/`phase2/heading-fix`/`phase2/marker-fix`
is `4834134` (2026-06-24); for `debug/fix-rate-probe` it's `8dc7963` (2026-06-16).

Ancestry note: `phase2/marker-fix` (tip `1433c48`) is a **direct git ancestor** of `feat/arrival-fix` (its 4 commits —
`71dd93d`, `6af8d7b`, `6f9333d`, `1433c48` — appear verbatim in `git log main..feat/arrival-fix`). So the marker-swap
code is not independently duplicated between the two branches; `feat/arrival-fix` = marker-fix + 8 more commits.

---

## 1. `feat/arrival-fix` (HEAD `4332804`, 12 commits ahead)

Own diff vs merge-base (`git diff 4834134 feat/arrival-fix -- lib/`): 1 file, nav_screen.dart, +282/-151.
Four distinct pieces of functionality, each checked separately against current `main`:

### 1a. Destination/waypoint marker: FlutterMap overlay → MapLibre `Symbol`
Same change as `phase2/marker-fix` (inherited via ancestry, see above). **Superseded** — see §3 below for the
file:line evidence; conclusion is identical (main has its own, later, differently-structured native-Symbol
implementation and the `flutter_map` import is gone).

### 1b. Arrival trigger: straight-line 30m → route-remaining-distance + last-step condition
Branch `_checkArrival` (`git show feat/arrival-fix:lib/.../nav_screen.dart:558-581`): replaces a flat
`_distanceM(loc, dest) <= 30.0` check with `(_stepEndDistM.last - _traveledDistM(loc)) <= 20.0` gated on
`_stepIdx == _steps.length - 1`, plus a straight-line-20m fallback when step-distance data is unavailable.

**Superseded** by `main`'s `route_progress_provider.dart:141` — `final arrived = distToDest <= _kArrivalM;` where
`distToDest` (`route_progress_provider.dart:140`) is `_totalM - traveledM` (polyline-remaining distance, the same
underlying idea as the branch) and `_kArrivalM = 25.0` (`route_progress_provider.dart:46`). Consumed in
`nav_screen.dart:266-277` (`prog.arrived` → `_arrivalBannerVisible`/`_saidArrival`). Different threshold (25m vs
20m) and no separate "last step" gate, but the same design (route-remaining distance, not straight-line), already
in main, independently of this branch.

### 1c. Arrival TTS-once-guard + POI binding
Branch `_onArrivedHoldEntered` (`git show feat/arrival-fix:...:604-609`): `_arrivalAnnounced` flag guards
`speak('arrival')`, then `_fetchNearbyPois(dest)` binds into `_arrivalPois`.

**Superseded** by `main`'s equivalent, differently-named fields: `_saidArrival` (`nav_screen.dart:98`, guards
`speak('arrival')` at `nav_screen.dart:273-276`) and `_arrivalPois` (`nav_screen.dart:100`), populated via
`_fetchNearbyPois(widget.destination!)` at `nav_screen.dart:269-271`. Same behavior, different implementation.

### 1d. Geofence-gated manual exit ("지금 종료") — **NOT present in main in any form**
Branch adds (`git show feat/arrival-fix:...:98-104, 583-602, 1163`):
- `_kGeofenceM = 30.0`, `_kExitSpeedKmh = 30.0`, `_kExitBtnRadiusM = 8.0`, `_canExit` flag.
- `_checkArrivedGeofence(loc)`: while `arrivedHold`, if `dist > 30m` → **reverts phase to `guiding` and calls
  `_reroute(loc)`** (handles overshoot / false-positive arrival, e.g. rider doesn't actually stop at the pin and
  keeps riding). Otherwise sets `_canExit = dist <= 8m && speedKmh <= 30`.
- The exit button ("지금 종료") in the bottom panel is only rendered/tappable when `_phase == arrivedHold &&
  _canExit` (`...:1163`) — i.e. exiting nav is gated on being both close (≤8m) and slow (≤30km/h).

Checked `main`'s equivalent exit paths — both are **unconditional, no gate of any kind**:
- Arrival banner "종료" button: `nav_screen.dart:1024-1026`, `onTap: () => Navigator.of(context).pop()`.
- Bottom ETA-bar "종료" button (always visible, not just post-arrival): same unconditional
  `Navigator.of(context).pop()` pattern.
- `_confirmExit` (`nav_screen.dart:493`) exists but is wired **only** to the system back gesture via `PopScope`
  (`nav_screen.dart:915`), not to either in-UI exit button.
- No geofence/overshoot-revert logic anywhere in `nav_screen.dart` — `grep -n "geofence\|_canExit\|_ArrivalPhase"
  lib/features/navigation/presentation/nav_screen.dart` on main returns 0 hits.

So on `main`, tapping "종료" the instant the arrival banner appears ends navigation immediately regardless of
speed or actual proximity, and if the rider overshoots the destination while the banner is still showing, nothing
automatically un-latches the banner or reroutes — it just sits there until an unrelated off-route reroute happens
to reset it as a side effect (`_reroute()` clears `_arrivalBannerVisible`/`_arrived`/`_saidArrival` at
`nav_screen.dart:351-357`, but only when `_reroute` is invoked for some other reason).

Note on branch history: this geofence design is itself the *second* iteration — an earlier commit in this same
branch (`3de7887`, "ARRIVAL-C3") built a 10s auto-countdown-then-auto-`Navigator.pop()` "stopReady" phase, which
a later commit (`3afbd46`) explicitly replaced ("카운트다운 자동종료... 를 지오펜스 기반 수동 종료버튼으로 교체").
The diff read above is the branch tip, i.e. already the final, non-superseded design — not the discarded
countdown version.

**Verdict: KEEP-BUT-REVIEW.** §1a–1c are fully superseded by independently-evolved main code and can be discarded.
§1d (geofence + speed gated manual exit, auto-revert-to-guiding-and-reroute on 30m overshoot) is not implemented
in `main` in any form — main's exit buttons are unconditional taps with zero safety gate. This looks like a
deliberate, considered UX/safety behavior (guards against accidentally ending navigation while still moving, and
against a stale arrival banner if the destination point turns out unreachable/overshot), not a stale duplicate.
Recommend porting §1d on top of main's current arrival fields (`_saidArrival`/`_arrivalBannerVisible`/
`_arrivalPois`) rather than deleting the branch outright — do not guess the correct thresholds/UX without a
ride confirming main's current "instant-exit" behavior is actually fine as-is.

---

## 2. `phase2/heading-fix` (HEAD `1821607`, 6 commits ahead)

Own diff vs merge-base (`git diff 4834134 phase2/heading-fix -- lib/`): 2 files, 10 insertions / 1 deletion
(full diff read in this recon):
- `nav_screen.dart`: adds raw `_currentHeading` field, set unconditionally from `pos.heading` in `_onPosition`
  (no speed gate), passed as `heading: _currentHeading` into the `_reroute()` → `fetchRoutes()` call.
- `routing_service.dart`: adds optional `heading` param to `fetchRoutes()`; when non-null, sets
  `locations[0]['heading']` + fixed `heading_tolerance: 45`.

Checked against `main`'s current heading-reroute implementation, which is materially more advanced:
- `routing_service.dart:135-147` already has `originHeading`/`headingTolerance` (default **90**, not 45) params,
  serialized the same way (`'heading': ?originHeading`).
- `nav_screen.dart:363-374` (`_reroute`) already computes heading with a **speed gate** (`speedKmh > 2`) before
  passing it as `originHeading`, and additionally routes it through `_resolveHeading()`
  (`nav_screen.dart:524-531`), which **holds the last known heading during near-stop** (`speedKmh < 3`) instead of
  discarding it outright — a hysteresis the branch's raw `_currentHeading` field does not have (branch sets it
  unconditionally on every fix, no gating at all, and has no read-side speed check either — actually gates it
  only via the assignment order into `_reroute`, whereas main both gates AND holds-through-stops).
- Confirms task background: `feat/reroute-heading` (HEAD `c41859d`, **not** one of the 4 stale candidates, still
  active) builds its own increment directly on top of this exact main-side `originHeading`/`_resolveHeading` base
  — i.e. the maintained lineage for this idea is main + `feat/reroute-heading`, not this branch.

**Verdict: DELETE.** Fully superseded — main's own heading-reroute implementation (independently arrived at,
later) is a strict superset of what this branch adds: same parameter plumbing, plus a speed gate and a
stop-hysteresis this branch lacks, plus a wider tolerance (90 vs 45) that a currently-active branch is already
building further on top of.

---

## 3. `phase2/marker-fix` (HEAD `1433c48`, 4 commits ahead)

Own diff vs merge-base (`git diff 4834134 phase2/marker-fix -- lib/`): 1 file, nav_screen.dart, +59/-48 (full diff
read in this recon). Removes the `flutter_map` import and the `IgnorePointer(child: FlutterMap(...MarkerLayer...))`
overlay block (the one that didn't track the camera because `FlutterMap`'s `initialCenter` was set once and never
updated); adds `ml.Symbol? _destMarker` / `List<ml.Symbol> _waypointMarkers` with `_ensureDestMarker()`/
`_syncNavWaypointMarkers()`, wired into `_onStyleLoaded()` which nulls both and recreates via `addSymbol` every
time it fires.

Checked against `main`'s current implementation:
- `grep -n "flutter_map\|FlutterMap" lib/features/navigation/presentation/nav_screen.dart` → **0 hits**. The
  overlay is gone.
- Main has its own, later, differently-structured native-Symbol implementation:
  `_initDestLayer()` (`nav_screen.dart:678-696`) calls `addSymbol` once per waypoint/destination, guarded by a
  one-shot `_destLayerReady` flag, invoked from `_onStyleLoaded()`'s completion chain alongside
  `_initLocationLayer()` (`nav_screen.dart:649-661`), which uses a raw GeoJSON + `addSymbolLayer` with
  `iconRotationAlignment: 'map'` for the location puck (a deliberate upgrade over both the branch's `ml.Circle`
  puck and an earlier `addSymbol`-based puck — comment at `nav_screen.dart:646-648` explains `addSymbol`/
  `SymbolManager` can't set `icon-rotation-alignment`, only raw `addSymbolLayer` can).
- Both approaches achieve the same end goal (destination/waypoint markers as MapLibre-native `Symbol`s that
  project with the camera, not a screen-fixed FlutterMap overlay).

Minor design difference, noted for completeness only (not a reason to keep this branch): main's
`_destLayerReady`/`_locLayerReady` are one-shot guards that are never reset, whereas this branch's `_onStyleLoaded`
unconditionally nulls and recreates markers on every invocation. Main's nav screen does have a live style-reload
path (`ref.listen(mapLanguageProvider, ...)` at `nav_screen.dart:905-910`, which on a language change does
`setState(() => _styleJson = applyMapLanguageToStyle(...))`, changing `MapLibreMap.styleString` and re-firing
`onStyleLoadedCallback`) where the one-shot guards would skip re-adding symbols after a language-triggered style
reload during navigation. This is a possible latent gap in main's *current* code, but re-adopting this branch's
code would not cleanly fix it (would mean giving up the z-order/bearing-rotation puck upgrade main already has)
— flagging for visibility only, out of scope for this branch's verdict.

**Verdict: DELETE.** Core goal (remove screen-fixed FlutterMap overlay, replace with camera-following native
markers) is fully done in main via an independently-evolved, more refined implementation.

---

## 4. `debug/fix-rate-probe` (HEAD `2991a68`, 1 commit ahead)

Full content (`git show debug/fix-rate-probe -- lib/`): single line added to `_onPosition`
(`nav_screen.dart`, one-line diff):
```dart
debugPrint('YN_FIX t=${DateTime.now().millisecondsSinceEpoch} spd=${pos.speed} acc=${pos.accuracy}');
```
Commit message itself: *"THROWAWAY — debug/fix-rate-probe branch only, NEVER merge to main."*
`grep -rn "YN_FIX" lib/` on main → 0 hits (never merged, as intended).

Its stated job (`loop/RIDING_QUEUE.md:9`, `loop/BACKLOG.md:57-61`, task **INSTR-fixrate**): ride 2–3 minutes,
capture `YN_FIX` lines via `adb logcat -s flutter`, measure the interval (5s ⇒ OS Doze, 1s ⇒ code-level fix),
record the result against BACKLOG's **LOC-UNIFY** precondition, then discard the branch. Searched `loop/*.md` for
whether this was ever concluded another way:

- `loop/RECON_1hz.md` (2026-06-17, same day as this probe): root-causes the 5s interval via pure code analysis,
  **no ride needed** — `geolocator_android-5.0.2`'s `getPositionStream()` caches `_positionStream` as an instance
  singleton (`geolocator_android.dart:166-171`, quoted in the recon); `main_map_screen.dart:193-197`'s
  `LocationSettings` (no `intervalDuration` → Android default 5000ms) creates that cached stream first, so
  `nav_screen.dart:232-243`'s `AndroidSettings(intervalDuration: 1000ms)` is silently discarded on cache hit —
  nav_screen keeps receiving the stale 5s stream.
- `loop/BACKLOG.md:80`: LOC-UNIFY's precondition was updated same-day to *"없음 (RECON_1hz로 원인·설정값 확정
  2026-06-17)"* — i.e. the ride-measurement precondition was explicitly dropped once the code-level root cause
  was nailed down, without waiting on this probe branch's logcat capture.
- LOC-UNIFY subsequently shipped **and was ride-validated**: `git log` shows merge commit `abced22` —
  *"merge: LOC-UNIFY — 위치 단일화+워밍업+WAKE_LOCK (5초→1초·콜드스타트 해소 라이딩 검증)"* — the commit message
  itself states the fix was confirmed by a real ride to move the interval from 5s to 1s.
- `loop/HANDOFF_tts_arrival.md:3` (2026-06-24, a later session): *"LOC-UNIFY는 main 머지 완료(abced22)"* — confirms
  it's in main, not just a stale merge attempt.
- Current main structurally eliminates the root cause: `lib/features/map/providers/map_providers.dart:64-75`
  defines a single `locationStreamProvider` (`AndroidSettings`, `intervalDuration: 1000ms`, `distanceFilter: 0`),
  consumed by both `nav_state_provider.dart:62` and `splash_screen.dart:65-66` — there is no longer a second,
  settings-less `getPositionStream()` call that could win the singleton-cache race.

**Verdict: DELETE.** The question this probe existed to answer (is the 5s interval an OS/Doze artifact or a code
bug, and is it actually fixed) was independently resolved by code analysis the same day the probe was created,
and the fix (LOC-UNIFY) has since shipped to main and been ride-validated on a real ride (commit `abced22`,
2026-06-24). The probe's own literal task — capturing a `YN_FIX` logcat trace — may never have been executed, but
it is moot: nothing is left for it to prove, and its own commit message calls it a throwaway never meant for main.

---

## Summary

| Branch | HEAD | Verdict | Reason |
|---|---|---|---|
| `feat/arrival-fix` | `4332804` | **KEEP-BUT-REVIEW** | Marker + arrival-trigger + TTS/POI pieces superseded, but the geofence+speed-gated manual exit (§1d) has no equivalent in main — main's exit buttons are unconditional. |
| `phase2/heading-fix` | `1821607` | **DELETE** | Main's own `originHeading`/`_resolveHeading` reroute logic is a strict superset (speed gate + stop-hysteresis + wider tolerance); `feat/reroute-heading` already builds on that base. |
| `phase2/marker-fix` | `1433c48` | **DELETE** | Goal (FlutterMap overlay → camera-following native Symbol) fully done in main via a later, independently-evolved implementation; `flutter_map` import confirmed gone. |
| `debug/fix-rate-probe` | `2991a68` | **DELETE** | Underlying question already answered by code analysis (`RECON_1hz.md`) and fix already ride-validated in main (LOC-UNIFY, commit `abced22`); branch's own commit message calls it a throwaway. |
