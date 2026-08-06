#!/usr/bin/env bash
# S1b 조사용 — S3b 플로팅 오버레이 경로의 실제 트리거(HOME → 오버레이 아이콘 탭 복귀)
# 반복 왕복 실험. pip_repeat.sh(구 PIP 경로, S3b 이전)와 구분해서 유지한다.
# usage: real_trigger_repeat.sh <rounds> <dwell_sec> <out_dir> [overlay_x] [overlay_y]
set -euo pipefail

ROUNDS="${1:-10}"
DWELL="${2:-3}"
OUTDIR="${3:-/tmp/real_trigger_repeat}"
OVX="${4:-934}"
OVY="${5:-1939}"
DENSITY=450
SCREEN=1080x2400

mkdir -p "$OUTDIR"
echo "round,timestamp,speedo_ink,sunset_ink,arrow_blue_px,whiteout" > "$OUTDIR/results.csv"

for i in $(seq 1 "$ROUNDS"); do
  TS=$(date +%H:%M:%S)
  echo "== round $i/$ROUNDS dwell=${DWELL}s @ $TS =="
  adb shell input keyevent KEYCODE_HOME
  sleep "$DWELL"
  adb shell input tap "$OVX" "$OVY"
  sleep 2
  SHOT="$OUTDIR/r${i}.png"
  adb exec-out screencap -p > "$SHOT"
  JSON=$(python3 "$(dirname "$0")/detect_whiteout.py" "$SHOT" --screen "$SCREEN" --density "$DENSITY" --json 2>/dev/null || echo '{}')
  echo "$JSON"
  ROW=$(python3 -c "
import json
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
