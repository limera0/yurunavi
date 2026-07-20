#!/usr/bin/env bash
# loop/run_night_auto.sh — 유루나비 야간 무인 실행: claude -p 틱 체인
#
# 하나의 긴 대화형 세션 대신, 짧고 독립된 claude -p 세션("틱")을 순서대로 여러 번
# 실행한다. 각 틱은 이전 틱의 대화 기록을 전혀 갖지 않고(--resume 안 씀),
# loop/.auto/handoff.md 를 통해서만 상태를 이어받는다.
# 배경: anthropics/claude-code#51164 — 큰 트랜스크립트 + 긴 단일 응답 조합이
# mid-stream ECONNRESET을 유발(자동 재시도 없음, "not planned"). 컨텍스트를 매번
# 작게 리셋하고, 틱 1회 벽시계 시간도 하드 타임아웃으로 못박아 두 트리거를 모두 회피.
#
# 사용법:
#   loop/run_night_auto.sh <task_file> [옵션]
# 옵션:
#   --max-ticks N              최대 틱 수 (기본 14)
#   --max-wall-seconds N       전체 실행 상한 초 (기본 37800 = 10.5시간)
#   --tick-timeout N           틱 1회 타임아웃 초 (기본 2700 = 45분)
#   --permission-mode MODE     claude -p 에 넘길 --permission-mode (기본 bypassPermissions)
#   --effort LEVEL             claude -p 에 넘길 --effort (기본 high)
#   --blocked-wait-seconds N   BLOCKED 상태에서 디스코드 답장 대기 상한 초 (기본 10800 = 3시간)
#
# 디스코드 연동 (.env, 없으면 조용히 생략):
#   DISCORD_WEBHOOK_URL     — 종료/BLOCKED 알림 발송용
#   DISCORD_BOT_TOKEN       — BLOCKED 답장 폴링용 (봇, 웹훅과 별개)
#   DISCORD_CHANNEL_ID      — 폴링할 채널
#   DISCORD_OWNER_USER_ID   — 이 유저 ID가 보낸 메시지만 답장으로 인정(보안)

set -uo pipefail
cd /data/projects/yurunavi || exit 1

# .env에 시크릿(DISCORD_WEBHOOK_URL 등) — 없어도 알림만 조용히 생략, 스크립트는 계속 진행
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# ---- 안전 점검 ----
if [ "$(id -u)" -eq 0 ]; then
  echo "FATAL: root/sudo로 실행 금지. 일반 계정에서 실행하세요." >&2
  exit 1
fi

TASK_FILE="${1:-}"
if [ -z "$TASK_FILE" ]; then
  echo "Usage: $0 <task_file> [--max-ticks N] [--max-wall-seconds N] [--tick-timeout N] [--permission-mode MODE] [--effort LEVEL]" >&2
  exit 1
fi
[ -f "$TASK_FILE" ] || { echo "FATAL: task file not found: $TASK_FILE" >&2; exit 1; }
shift

MAX_TICKS=14
MAX_WALL_SECONDS=37800     # 10.5h — ~12h 부재 시간에서 최종 리포트 틱용 버퍼 확보
TICK_TIMEOUT=2700          # 45min — 틱 1회 하드 타임아웃(ECONNRESET 회피 핵심)
PERMISSION_MODE="bypassPermissions"
EFFORT_LEVEL="high"
BLOCKED_WAIT_SECONDS=10800  # 3h — BLOCKED 상태에서 디스코드 답장 기다리는 상한

while [ $# -gt 0 ]; do
  case "$1" in
    --max-ticks) MAX_TICKS="$2"; shift 2 ;;
    --max-wall-seconds) MAX_WALL_SECONDS="$2"; shift 2 ;;
    --tick-timeout) TICK_TIMEOUT="$2"; shift 2 ;;
    --permission-mode) PERMISSION_MODE="$2"; shift 2 ;;
    --effort) EFFORT_LEVEL="$2"; shift 2 ;;
    --blocked-wait-seconds) BLOCKED_WAIT_SECONDS="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"

SCRATCH_DIR="loop/.auto"
LOG_DIR="$SCRATCH_DIR/logs"
HANDOFF_FILE="$SCRATCH_DIR/handoff.md"
TICK_PROMPT_FILE="$SCRATCH_DIR/tick_prompt.md"
mkdir -p "$LOG_DIR"

