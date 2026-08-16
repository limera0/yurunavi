---
name: yurunavi-flutter
description: Implement or modify YuruNavi Flutter/Dart code under lib/, including UI, Riverpod state, services, models, packages, and Flutter tests. Use for meaningful Dart implementation; do not use for Rust, documentation-only, or read-only audit work.
---

# YuruNavi Flutter Work

1. Read `.ai/ARCHITECTURE.md`, `.ai/WORKFLOW.md`, and `.ai/TESTING.md` completely. Read `.ai/REAL_DEVICE.md` only for device-dependent behavior.
2. Confirm one bounded goal and one primary module. Inspect current code, focused tests, Git state, and relevant `loop/WIKI_INDEX.md` entries.
3. Implement the smallest root-cause change. Preserve unrelated work. Never commit.
4. Respect MapLibre full-style reinjection, voice-pack wording, and Dart/Rust parity constraints.
5. Add or update focused tests for changed behavior.
6. Run focused tests and `flutter analyze`; run the complete Flutter suite when the checkpoint is ready.
7. Report changed files, exact results, remaining risk, and real-device status to the orchestrator.
