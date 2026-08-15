#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

NATIVE_DIR=/data/projects/yurunavi/native
OUTPUT=/data/gasstations/gasstations.json

log() { echo "[refresh_gasstations] $(date -Iseconds) $*"; }

log "시작"

mkdir -p /data/gasstations

(cd "$NATIVE_DIR" && cargo build --release --bin refresh_gasstations 2>&1)

"$NATIVE_DIR/target/release/refresh_gasstations" --output "$OUTPUT"

log "완료 — $(stat -c%s "$OUTPUT" 2>/dev/null || echo 0) bytes"

# cron 등록 (root 또는 limera):
# 0 5 * * * /data/projects/yurunavi/docker/refresh_gasstations.sh >> /data/gasstations/refresh.log 2>&1
