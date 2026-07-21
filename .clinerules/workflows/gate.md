# Commit Gate
1. Run `flutter analyze`. If any NEW error, stop and report. Do not commit.
2. Run `flutter test`. If not 51/51, stop and report. Do not commit.
3. Confirm the change is one file, one logical change. If not, propose splitting the commit.
4. Only if all pass: commit. Then run `git log --oneline -3` to confirm the commit actually landed.
5. If this is a T3 (behavior-changing) feature, explicitly state: "Ride verification required — hold main merge."

Report to the user in Korean.