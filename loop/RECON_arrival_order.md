# RECON: 도착/부근 음성 순서 역전

RECON ONLY — no edits made.

## 1. Event keys

- `부근` (approaching) = template key **`destination_imminent`**
  `assets/voice_packs/default_ko.json:35` → `"목적지 부근입니다"`
  Produced by `VoiceEngine.onProgress` in `lib/features/navigation/voice_engine.dart:67`
  (`key = '${event}_$phase$suffix'` where `event='destination'`, `phase='imminent'`
  when `point == profile.imminentM`, see `voice_engine.dart:58-60`).

- `도착` (arrived) = template key **`arrival`**
  `assets/voice_packs/default_ko.json:10` → `"목적지에 도착했습니다"`
  Spoken directly (NOT through VoiceEngine's tier system) at
  `lib/features/navigation/presentation/nav_screen.dart:252`: `_vps?.speak('arrival');`

These are two structurally different pipelines: `destination_imminent` comes from
the generic maneuver-tier engine (`VoiceEngine`), `arrival` is a one-off hardcoded
call gated on `RouteProgress.arrived`.

`eventForType` mapping maneuver types 4/5/6 → `'destination'`:
`lib/features/navigation/voice_engine.dart:21`.

## 2. Thresholds — confirmed current values

- **부근 (`destination_imminent`) fires at `profile.imminentM` = 10m.**
  Source: `assets/config/guidance_profile.json:4` → `"imminent_m": 10`.
  This is a single **global** value (`GuidanceProfile.imminentM`,
  `lib/features/navigation/guidance_profile.dart:17,30,47`) appended to
  *every* event's tier point list, not just `destination`
  (`voice_engine.dart:50`: `final pts = [...tier.pointsM, profile.imminentM];`).
  There is no per-event imminent override in the schema — `destination` in
  `guidance_profile.json:44` has only `{"enabled": true}`, no `tiers` or
  `imminent_m` override, so it falls back to the same 10m as turns/ramps/etc.

- **도착 (`arrival`) fires when `RouteProgress.arrived` flips true, which is
  `distToDestM <= _kArrivalM` where `_kArrivalM = 25.0`.**
  Source: `lib/features/navigation/providers/route_progress_provider.dart:47`
  (`static const _kArrivalM = 25.0;`) and `:144`
  (`final arrived = distToDest <= _kArrivalM;`). This constant is a **hardcoded
  Dart literal**, not read from `guidance_profile.json` or any voice pack at all.

So: 부근 currently fires at 10m, 도착 at 25m — i.e. **도착's trigger radius (25m)
is larger than 부근's (10m)**. HANDOFF's expectation of 부근=50m/도착=8m has the
same shape (부근's radius > 도착's radius), but current code has it backwards in
magnitude relative to itself: the "closer" event (부근, 10m) is configured
smaller than the "farther" event (도착, 25m) should never happen — 25 > 10 means
as the vehicle's remaining distance shrinks monotonically from far to near, it
crosses 25m *before* it ever reaches 10m.

## 3. Why reversed — traced firing path

Both `distToDestM` (used for `arrived`) and `distToNextTurnM` (used for the
destination voice tier, since `destination` is the last maneuver and gets fed
as `d` in `onProgress`) are the same kind of monotonically-decreasing
polyline-remaining-distance metric, updated once per position fix in
`_advance()` (`route_progress_provider.dart:104-163`), and both are computed in
the same tick (`:141-144`) before the single `state = RouteProgress(...)`
assignment (`:155-162`) — so there is exactly one `RouteProgress` emitted per
fix, carrying both `distToNextTurnM` and `arrived` consistently.

The consuming listener in `nav_screen.dart:241-273` — call order per tick is:
1. `:249` `_handleVoice(prog)` → runs `VoiceEngine.onProgress` → would emit
   `destination_imminent` intent once `d <= 10`.
2. `:250-253` `if (prog.arrived && !_arrived)` → speaks `arrival` once
   `distToDestM <= 25`.

**This code order is actually correct** (voice-tier check before arrival
check) — hypothesis (c), tier evaluation order in the listener, is **not** the
cause; if both flags were true in the same tick, 부근 would already be queued
to `_tts` before 도착.

**Root cause is hypothesis (a): threshold magnitudes are inverted.** Because
`_kArrivalM` (25m) > `profile.imminentM` (10m), on the tick where remaining
distance first drops to ≤25m, `prog.arrived` becomes `true` and `arrival`
("도착했습니다") is spoken immediately (`nav_screen.dart:252`). The vehicle is
still 11–25m out at that point, so `destination_imminent` ("부근입니다") has
not fired yet — its own trigger point (`d <= 10`) is still several ticks in the
future. Only later, once distance drops further to ≤10m, does
`VoiceEngine.onProgress` finally emit the pending `destination_imminent`
intent (`voice_engine.dart:56-58`, `_pendingPoints` still holds `10` because it
was only cleared for points `< entryD` at step-entry, `voice_engine.dart:51`).
Result: 도착 is spoken first (~25m), 부근 second (~10m) — exactly the reported
reversal.

Hypothesis (b) (arrival computed from shape-index/snap reaching literal route
end, decoupled from straight-line distance) does **not** apply here — `arrived`
is derived from the same cumulative-polyline `distToDestM` metric
(`route_progress_provider.dart:143-144`), not a snap-index-reached-end
check, so it's on the same distance axis as the voice tiers, just with a
larger radius.

## 4. Configurability of desired thresholds (부근=50m, 도착=8m)

- 부근 side: **partially configurable today.** `imminent_m` in
  `guidance_profile.json:4` is read generically
  (`guidance_profile.dart:47`), so changing it to `50` would change 부근's
  trigger to 50m — **but this value is global**, shared by every maneuver
  type (turn/ramp/exit/roundabout/merge/keep/destination all append the same
  `profile.imminentM`, `voice_engine.dart:50`). Setting it to 50 would also
  push every turn/ramp/exit "imminent" utterance out to 50m, which is very
  likely not desired. To fix 부근 alone without collateral, the schema needs a
  per-event override, e.g. add `"imminent_m": 50` inside the `"destination"`
  block in `guidance_profile.json:44`, and extend `GuidanceProfile`
  (`guidance_profile.dart:16-84`) with an `eventImminentM` map (parsed
  alongside `eventTiers` at `:57-66`) plus a `imminentForEvent(event)` lookup,
  then have `voice_engine.dart:50` use `profile.imminentForEvent(event)`
  instead of the bare `profile.imminentM`.

- 도착 side: **not configurable at all today.** `_kArrivalM` is a private
  `static const` in `route_progress_provider.dart:47`, disconnected from
  `guidance_profile.json` / `default_ko.json` entirely — there is no key for
  it in either file. Per the project's no-hardcoded-TTS-distance rule, this is
  itself already a violation independent of the ordering bug. To make 도착=8m
  configurable it would need a new field (e.g. top-level `"arrival_m": 8` in
  `guidance_profile.json`) threaded into `RouteProgressNotifier` (it doesn't
  currently hold a `GuidanceProfile` reference at all — `setRoute`/`_advance`
  only take polyline/maneuver data, `route_progress_provider.dart:64-101`), so
  wiring this through is a bigger change than just editing a JSON number.

## 5. Coupling with arrival banner

`prog.arrived` is a **single boolean** that simultaneously drives both the
도착 voice line and the arrival banner — both gated on the exact same
`if (prog.arrived && !_arrived)` block:
`nav_screen.dart:250-256`:
```
if (prog.arrived && !_arrived) {
  _arrived = true;
  _vps?.speak('arrival');
  setState(() => _arrivalBannerVisible = true);
  _fetchNearbyPois(widget.destination!).then(...);
}
```
So they are **not independently tunable today** — moving `_kArrivalM` from
25m to 8m (to fix the voice-order bug) would also delay the arrival banner
(and the nearby-POI fetch trigger) from popping at 25m to popping at 8m. If
banner-at-25m is intentional/relied upon (recently touched per "banner
recently changed"), decoupling voice-arrival-distance from
banner-arrival-distance would require splitting `RouteProgress.arrived` into
two flags (or keeping one flag for banner and adding a second, tighter
distance check purely for the `arrival` speak call) rather than just changing
`_kArrivalM`.

## ROOT CAUSE

`도착` (`arrival`, spoken at `nav_screen.dart:252`) fires whenever
`RouteProgress.arrived` becomes true, which happens at
`distToDestM <= _kArrivalM` where **`_kArrivalM = 25.0`**
(`route_progress_provider.dart:47`, checked at `:144`). `부근`
(`destination_imminent`) fires from `VoiceEngine.onProgress` when the same
kind of remaining-distance value drops to `profile.imminentM = 10`
(`assets/config/guidance_profile.json:4`, consumed at `voice_engine.dart:50,58`).
Because **25 > 10**, as remaining distance monotonically decreases the 25m
arrival radius is crossed — and `arrival` is spoken — several meters/ticks
before the 10m imminent radius is ever reached, so `destination_imminent`
("부근") necessarily speaks *after* `arrival` ("도착"). The listener call
order in `nav_screen.dart` (`_handleVoice` at :249 before the arrival check at
:250) is already correct and not the cause; this is purely a threshold-value
inversion, compounded by the fact that the 도착 threshold (`_kArrivalM`) isn't
even in the same config file as the 부근 threshold (`imminent_m`) — one lives
in `guidance_profile.json`, the other is a hardcoded Dart constant in
`route_progress_provider.dart`, so there was no single place where their
relative ordering was ever visible/enforced.
