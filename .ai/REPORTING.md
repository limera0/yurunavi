# Reporting and Handoff

Owner-facing output is concise, plain Korean and starts with:

```text
오늘 목표: <one sentence>
결과: <product outcome>
검증: <completed evidence>
남은 일: <none or one clear item>
내가 확인할 것: <none or minimum human observation>
다음 추천: <one highest-value next task>
```

If blocked, add verified facts, product impact, the AI recommendation, and one minimal question. Do not expose raw logs unless requested.

## Tick handoff

The first line of `loop/.auto/handoff.md` is exactly:

- `STATUS: CONTINUE` — a safe next checkpoint is known;
- `STATUS: DONE` — goal and applicable automated verification are complete;
- `STATUS: BLOCKED` — genuine owner/external input is required;
- `STATUS: STUCK` — three bounded repair/audit attempts failed.

Record completed work and commits, exact verification, owned dirty files, and the next step.

## Morning report

For DONE/BLOCKED/STUCK create `loop/MORNING_REPORT_<date>_<topic>.md` with `## 1분 요약` using the owner format, the required goal verdict, then `## AI 인수인계` containing files, commits, exact checks, real-device state, risks, and next step.