NIGHT_DATE="$(date +%m%d)"          # 밤 시작 시각 기준 1회 고정 — 자정 넘어가도 안 바뀜
RUN_LOG="$LOG_DIR/run_${NIGHT_DATE}_$(date +%H%M).log"

{
echo "=== run_night_auto start $(date) ==="
echo "task_file=$TASK_FILE max_ticks=$MAX_TICKS max_wall_seconds=$MAX_WALL_SECONDS tick_timeout=$TICK_TIMEOUT permission_mode=$PERMISSION_MODE effort=$EFFORT_LEVEL"

run_start_epoch=$(date +%s)
tick=0
no_progress_streak=0
stop_reason=""

morning_report_exists() {
  # 날짜만 보면 안 됨: 오늘 다른 작업으로 이미 쓰인 MORNING_REPORT_${NIGHT_DATE}_*.md가
  # 있을 수 있음(예: 낮에 별도 세션이 리포트를 남긴 경우). 이번 run 시작 이후에
  # "새로" 만들어진(또는 갱신된) 파일만 완료 신호로 인정한다.
  local f
  for f in loop/MORNING_REPORT_${NIGHT_DATE}_*.md; do
    [ -e "$f" ] || continue
    if [ "$(file_mtime "$f")" -ge "$run_start_epoch" ]; then
      return 0
    fi
  done
  return 1
}

handoff_status() {
  [ -f "$HANDOFF_FILE" ] && head -n5 "$HANDOFF_FILE" \
    | grep -oE 'STATUS: (CONTINUE|DONE|BLOCKED|STUCK)' | head -n1 | sed 's/STATUS: //'
}

file_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }

# 디스코드로 종료 알림 (베스트 에포트 — 실패해도 스크립트 흐름에 영향 없음).
# 웹훅 URL은 .env에서만 읽음, 로그에도 URL 자체는 남기지 않음.
notify_discord() {
  if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
    echo "notify_discord: DISCORD_WEBHOOK_URL 없음 — 알림 생략"
    return 0
  fi

  local report_file
  report_file=$(ls -t loop/MORNING_REPORT_${NIGHT_DATE}_*.md 2>/dev/null | head -n1)

  local payload
  payload=$(python3 - "$tick" "$stop_reason" "$RUN_LOG" "${report_file:-}" <<'PYEOF'
import json, sys

tick, stop_reason, run_log, report_file = sys.argv[1:5]

lines = [
    "🌙 유루나비 야간 자동화 종료",
    "",
    f"총 {tick}틱 진행, 멈춘 이유: {stop_reason}",
]

if report_file:
    try:
        text = open(report_file, encoding="utf-8", errors="ignore").read()
    except OSError:
        text = ""
    preview = text[:1200]
    lines.append("")
    lines.append(f"📄 {report_file}")
    lines.append("────────────")
    lines.append(preview)
    if len(text) > len(preview):
        lines.append("...(생략, 전체는 파일에서 확인)")
else:
    lines.append("")
    lines.append(f"⚠️ MORNING_REPORT 파일을 못 찾았습니다 — 로그 직접 확인: {run_log}")

content = "\n".join(lines)[:1900]  # 디스코드 메시지 2000자 제한 여유
print(json.dumps({"content": content}))
PYEOF
)

  if curl -sS --max-time 15 -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1; then
    echo "notify_discord: 전송 완료"
  else
    echo "notify_discord: 전송 실패 (네트워크 문제일 수 있음, 무시하고 계속)"
  fi
}

# BLOCKED로 멈췄을 때 "답장 기다리는 중" 알림 (최종 종료 알림과 별개, 웹훅 재사용).
notify_discord_blocked() {
  if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
    return 0
  fi
  local payload
  payload=$(python3 - "$tick" "$BLOCKED_WAIT_SECONDS" "$HANDOFF_FILE" <<'PYEOF'
import json, sys
tick, wait_s, handoff_file = sys.argv[1:4]
hours = int(wait_s) / 3600
try:
    text = open(handoff_file, encoding="utf-8", errors="ignore").read()
except OSError:
    text = ""
preview = text[:1200]
lines = [
    f"⏸️ tick {tick}: BLOCKED — 사람 판단 필요",
    f"이 채널에 답장하면 이어서 진행합니다 (최대 {hours:.1f}시간 대기, 안 오면 그냥 종료).",
    "",
    preview,
]
content = "\n".join(lines)[:1900]
print(json.dumps({"content": content}))
PYEOF
)
  curl -sS --max-time 15 -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" > /dev/null 2>&1
}

