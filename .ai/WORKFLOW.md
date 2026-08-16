# Autonomous Workflow

## Planning

Maintain three levels:

- Long term: product vision and release stages; Product Owner controls direction.
- Medium term: release milestones, stability, ride-verification groups, relevant debt; use `loop/RELEASE_ROADMAP.md` selectively.
- Short term: one observable outcome per session/run. Unattended task files start with `GOAL: <one line>`.

Derive safe next steps from the approved priority and current state. Do not ask for routine continuation.

## Work cycle

1. Verify state and reuse prior investigation.
2. Define product-level completion and verification criteria.
3. Split into small checkpoints; keep one module per session.
4. Delegate substantial Flutter or Rust implementation.
5. Run focused and required broad checks.
6. Obtain an independent read-only audit.
7. On FAIL, issue a minimal fix, retest, and re-audit; stop after three failed cycles.
8. Perform only necessary in-scope refactoring and reverify.
9. Inspect the complete diff, then use `.ai/GIT_SAFETY.md`.
10. Update handoff/report using `.ai/REPORTING.md` and recommend the next valuable task.

Coders do not commit; the orchestrator verifies and commits. Continue while safe in-scope action remains.

## Short unattended ticks

`loop/run_night_auto.sh` runs independent Claude ticks with no chat memory. A tick reads its task, `loop/.auto/handoff.md`, Git evidence, and only relevant `.ai/` documents. Complete one investigation, one implementation/audit checkpoint, or final verification/report per tick. Leave factual continuation state before exit.

Use `CONTINUE`, `DONE`, `BLOCKED`, or `STUCK` exactly as defined in `.ai/REPORTING.md`.
