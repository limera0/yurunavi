#!/usr/bin/env bash
# S1b 조사용 — PIP 왕복 반복 실험 스크립트 (커밋 대상, 회귀 재현에 재사용)
# usage: pip_repeat.sh <trigger> <rounds> <dwell_sec> <out_dir>
#   trigger: notif | appswitch | home
set -euo pipefail

TRIGGER="${1:-notif}"
ROUNDS="${2:-5}"
DWELL="${3:-3}"
OUTDIR="${4:-/tmp/pip_repeat}"
DENSITY=450
SCREEN=1080x2400

mkdir -p "$OUTDIR"

do_trigger_enter() {
  case "$TRIGGER" in
    notif)
      adb shell cmd statusbar expand-notifications
      sleep 1
      adb shell cmd statusbar collapse
      ;;
    appswitch)
      adb shell input keyevent KEYCODE_APP_SWITCH
      ;;
    home)
      adb shell input keyevent KEYCODE_HOME
      ;;
    *)
      echo "unknown trigger $TRIGGER" >&2; exit 1
      ;;
  esac
}

do_return() {
  adb shell am start -n com.westinx.yurunavi/.MainActivity >/dev/null
}

echo "round,timestamp,speedo_ink,sunset_ink,arrow_blue_px,whiteout" > "$OUTDIR/results.csv"

for i in $(seq 1 "$ROUNDS"); do
  TS=$(date +%H:%M:%S)
  echo "== round $i/$ROUNDS trigger=$TRIGGER dwell=${DWELL}s @ $TS =="
  do_trigger_enter
  sleep "$DWELL"
  do_return
  sleep 3
  SHOT="$OUTDIR/r${i}.png"
  adb exec-out screencap -p > "$SHOT"
  JSON=$(python3 "$(dirname "$0")/detect_whiteout.py" "$SHOT" --screen "$SCREEN" --density "$DENSITY" --json 2>/dev/null || echo '{}')
  echo "$JSON"
  ROW=$(python3 -c "
import json,sys
d=json.loads('''$JSON''')
sp=d.get('speedo_inner',{}).get('ink_ratio','')
dl=d.get('daylight_inner',{}).get('ink_ratio','')
arrow=d.get('puck_px','')
wo=d.get('whiteout','')
print(f'{sp},{dl},{arrow},{wo}')
" 2>/dev/null || echo ",,,ERROR")
  echo "$i,$TS,$ROW" >> "$OUTDIR/results.csv"
done

echo "done. results: $OUTDIR/results.csv"