# 폴링용 봇 자격 3종이 다 있어야 동작 — 하나라도 없으면 BLOCKED 즉시 종료(기존 동작)로 폴백.
discord_polling_available() {
  [ -n "${DISCORD_BOT_TOKEN:-}" ] && [ -n "${DISCORD_CHANNEL_ID:-}" ] && [ -n "${DISCORD_OWNER_USER_ID:-}" ]
}

discord_latest_message_id() {
  curl -sS --max-time 15 -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    "https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages?limit=1" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d[0]['id'] if d else '0')
except Exception:
    print('0')
" 2>/dev/null || echo "0"
}

# $1 = 이 메시지 ID 이후의 메시지만 확인. DISCORD_OWNER_USER_ID가 보낸 것만 인정(보안 —
# 다른 사람이 채널에 뭘 써도 자동화에 영향 없게).
discord_poll_reply() {
  local after_id="$1"
  curl -sS --max-time 15 -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    "https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages?after=${after_id}&limit=50" 2>/dev/null \
    | python3 -c "
import sys, json
owner_id = '$DISCORD_OWNER_USER_ID'
try:
    msgs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(msgs, list):
    sys.exit(0)
mine = [m for m in msgs if m.get('author', {}).get('id') == owner_id and m.get('content')]
mine.sort(key=lambda m: m['id'])
if mine:
    print('\n'.join(m['content'] for m in mine))
" 2>/dev/null
}

# 반환: 성공(0)이면 stdout에 답장 텍스트, 실패(1)면 타임아웃.
wait_for_discord_reply() {
  local wait_seconds="$1"
  local since_id
  since_id=$(discord_latest_message_id)
  local deadline=$(( $(date +%s) + wait_seconds ))
  echo "wait_for_discord_reply: 대기 시작 (최대 ${wait_seconds}s)"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local reply
    reply=$(discord_poll_reply "$since_id")
    if [ -n "$reply" ]; then
      printf '%s' "$reply"
      return 0
    fi
    sleep 30
  done
  return 1
}

