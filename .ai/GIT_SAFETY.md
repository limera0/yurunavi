# Git Safety for Concurrent Sessions

Sessions share the branch, working tree, and index. Existing changes may belong to someone else.

## Before work and commit

1. Run `git status --short`; identify owned files.
2. Inspect unstaged and staged diffs completely.
3. Never stage or alter unrelated changes.
4. Stage explicit filenames only.
5. Recheck `git diff --cached --name-only` and the staged diff.
6. Stage and commit together; do not leave files staged during a long wait.
7. Confirm the result with recent log and `git show`.

## Rules

- Never use `git add .`, `git add -A`, or `git commit -a`.
- One commit is one logical checkpoint; inseparable implementation and tests may share it.
- Never commit foreign staged work merely because it is present.
- Do not untangle concurrent work with reset, rebase, checkout, or force without explicit authority.
- No remote push unless the task explicitly authorizes it; never force-push.
- Checkpoint requirements never authorize committing unrelated dirty state.

Incident history: `loop/RECON_0805_git_index_collision.md` explains why these rules are strict.
