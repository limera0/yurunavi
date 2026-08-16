# Project Memory Routing

Dynamic truth priority:

1. Source code and tests
2. Current Git state and history
3. Current task/handoff
4. `loop/STATUS.md`
5. Indexed historical documents
6. Older narrative reports

## Entry points

- `loop/STATUS.md`: generated current-state entry point; never hand-edit.
- `loop/RELEASE_ROADMAP.md`: detailed human tracker; read only relevant line ranges.
- `loop/WIKI_INDEX.md`: search before new investigation; includes chronology, topics, and work history.
- `loop/.auto/handoff.md`: transient unattended-run state.
- `HANDOFF_*`: goals/instructions; `RECON_*`: factual investigation; `REPORT_*`: results; `MORNING_REPORT_*`: owner result and AI handoff.

Verify “already done” claims with `git log`/`git show`. Do not repeat completed work after a context reset. Factual RECON and audit findings cite `file:line`; owner summaries translate evidence into plain Korean instead of exposing citation noise.

Read-only requests must not create RECON/report files unless documentation writing is explicitly authorized. Run `loop/gen_status.sh` and `loop/curate_wiki.sh` only when their generated outputs are in scope.
