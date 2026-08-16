# Architecture and Project Constraints

## Runtime boundaries

- Flutter/Riverpod client: `lib/`
- Features: `lib/features/{auth,map,navigation,route,settings,profile,tour_summary}`
- Shared Dart: `lib/core`, `lib/services`, `lib/models`, `lib/providers`, `lib/widgets`
- Rust algorithms, Axum backend, ingestion binaries, FRB surface: `native/` — never `rust/`
- Routing graph and motorcycle costing: custom Valhalla fork
- Deployment: `docker/`; internal tools: `tools/`; tests: `test/`

Work in one module per session. Split legitimate cross-module work into independently verifiable checkpoints.

## Ownership and constraints

- Valhalla owns routing. Do not build a replacement routing graph in Dart or Rust.
- Dart `NativeEngine` currently mirrors some Rust behavior; keep both aligned while the fallback exists.
- Never use MapLibre `setLayerProperties` because the pinned fork has a `skipNulls:false` failure. Re-inject complete style JSON.
- Do not hardcode new guidance or announcement wording. Use voice-pack data.
- Fix root causes with the smallest scoped change; avoid unrelated refactoring.
- For navigation-following behavior, consult OsmAnd `RoutingHelper` and Organic Maps `FollowedPolyline` only when relevant; verify against current source rather than copying assumptions.
- Secrets belong in approved untracked environment configuration.

## External boundaries

Generated/build artifacts are not source: `build/`, `.dart_tool/`, `native/target/`, virtual environments, APKs, screenshots, ride evidence, and TTL exports.

Do not modify `/data/n8n-stack/`, the separate Valhalla checkout, production data, or another project without explicit scope. For infrastructure details load `docker/INFRA.md` only when needed.
