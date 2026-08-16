---
name: yurunavi-rust
description: Implement or modify YuruNavi Rust code under native/, including route scoring, GPS algorithms, Axum endpoints, ingestion binaries, Valhalla integration, and flutter_rust_bridge surfaces. Do not use for Flutter-only or audit-only work.
---

# YuruNavi Rust Work

1. Read `.ai/ARCHITECTURE.md`, `.ai/WORKFLOW.md`, and `.ai/TESTING.md` completely.
2. Confirm a bounded `native/` goal and inspect related callers, tests, and Git state.
3. Keep Valhalla responsible for routing graphs. Preserve Dart fallback parity when the same behavior exists there.
4. Implement the smallest stable root-cause change. Do not commit or modify unrelated work.
5. Add focused Rust tests, then run `cargo build` and `cargo test` from `native/`.
6. If a public contract changes, identify the exact Dart or deployment follow-up rather than silently expanding scope.
7. Report files, exact checks, compatibility impact, and remaining risk to the orchestrator.
