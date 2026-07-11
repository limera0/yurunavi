EXECUTION — edit and commit. Branch feat/sharp-curve-voice, HEAD 922375f. Per RECON_sharp_curve.md. One logical change per commit. flutter analyze zero, flutter test green. Only voice_engine.dart + guidance_profile.json + default_ko.json + new test file.

=== s1: split sharp-curve events from normal turn events ===
RECON: voice_engine.dart:12-13 currently folds type 11(kSharpRight)/14(kSharpLeft) into the
same 'turn_right'/'turn_left' events as slight/moderate turns (9/10/15/16).
- `eventForType` (voice_engine.dart:10-24): change
  `case 14: case 15: case 16: return 'turn_left';` → keep 15/16 as `turn_left`, add
  `case 14: return 'sharp_turn_left';` (own case, order doesn't matter in a switch).
  `case 9: case 10: case 11: return 'turn_right';` → keep 9/10 as `turn_right`, add
  `case 11: return 'sharp_turn_right';`.
- `_profileEventKey` (voice_engine.dart:26-27): no change needed — sharp_turn_left/right are not
  prefixed with 'roundabout_' so they pass through unchanged as profile keys.
- `_fast` suffix condition (voice_engine.dart:62-66) intentionally NOT extended to sharp_turn_*
  (see RECON risk note) — leave the `event == 'turn_left' || event == 'turn_right'` check as-is.
commit s1: "feat(voice): split sharp-curve (45+) from normal turn events"

=== s2: guidance_profile.json + default_ko.json additions ===
- `assets/config/guidance_profile.json` events map: add `sharp_turn_left` and `sharp_turn_right`,
  each `{ "enabled": true }` (no custom tiers/imminent_m — falls back to top-level common tiers,
  same as turn_left/turn_right today; see RECON risk note on why timing is untouched).
- `assets/voice_packs/default_ko.json` templates: add 4 keys exactly as in RECON:
  `sharp_turn_left_approach`, `sharp_turn_left_imminent`, `sharp_turn_right_approach`,
  `sharp_turn_right_imminent` (see RECON proposal §3 for exact Korean strings).
commit s2: "feat(voice): sharp-curve slow-down voice templates (ko)"

=== s3: test coverage ===
New test file `test/voice_engine_sharp_curve_test.dart` (mirror existing
`test/voice_engine_test.dart` structure/imports):
- type 11 → event resolves to sharp_turn_right → speak key `sharp_turn_right_imminent` at
  imminent point (not `turn_right_imminent`).
- type 14 → event resolves to sharp_turn_left → speak key `sharp_turn_left_imminent`.
- type 9/10 still produce plain `turn_right_*` (regression guard — slight/moderate turn unchanged).
- type 15/16 still produce plain `turn_left_*` (regression guard).
- speedKmh ≥ 20 on a sharp_turn_* event does NOT produce a `_fast` suffixed key (confirms s1's
  intentional exclusion — construct GuidanceProfile fixture the same way voice_engine_speed_test.dart
  does, feed speedKmh=30 into onProgress for a type-11 step, assert key has no `_fast`).
commit s3: "test(voice): sharp-curve event split + fast-suffix exclusion coverage"

=== AFTER ===
git log --oneline -4 (paste).
flutter analyze (report), flutter test (report). Do NOT merge/build yet — report back first.
Desk-verifiable in full: this is pure event-routing + template text, no timing/tier change,
so no drive-only unknowns remain for THIS slice (unlike RECON's deferred tier-tuning note).
