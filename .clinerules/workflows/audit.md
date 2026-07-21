# Audit (Plan=Opus only, read-only)
You are auditing the change Act just produced. Do NOT modify code. Report only.

1. Run `git diff HEAD` and read the entire change.
2. Check violations against .clinerules/01-discipline.md:
   - One commit, one file, one logical change?
   - Any forbidden API (e.g. setLayerProperties)?
   - Any hardcoded announcement string?
   - Any dead code left behind (delete/rewrite principle)?
3. Judge: root-cause fix vs symptom patch. Back every point with a `file:line` citation.
4. Output PASS or REJECT with reasons, in Korean. If REJECT, leave fix instructions only and STOP — do not edit.