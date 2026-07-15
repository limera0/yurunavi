#!/usr/bin/env bash
# YuruNavi POI 데이터 분기 재동기화 — 소상공인시장진흥공단 상가(상권)정보 CSV를
# data.go.kr에서 새로 받아 poi.db(SQLite)를 재적재한다.
#
# 실행 주기: 분기 1회 권장(원본 데이터 자체가 분기 갱신 — 다음 예정 2026-08-01).
# crontab에 자동 등록은 하지 않았다 — data.go.kr 페이지 구조가 바뀌면 이 스크립트의
# 다운로드 링크 추출이 조용히 실패할 수 있는데, 사람이 안 보는 새벽 cron에서 그런
# 실패가 운영 데이터를 반쯤 망가뜨린 채 방치될 위험이 있다고 판단해서다(아래
# 검증 단계들이 최대한 막아주지만, 완전히 자동화하기보다 사람이 분기 1회 수동
# 트리거하거나, 신뢰가 쌓인 뒤 아래 cron 줄을 직접 추가하길 권장):
#   0 4 1 8,11,2,5 * /data/projects/yurunavi/docker/refresh_poi_data.sh >> /data/poi/refresh.log 2>&1
#
# 실패 시 항상 기존 데이터를 그대로 두고 종료한다(부분 갱신으로 인한 데이터
# 손상을 만들지 않는다 — staging 디렉터리에서 전부 검증한 뒤에만 실제 경로를 교체).
set -euo pipefail

DATASET_PK=15083033
POI_DIR=/data/poi
RAW_DIR="$POI_DIR/raw"
DB_PATH="$POI_DIR/poi.db"
STAGING=$(mktemp -d /tmp/poi_refresh.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

log() { echo "[refresh_poi_data] $(date -Iseconds) $*"; }

log "시작 — staging=$STAGING"

# ── 1. 최신 다운로드 링크 추출 ────────────────────────────────────
# data.go.kr 파일데이터 상세 페이지에 검색엔진용 JSON-LD(schema.org DataDownload)로
# 실제 다운로드 URL이 박혀있다 — 이 필드가 매 분기 새 atchFileId로 갱신된다.
DETAIL_URL="https://www.data.go.kr/data/${DATASET_PK}/fileData.do"
CONTENT_URL=$(curl -sL -A "Mozilla/5.0" "$DETAIL_URL" \
  | grep -o '"contentUrl"[[:space:]]*:[[:space:]]*"[^"]*fileDownload[^"]*"' \
  | head -1 \
  | sed -E 's/.*"(https:[^"]+)".*/\1/')

if [ -z "$CONTENT_URL" ]; then
  log "실패: 다운로드 링크를 페이지에서 찾지 못함 — data.go.kr 페이지 구조가 바뀌었을 수 있음. 중단(기존 데이터 유지)."
  exit 1
fi
log "다운로드 링크: $CONTENT_URL"

# ── 2. 다운로드 + 압축 해제 (staging) ─────────────────────────────
ZIP_PATH="$STAGING/poi_data.zip"
curl -sL -A "Mozilla/5.0" "$CONTENT_URL" -o "$ZIP_PATH"

ZIP_TYPE=$(file -b "$ZIP_PATH")
if [[ "$ZIP_TYPE" != *"Zip archive"* ]]; then
  log "실패: 다운로드된 파일이 zip이 아님 ($ZIP_TYPE) — 로그인 페이지 등이 대신 받아졌을 가능성. 중단."
  exit 1
fi

mkdir -p "$STAGING/extracted"
unzip -q -o "$ZIP_PATH" -d "$STAGING/extracted"

CSV_COUNT=$(find "$STAGING/extracted" -name "*.csv" | wc -l)
if [ "$CSV_COUNT" -lt 15 ]; then
  log "실패: 압축 해제된 CSV가 ${CSV_COUNT}개뿐(17개 시도 기대) — 중단."
  exit 1
fi

TOTAL_ROWS=$(find "$STAGING/extracted" -name "*.csv" -exec cat {} + | wc -l)
# 2026-07-15 기준 실측 2,725,336행(헤더 포함, 17개 파일) — 데이터가 꾸준히 늘어나는
# 추세이므로 넉넉하게 200만~500만 행을 정상 범위로 본다.
if [ "$TOTAL_ROWS" -lt 2000000 ] || [ "$TOTAL_ROWS" -gt 5000000 ]; then
  log "실패: 총 행수(${TOTAL_ROWS})가 예상 범위(200만~500만) 밖 — 중단."
  exit 1
fi
log "검증 통과: CSV ${CSV_COUNT}개, 총 ${TOTAL_ROWS}행"

# ── 3. raw 디렉터리 교체 (검증 통과 후에만) ───────────────────────
mkdir -p "$RAW_DIR"
rsync -a --delete "$STAGING/extracted"/*.csv "$RAW_DIR"/
log "raw 디렉터리 교체 완료: $RAW_DIR"

# ── 4. ingest_poi 빌드 + 재적재 (임시 파일에, 검증 후 원자적 교체) ──
NATIVE_DIR=/data/projects/yurunavi/native
( cd "$NATIVE_DIR" && cargo build --release --bin ingest_poi )

NEW_DB="$STAGING/poi.db.new"
"$NATIVE_DIR/target/release/ingest_poi" --input-dir "$RAW_DIR" --output "$NEW_DB"

NEW_DB_SIZE=$(stat -c%s "$NEW_DB" 2>/dev/null || echo 0)
# 2026-07-15 기준 실측 153.6MB(696,255행) — 데이터 증가 추세를 감안해 넉넉하게
# 50MB~500MB를 정상 범위로 본다.
if [ "$NEW_DB_SIZE" -lt 52428800 ] || [ "$NEW_DB_SIZE" -gt 524288000 ]; then
  log "실패: 새 DB 크기(${NEW_DB_SIZE} bytes)가 예상 범위(50MB~500MB) 밖 — 기존 poi.db 유지, 중단."
  exit 1
fi

# ── 5. 원자적 교체 + 서비스 재시작 ─────────────────────────────────
# 같은 파일시스템(/data) 내 mv는 원자적 rename — 다운타임 없이 파일 교체.
# 단, navi 서버는 시작 시 한 번만 DB를 여는 구조라(main.rs의 OnceLock) 컨테이너
# 재시작이 있어야 새 DB를 인식한다.
mv "$NEW_DB" "$DB_PATH"
log "poi.db 교체 완료: $DB_PATH ($NEW_DB_SIZE bytes)"

( cd /data/projects/yurunavi/docker && docker compose restart navi )
log "yurunavi-navi 재시작 완료 — 새 POI 데이터 반영됨"

log "완료"
