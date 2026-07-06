EXECUTION — rebase validated #5 TTS-audibility fix (originally on stale `feat/tts-audibility`,
44 commits behind main, unrebaseable cleanly) onto current main. Branch `feat/tts-audibility-v2`.
Only 2 functional one-line changes, both already verified against flutter_tts 4.2.5 source by
prior RECON (`loop/RECON_tts_volume.md`, cherry-picked from `33aa6d4`). No new design decisions —
this is a clean re-apply, not new RECON.

=== s1: bring forward RECON_tts_volume.md (docs only) ===
cherry-pick 33aa6d4 as-is.
commit s1: (keep original message) "docs: TTS 볼륨 가청성 recon (usage/focus 미설정 확인)"

=== s2: route speech to navigation audio usage ===
`lib/features/navigation/presentation/nav_screen.dart` `_initTts()` — after `setVolume(1.0)`,
add `await _tts!.setAudioAttributesForNavigation();` (flutter_tts 4.2.5 API, confirmed at
flutter_tts.dart:665-666 in RECON). Routes TTS to `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` stream,
separate from media volume.
cherry-pick 07feb5b, resolve any context-line drift manually (44 commits of divergence since
original commit — same file, same function, expect trivial offset only).
commit s2: (keep original message) "feat(tts): route speech to navigation audio usage (#5)"

=== s3: request audio focus + ducking on speak ===
`lib/services/voice_pack_service.dart` — `await _tts.speak(text);` → `await _tts.speak(text,
focus: true);`. Requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` so background media (music etc.)
ducks when TTS speaks.
cherry-pick 98b71b0.
commit s3: (keep original message) "feat(tts): request audio focus + ducking on speak (#5)"

=== s4: refreshed report ===
New `loop/REPORT_tts_audibility.md` (old one at `6793b08` referenced the stale branch/commit
hashes — rewrite with current hashes, same riding checklist, note this is a rebase not new work).
commit s4: "docs(tts): refresh audibility fix report on rebased branch (#5)"

=== AFTER ===
git log --oneline -5 (paste). flutter analyze (expect 0 — main already clean after `d9d78d5`
cherry-pick this session). flutter test (expect all green, no new tests — RECON already
established audio focus/usage is platform-channel-only, not unit-testable; existing voice tests
must stay green since VoicePackService.speak signature is unchanged, only call-site arg added).
Do NOT merge into main yet (T3, pre-ride). After PASS here, merge into `verify/ride-0706` as the
6th branch per user instruction (2026-07-06): "TTS까지 진행하자. 내일 퇴근 때 한 번에 싹
검토하지 뭐" — one consolidated APK, one ride, tomorrow (2026-07-07) early-morning commute.
Old `feat/tts-audibility` branch left untouched (superseded, not deleted) — it also carries 3
unrelated docs-only commits (private-land route avoidance / gate-tagging POC / overlay pipeline
recon) that are out of scope for this task; flag separately, do not pull into this branch.