write_tick_prompt() {
  cat > "$TICK_PROMPT_FILE" <<PROMPT
너는 유루나비(YuruNavi) 프로젝트의 오케스트레이터다. 이건 밤새 반복 실행되는
자동화 체인의 "한 틱(tick)"이다(#${tick}번째). 이 세션은 방금 새로 시작됐고
이전 틱의 대화 기록이 전혀 없다 — 필요한 상태는 전부 파일에서 직접 읽어라.

## 먼저 읽을 것 (순서대로)
1. CLAUDE.md (이미 자동 적용됨, 그래도 한 번 확인)
2. 오늘 밤 작업 지시서: ${TASK_FILE}
3. 직전 틱이 남긴 진행 메모: ${HANDOFF_FILE} (없으면 오늘 밤 첫 틱 — 2번부터 시작)
4. 진짜 git 상태를 직접 확인해라: git log --oneline -10, git status.
   진행 메모의 "이미 했음" 서술을 그대로 믿지 마라 — 커밋 해시/타임스탬프로
   직접 검증해라 (git show -s --format='%ci %h %s' <hash>).
   작업 디렉토리가 지저분하면 이전 틱이 타임아웃으로 중단된 흔적일 수 있다 —
   완료할지 되돌릴지 네가 판단해라.

## 이번 틱에서 할 일
- 오늘 밤 작업 전체를 끝내려 하지 마라. 딱 한 개의 체크포인트 단위만 진행해라
  (대략: 코더 위임 1회 + 감사 1회 + 커밋 1회, 막혔으면 조사 후 보고로 대체).
- CLAUDE.md의 하드 룰을 그대로 따른다 (비밀 커밋 금지, 파괴적 명령 금지, push 금지,
  서브태스크 시작 전 체크포인트 커밋, PASS 후 커밋, 감사 최대 3회 반복 후 중단).
- 애매하면 추측하지 말고 멈춰라. 무인 실행이라 아침에 사람이 확인한다.

## 틱을 끝내기 전, 반드시 ${HANDOFF_FILE} 를 갱신해라
파일의 첫 줄은 반드시 아래 넷 중 정확히 하나 (자동화 스크립트가 이 줄을 그대로
파싱하니 형식을 지켜라, 다른 말 덧붙이지 마라):

STATUS: CONTINUE   ← 오늘 밤 작업이 아직 안 끝났음, 다음 틱이 이어감
STATUS: DONE       ← 오늘 밤 작업 전체가 끝났음
STATUS: BLOCKED    ← 사람 판단이 필요해 더 진행 불가
STATUS: STUCK      ← 같은 문제로 반복 실패, 더 시도해도 소용없음

STATUS: BLOCKED를 쓰면 그 아래 내용이 그대로 사람 폰 디스코드 알림으로 전송되고,
사람이 그 채널에 답장하면 다음 틱의 ${HANDOFF_FILE} 맨 아래에 "## 🙋 사용자 응답"
섹션으로 그 답이 그대로 붙어서 넘어온다. 그러니 BLOCKED일 때는 막연히 "막혔음"이라고만
쓰지 말고, 사람이 폰으로 봐도 바로 답할 수 있는 구체적인 질문(예/아니오, 또는 A/B 선택)
형태로 명확하게 적어라.

그 아래는 자유 형식(기존 loop/HANDOFF_*.md 관례처럼): 이번 틱에서 한 일(커밋
해시 포함) / 현재 git 상태 / 다음 틱이 이어받을 정확한 할 일(번호 매겨서) /
막히거나 애매했던 점.

## STATUS: DONE / BLOCKED / STUCK 이면 지금 바로 loop/MORNING_REPORT_${NIGHT_DATE}_<주제>.md 를 써라
- 대상 독자는 코드를 못 읽는 사람이다. 쉬운 말로, 뭐가 됐고 뭐가 막혔는지,
  검증 방법(커밋 해시/실행 방법)까지 적어라. 기존 loop/MORNING_REPORT_*.md 톤을 참고해라.
- STATUS: CONTINUE 면 MORNING_REPORT는 쓰지 마라 — 다음 틱이 이어간다.
PROMPT
}

write_final_report_prompt() {
  local reason="$1"
  cat > "$TICK_PROMPT_FILE" <<PROMPT
자동화 체인(loop/run_night_auto.sh)이 방금 멈췄다. 왜 멈췄는지 사람이 이해할
아침 보고서를 쓰는 것이 너의 유일한 임무다. 코드를 고치지 마라. 커밋하지 마라.
오직 보고서 파일만 써라.

## 읽어라
1. 오늘 밤 작업 지시서: ${TASK_FILE}
2. 마지막 진행 메모: ${HANDOFF_FILE} (있으면)
3. git log --oneline -20, git status
4. 자동화 스크립트가 멈춘 이유(참고, 사람 말로 풀어써도 됨): ${reason}

## 써라: loop/MORNING_REPORT_${NIGHT_DATE}_auto.md
- 오늘 밤 무엇이 진행됐는지(커밋 해시 나열, 검증 방법)
- 왜 여기서 멈췄는지
- 남은 것 / 다음 밤 추천 작업
- 코드를 못 읽는 사람이 읽는 보고서다. 쉬운 말로 써라.
PROMPT
}

while [ "$tick" -lt "$MAX_TICKS" ]; do
  elapsed=$(( $(date +%s) - run_start_epoch ))
  if [ "$elapsed" -ge "$MAX_WALL_SECONDS" ]; then
    stop_reason="전체 실행시간 상한(${MAX_WALL_SECONDS}s) 도달 (다음 틱 시작 전)"
    break
  fi

  tick=$((tick+1))
  write_tick_prompt

  head_before=$(git rev-parse HEAD)
  count_before=$(git rev-list --count HEAD)
  mtime_before=$(file_mtime "$HANDOFF_FILE")

  tick_log="$LOG_DIR/tick_${tick}_$(date +%H%M).log"
  echo "--- tick $tick start $(date) (timeout ${TICK_TIMEOUT}s) ---"

  tick_start_epoch=$(date +%s)
  timeout --signal=TERM --kill-after=60s "$TICK_TIMEOUT" \
    "$CLAUDE_BIN" --permission-mode "$PERMISSION_MODE" --effort "$EFFORT_LEVEL" -p --verbose \
    < "$TICK_PROMPT_FILE" > "$tick_log" 2>&1
  tick_exit=$?
  tick_elapsed=$(( $(date +%s) - tick_start_epoch ))

  head_after=$(git rev-parse HEAD)
  count_after=$(git rev-list --count HEAD)
  mtime_after=$(file_mtime "$HANDOFF_FILE")
  commits_made=$((count_after - count_before))
  handoff_updated="no"; [ "$mtime_after" -gt "$mtime_before" ] && handoff_updated="yes"
  status=$(handoff_status)
  dirty=""; [ -n "$(git status --porcelain)" ] && dirty=" [경고: 작업트리 dirty]"

  echo "tick $tick done exit=$tick_exit elapsed=${tick_elapsed}s commits=${commits_made} (HEAD ${head_before:0:7}->${head_after:0:7}) handoff_updated=${handoff_updated} status=${status:-NONE}${dirty} log=$tick_log"
  [ "$tick_exit" -eq 124 ] && echo "tick $tick: TIMEOUT (killed after ${TICK_TIMEOUT}s)"

  # ---- 정지 조건 1: 오늘 날짜 MORNING_REPORT 존재 ----
  if morning_report_exists; then
    stop_reason="MORNING_REPORT_${NIGHT_DATE}_*.md 작성됨 — 오늘 밤 작업 완료로 판단"
    break
  fi

  # ---- 정지 조건 2: STATUS 명시적 종료 ----
  case "$status" in
    DONE) stop_reason="tick $tick: STATUS: DONE"; break ;;
    STUCK) stop_reason="tick $tick: STATUS: STUCK"; break ;;
    BLOCKED)
      if discord_polling_available; then
        echo "tick $tick: STATUS: BLOCKED — 디스코드 답장 대기 시작 (최대 ${BLOCKED_WAIT_SECONDS}s)"
        notify_discord_blocked
        if reply=$(wait_for_discord_reply "$BLOCKED_WAIT_SECONDS"); then
          echo "tick $tick: 디스코드 답장 수신 — ${HANDOFF_FILE}에 반영 후 계속 진행"
          {
            echo ""
            echo "## 🙋 사용자 응답 (디스코드, $(date '+%Y-%m-%d %H:%M:%S'))"
            echo "$reply"
          } >> "$HANDOFF_FILE"
          continue
        else
          stop_reason="tick $tick: STATUS: BLOCKED — ${BLOCKED_WAIT_SECONDS}s 내 답장 없음"
          break
        fi
      else
        stop_reason="tick $tick: STATUS: BLOCKED (디스코드 봇 설정 없음 — 즉시 종료)"
        break
      fi
      ;;
  esac

  # ---- 정지 조건 3: 연속 무진전 2틱 (HEAD 불변 AND 커밋 0 AND handoff 갱신 없음) ----
  progress="no"
  [ "$head_after" != "$head_before" ] && progress="yes"
  [ "$commits_made" -gt 0 ] && progress="yes"
  [ "$handoff_updated" = "yes" ] && progress="yes"
  if [ "$progress" = "no" ]; then
    no_progress_streak=$((no_progress_streak+1))
  else
    no_progress_streak=0
  fi
  if [ "$no_progress_streak" -ge 2 ]; then
    stop_reason="연속 ${no_progress_streak}틱 무진전(HEAD 불변+커밋 없음+진행메모 갱신 없음) — 막힌 것으로 판단"
    break
  fi
