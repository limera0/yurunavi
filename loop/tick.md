EXECUTION — edit and commit. Branch feat/continue-straight-voice, HEAD 41c6056. Per RECON_voice_v2.md R4 (실증 완료, 2026-07-06 curl 계측: 285km/118maneuver 중 type8 0건, Valhalla 소스상 애매한 분기점에만 발생). One logical change per commit. flutter analyze zero, flutter test green. Only voice_engine.dart + guidance_profile.json + default_ko.json + new test file.

=== s1: map type 8 (kContinue) to 'continue' event ===
RECON: voice_engine.dart:10-25 `eventForType` currently has no case for 8, falls through to
`default: return null;` (silent).
- `eventForType` (voice_engine.dart:10-25): add `case 8: return 'continue';` (own line, any
  position in the switch — order doesn't matter).
- `_profileEventKey` (voice_engine.dart:28-29): no change needed — 'continue' is not prefixed
  with 'roundabout_' so it passes through unchanged as the profile key (matches existing
  `"continue"` entry already present in guidance_profile.json:46).
commit s1: "feat(voice): map Continue (type 8) to voice event"

=== s2: enable profile + add ko templates ===
- `assets/config/guidance_profile.json` (line 46): flip `"continue": { "enabled": false }` →
  `"continue": { "enabled": true }`. No custom tiers/imminent_m — falls back to top-level
  common tiers (same principle as sharp_turn_left/right: no real-ride timing evidence yet,
  don't invent new timing).
- `assets/voice_packs/default_ko.json` templates: add two keys, positioned near `keep_*` (both
  are "no-turn, still needs a word" categories):
  `"continue_approach": "{dist}미터 앞 직진"`,
  `"continue_imminent": "직진입니다"`.
  (Valhalla's own ko-KR locale uses terse "계속" — app convention elsewhere is the more explicit
  "{dist}미터 앞 X" / "X입니다" pattern, matching turn_left/turn_right style, so follow the app
  convention not Valhalla's.)
commit s2: "feat(voice): continue-straight voice templates (ko)"

=== s3: test coverage ===
New test file `test/voice_engine_continue_test.dart` (mirror `test/voice_engine_sharp_curve_test.dart`
structure/imports/fixture setup):
- type 8 → event resolves to 'continue' → with profile continue.enabled=true, speak key
  `continue_imminent` fires at the imminent point.
- type 8 with continue.enabled=false → onProgress returns no SpeakIntent for that key (profile
  gate regression guard).
- type 9/10/15/16 unaffected (regression guard — plain turn events still resolve, not swallowed
  by the new case 8 branch).
- type 22/23/24 ('keep') unaffected — confirms 'continue' and 'keep' remain distinct events with
  distinct templates, not merged.
commit s3: "test(voice): continue-straight event coverage + profile-gate regression"

=== AFTER ===
git log --oneline -4 (paste).
flutter analyze (report), flutter test (report). Do NOT merge into verify/ride-0706 yet — report
back first, then merge as 5th T3 branch into verify/ride-0706 for tomorrow's single consolidated
ride (per HANDOFF_0706_3.md 0순위/1순위 — user verifies once, tomorrow's early-morning commute).
Desk-verifiable in full: pure event-routing + template text + profile flag, no timing/tier
change. Residual unknown (record, don't block): type 8 occurred 0/118 in curl samples, so this
event may simply not fire during tomorrow's ride at all — that's expected, not a failure signal.
