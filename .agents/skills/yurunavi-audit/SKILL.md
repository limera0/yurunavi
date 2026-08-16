---
name: yurunavi-audit
description: Perform the required independent read-only audit of a meaningful YuruNavi implementation or refactor after coding. Use to judge goal fit, correctness, safety, tests, scope, and real-device gaps; never edit or commit.
---

# YuruNavi Independent Audit

1. Stay read-only. Read the goal, complete diff, and relevant `.ai/` policy only.
2. Verify the change addresses the root cause and matches the bounded goal.
3. Check imports/contracts, edge cases, secrets, destructive behavior, unrelated edits, dead code, and project-specific constraints.
4. Verify relevant check results; run safe read-only checks when evidence is missing.
5. Load `.ai/REAL_DEVICE.md` for behavior-dependent changes and state any pending gate.
6. Cite each factual finding as `file:line`. Return `PASS` or `FAIL` in concise Korean. On FAIL, list precise minimal corrections. Do not fix them.