done

# ---- 정지 조건 4/5: 틱 상한 또는 시간 상한으로 루프가 자연 종료된 경우 ----
if [ -z "$stop_reason" ] && [ "$tick" -ge "$MAX_TICKS" ]; then
  stop_reason="최대 틱 수(${MAX_TICKS}) 도달"
fi
[ -z "$stop_reason" ] && stop_reason="전체 실행시간 상한(${MAX_WALL_SECONDS}s) 도달"

echo "=== tick loop ended: $stop_reason ==="

# ---- 최종 보장 리포트 (틱 상한/스트릭 계산에 포함되지 않음) ----
if morning_report_exists; then
  echo "MORNING_REPORT_${NIGHT_DATE}_*.md 이미 존재 — 별도 리포트 틱 생략"
else
  echo "--- final report tick start $(date) ---"
  write_final_report_prompt "$stop_reason"
  timeout --signal=TERM --kill-after=30s 600 \
    "$CLAUDE_BIN" --permission-mode "$PERMISSION_MODE" --effort "$EFFORT_LEVEL" -p --verbose \
    < "$TICK_PROMPT_FILE" > "$LOG_DIR/final_report_$(date +%H%M).log" 2>&1
  if morning_report_exists; then
    echo "final report tick: MORNING_REPORT_${NIGHT_DATE}_*.md 작성 확인됨"
  else
    echo "WARNING: final report tick도 MORNING_REPORT를 못 남김 — 로그 직접 확인 필요: $RUN_LOG"
  fi
fi

notify_discord

echo "=== run_night_auto end $(date) === total_ticks=$tick stop_reason=[$stop_reason]"
} >> "$RUN_LOG" 2>&1
