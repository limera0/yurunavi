# Commit Discipline

- One commit = one file = one logical change. Never bundle multiple files or concerns.
- At EVERY commit boundary: `flutter analyze` (0 new errors) AND `flutter test` (51/51) must pass. No exceptions.
- Prefer deleting and cleanly rewriting over preserving dead code. Fix root causes, never symptom patches.
- T3 rule: any behavior-changing feature requires ONE real-device ride verification before merging to main. Never auto-merge T3 work, regardless of passing automated gates.
- One branch per riding session. Never mix branches in a single session; merge each to main individually.
- Do not bypass stop gates when given multi-step tasks. Complete one phase, then stop and wait.