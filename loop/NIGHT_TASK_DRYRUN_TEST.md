# DRYRUN TEST — run_night_auto.sh 검증용 (실제 앱 코드는 절대 건드리지 말 것)

이건 새로 만든 `loop/run_night_auto.sh` 자동화 스크립트가 제대로 동작하는지
확인하기 위한 아주 작은 테스트 작업이다. 실제 야간 작업이 아니다.

## 할 일 (딱 이것만, 1틱 안에 끝날 만큼 작음)
1. 체크포인트 커밋 필요 없음(변경 없는 상태에서 시작).
2. 새 파일 `loop/DRYRUN_TEST_NOTE.md`를 만들고 아래 한 줄만 적어라:
   `run_night_auto.sh dry-run 검증 — <지금 날짜/시각>에 자동 생성됨.`
3. `flutter analyze` 실행해서 0 issues 확인 (코드를 안 건드렸으니 그대로 통과할 것).
4. `git add loop/DRYRUN_TEST_NOTE.md` 후 커밋: `test: run_night_auto.sh dry-run verification marker`
   (다른 파일은 절대 add/commit 하지 마라 — 지금 워킹트리에 이미 다른 미커밋 변경이 많다.)
5. `loop/.auto/handoff.md`에 `STATUS: DONE`으로 갱신.
6. `loop/MORNING_REPORT_<오늘날짜>_dryrun.md`를 짧게 써라(1~2문단이면 충분):
   무엇을 했는지, 커밋 해시, "이건 자동화 스크립트 자체를 검증하기 위한 더미 테스트였다"라고 명시.

## 건드리지 말 것
- lib/, rust/, 그 외 어떤 실제 앱 코드도 건드리지 마라.
- loop/DRYRUN_TEST_NOTE.md 외의 다른 파일을 add/commit 하지 마라.
- push 금지(원래 하드룰이지만 재확인).
