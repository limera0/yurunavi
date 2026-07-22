#!/usr/bin/env bash
set -uo pipefail
cd /data/projects/yurunavi
LOG="/data/projects/yurunavi/night6_$(date +%Y%m%d_%H%M).log"
# at/cron은 PATH가 최소라서 claude/node 절대경로 필요할 수 있음. 아래 CLAUDE_BIN 확인.
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
{
  echo "=== night6 start $(date) ==="
  # ▼▼ 이 한 줄을 night1~5에서 실제로 동작했던 자율 실행 명령으로 맞춰줘 ▼▼
  "$CLAUDE_BIN" --permission-mode auto -p "NIGHT_TASK_6.md 를 읽고 그대로 수행해. STAGE마다 커밋. STOP 조건이면 추측하지 말고 MORNING_REPORT_night6b.md 기록 후 중단."
  # ▲▲ (비대화형 at 실행이라 -p 사용. 네 검증된 형태가 다르면 그걸로 교체) ▲▲
  echo "=== night6 end $(date) ==="
} >> "$LOG" 2>&1
