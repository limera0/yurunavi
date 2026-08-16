---
name: yurunavi-finish
description: Finish a YuruNavi checkpoint after implementation by verifying evidence, ensuring audit PASS, committing safely, updating handoff or morning report, and giving the Product Owner a concise Korean result. Use at completion or blocked handoff; not for implementation itself.
---

# Finish a YuruNavi Checkpoint

1. Read `.ai/GIT_SAFETY.md` and `.ai/REPORTING.md`; read `.ai/TESTING.md` for the changed surfaces and `.ai/REAL_DEVICE.md` when applicable.
2. Confirm the goal, owned files, focused/broad checks, independent audit verdict, and any device gate.
3. Fix nothing silently at this stage: route defects back through implementation, testing, and audit.
4. Inspect status and complete diffs. Stage explicit owned files only, commit one logical checkpoint, then verify the commit. Never push unless authorized.
5. Update the handoff and required report without overwriting generated status manually.
6. Report in the one-minute Korean format. Put technical details only in the AI handoff.
