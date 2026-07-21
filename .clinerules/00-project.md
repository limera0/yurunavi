# YuruNavi — Project Context

## Stack
- Flutter 3.44 / Dart 3.12, Riverpod, MapLibre GL 0.26.1
- Valhalla 3.7 fork (port 8002), Rust scoring engine (port 8003)
- Server: westinx · Path: /data/projects/yurunavi · Repo: limera0/yurunavi

## Absolute Rules
- Always reply to the user in Korean. Instruction files are English; conversation is Korean.
- NEVER use `setLayerProperties` (MapLibre 0.26.1 `skipNulls:false` bug). Always re-inject full style JSON for any layer change.
- NEVER hardcode announcement/guidance strings. Use voice pack JSON.
- NEVER speculate. Every claim must be backed by a `file:line` citation. If you lack evidence, grep first.
- Reference implementations: OsmAnd (`RoutingHelper`), Organic Maps (`FollowedPolyline`). Solve in one attempt using verified references, not iterative guessing.