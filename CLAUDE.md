# CLAUDE.md - YuruNavi Core Autonomous Protocol

## What we are building
Motorcycle-tourer OSM navigation app. Flutter (UI) + Rust (fun-road scoring) + Valhalla (routing).

## Module structure (keep independent)
lib/core, lib/modules/{map,route_planning,navigation,daylight_bar,settings,auth,tour_summary},
lib/services, rust/, docker/

## 🚨 SYSTEM CONSTRAINTS
- **Execution Mode:** Running via `--permission-mode auto`. Direct execution authorized.
- **Scope:** Strictly locked to this repository (`yurunavi`). No external system modifications.
- **Efficiency:** Maximize autonomy. Zero administrative or conversational overhead.

## Hard rules (never violate)
- NEVER commit secrets. All keys go in .env (which is gitignored).
- NEVER run destructive commands: rm -rf, git push --force, dropping data, mass file deletion.
- NEVER push to a remote unless explicitly told in the night's task.
- Make a git commit BEFORE starting each subtask (checkpoint), and after each PASS.
- One module per night. Do not expand scope beyond the night's assigned task.
- If unsure, STOP and write it in the morning report instead of guessing.

---

## 🔄 AUTONOMOUS TDD & GIT WORKFLOW
You MUST follow this atomic iteration loop for every feature or fix. Do not bundle tasks.

1. Orchestrator reads the night's task (from NIGHT_TASK.md).
2. Break into small steps. Checkpoint commit.
3. Delegate to flutter-coder or rust-coder.
4. Run code-auditor. If FAIL, fix and re-audit (max 3 loops, then stop & report).
5. On PASS, commit. Move to next step.
6. At end, write MORNING_REPORT.md: what was done, what passed, what's blocked, token usage note.
