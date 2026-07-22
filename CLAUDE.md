# CLAUDE.md — YuruNavi Core Protocol

## Building
Motorcycle-tourer OSM navigation app. Flutter (UI) + Rust ("fun-road" curvature scoring, `native/`) + Valhalla (routing).

## Modules (actual paths)
- UI: `lib/features/{auth,map,navigation,route,settings,profile,tour_summary}`
- Shared: `lib/core`, `lib/services`, `lib/models`, `lib/providers`, `lib/widgets`
- Engine: `native/` (Rust + flutter_rust_bridge) — not `rust/`
- Infra: `docker/`

## System constraints
- Mode: `--permission-mode bypassPermissions` — direct execution authorized.
- Scope: locked to this repo (`yurunavi`). No external system changes.
- Efficiency: maximize autonomy, minimize overhead.

## Execution model — hybrid
- Daytime = unmanned: `loop/run_night_auto.sh` runs a chain of short, independent `claude -p` ticks.
- Evening = interactive steering: review day's report, set next goal.
- Each tick carries no prior chat — read state from task file + `loop/.auto/handoff.md`.
- Verify "already done" claims with `git log` / `git show`. One checkpoint per tick.
- Keep ticks short (context reset + per-tick wall-clock timeout) to avoid mid-stream ECONNRESET — do not merge into one long session.

## Claude's role — control-plane
- Delegate over direct coding: dev → flutter-coder / rust-coder; audit → code-auditor.
- Observe progress, decide next step. Big features: always delegate. Trivial edits only: direct.

## Hard rules (never violate)
- Never commit secrets. Keys in `.env` (gitignored).
- No destructive commands: `rm -rf`, `git push --force`, data drops, mass deletion.
- No remote push unless the task file says so.
- Never `git add -A` / `git commit -a` — stage named files only (`git add <file> …`). Concurrent sessions share the branch.
- Commit before each subtask (checkpoint) and after each PASS.
- One module per session. No scope creep.
- If unsure, STOP and write it in the report — do not guess.

## Work loop (goal → build → judge)
1. Goal gate (A): if scope is fuzzy, confirm goal with master (evening steering or Discord) before starting; pin it in `loop/HANDOFF_*.md`.
2. Break into small steps. Checkpoint commit.
3. Delegate to coder.
4. code-auditor. On FAIL, fix + re-audit (max 3, then STOP + report).
5. On PASS, commit. Next step.
6. Verdict (B): end in `loop/MORNING_REPORT_*.md` — done / passed / blocked / token note + one line `Goal: X / Met: yes·partial·no — reason`.
7. Wiki curation (C): periodic tick — subagent re-indexes `loop/RECON_*` + `REPORT_*` into `loop/WIKI_INDEX.md` (one-line hooks).

## Caution
- Build needs JDK21.
- Headless server: no `flutter run` → `flutter build apk --debug` → adb install.
- After pubspec version bumps, native build "cannot find symbol" → `flutter clean` + `pub get` first.

## Infra (detail in docker/INFRA.md)
- Public hosts: tiles `tiles.westinx.com` · routing `valhalla.westinx.com` · engine `navi.westinx.com` (localhost for local instrumentation).
- Tile server: tileserver-gl Docker (container `yurunavi-tiles`, port 8080, internal). config `/data/tiles/data/config.json`, data `korea.mbtiles`, fonts Noto Sans + Noto Sans CJK TC.
- Style: `assets/images/osm_liberty_yurunavi.json` (HTTPS public host).
- Public access depends on separate `/data/n8n-stack/` container `n8n_cloudflared` — do not touch from this repo.
- Release status source: `loop/RELEASE_ROADMAP.md` (BACKLOG.md goes stale).
- Map backlog: info density (style minzoom/filter), sun indicator misalignment, location/zoom buttons.
