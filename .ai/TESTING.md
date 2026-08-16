# Testing and Build Policy

Choose checks by changed surface; do not run irrelevant expensive checks without reason.

## Flutter/Dart

- Run focused tests for changed behavior.
- Run `flutter analyze`.
- Before a commit containing Dart behavior, run the current complete `flutter test` suite unless the task documents a justified narrower gate.
- Never use a historical fixed test count as the success condition.

## Rust

From `native/`, run `cargo build` and `cargo test` for Rust changes.

## Cross-stack

Use `bash scripts/check_all.sh` when the change crosses client/backend/routing boundaries. Use `--skip-validate --skip-server` when external services are intentionally unavailable, and report skipped external checks separately from failures.

## Android and release

- Android builds require JDK 21.
- On the headless server use `flutter build apk --debug`, then adb install when a device is available; do not rely on `flutter run`.
- Release packaging uses `scripts/build_release.sh` and `env.json` when explicitly in scope.
- After relevant pubspec changes, native missing-symbol errors may require `flutter clean` then `flutter pub get`.

Load `.ai/REAL_DEVICE.md` whenever behavior cannot be proven by automated checks.
