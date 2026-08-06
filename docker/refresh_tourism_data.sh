#!/usr/bin/env bash
# YuruNavi 관광지(관광지/전망대) 데이터 재생성 — OSM PBF(1순위) + data.go.kr
# 전국관광지정보표준데이터(2순위, 한글 명칭 보강)에서 추출해 tourism.db(SQLite)를
# 만든다.
#
# ⚠️ 라이선스 분리 원칙 (RECON_0805_offline_first_architecture.md §9-3): 이 DB는
# poi.db(/data/poi/poi.db, 소상공인시장진흥공단 데이터·공공누리)와 물리적으로 완전히
# 별도 파일이다. OSM(ODbL) 데이터를 poi.db와 같은 파일에 병합하면 그 DB 전체가 ODbL
# "파생 데이터베이스"가 되어 share-alike 의무가 걸릴 수 있다 — 절대 poi.db와 합치지
# 말 것. tourism.db는 poi.db와 별개로 배포되는 collective database로 유지한다.
#
# 실행 주기: OSM PBF 자체는 Valhalla 파이프라인이 비정기 갱신, data.go.kr 표준데이터는
# 연 1회 갱신(문화체육관광부 소관). refresh_poi_data.sh와 같은 이유로 crontab에 자동
# 등록하지 않는다 — data.go.kr 페이지/API 구조가 바뀌면 조용히 실패할 수 있는데, 사람이
# 안 보는 새벽 cron에서 그런 실패가 방치될 위험이 있어서다. 필요시 수동 트리거하거나
# 신뢰가 쌓인 뒤 아래 cron 줄을 직접 추가하길 권장:
#   0 4 1 1,7 * /data/projects/yurunavi/docker/refresh_tourism_data.sh >> /data/poi/tourism_refresh.log 2>&1
#
# 실패 시 항상 기존 tourism.db를 그대로 두고 종료한다(부분 갱신 금지 — staging에서
# 전부 검증한 뒤에만 실제 경로를 교체). 단, data.go.kr 보강 단계는 실패해도 스크립트
# 전체를 중단하지 않는다 — OSM 추출분만으로 tourism.db를 완성하고 계속 진행한다
# (data.go.kr은 2순위 보강 소스일 뿐 필수 소스가 아님).
set -euo pipefail

PBF_PATH="${PBF_PATH:-/data/valhalla/staging_impossible_turns/korea_patched.osm.pbf}"
TOURISM_DIR=/data/poi
RAW_DIR="$TOURISM_DIR/tourism_raw"
DB_PATH="$TOURISM_DIR/tourism.db"
STD_DATASET_PK=15021141
MATCH_RADIUS_M=80
STAGING=$(mktemp -d /tmp/tourism_refresh.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

log() { echo "[refresh_tourism_data] $(date -Iseconds) $*"; }

log "시작 — staging=$STAGING"

# ── 0. 필수 도구 확인 ──────────────────────────────────────────────
for bin in osmium jq curl; do
  command -v "$bin" >/dev/null || { log "실패: 필수 도구 '$bin'가 없습니다 — 중단."; exit 1; }
done

if [ ! -f "$PBF_PATH" ]; then
  log "실패: PBF 파일 없음($PBF_PATH) — 중단."
  exit 1
fi

# ── 1. OSM PBF에서 관광지/전망대 태그 추출 ────────────────────────
# 매핑: tourism=viewpoint→viewpoint / boundary=national_park·tourism=attraction·
# tourism=museum·historic=*·leisure=nature_reserve·natural=peak(이름 있는 것만)→
# tourist_spot. 카테고리 분류 자체는 ingest_tourism(Rust)이 한다 — 여기서는 태그
# 필터링만 한다.
FILTERED_PBF="$STAGING/tourism_filtered.osm.pbf"
osmium tags-filter "$PBF_PATH" \
  tourism=viewpoint \
  boundary=national_park \
  tourism=attraction \
  tourism=museum \
  historic \
  leisure=nature_reserve \
  natural=peak \
  -o "$FILTERED_PBF" -O -f pbf
log "osmium tags-filter 완료"

OSM_GEOJSONSEQ="$STAGING/osm_tourism.geojsonseq"
osmium export "$FILTERED_PBF" -o "$OSM_GEOJSONSEQ" -f geojsonseq -O \
  -a type,id --geometry-types=point,linestring,polygon
log "osmium export 완료"

OSM_FEATURE_COUNT=$(wc -l < "$OSM_GEOJSONSEQ")
# 2026-08-06 기준 실측 약 30,400라인(RECON §9-1 기대치 합계 약 28,000건과 자릿수
# 일치 — 태그 중복 매칭이 있어 정확히 같지는 않다). OSM 데이터는 계속 갱신되므로
# 넉넉하게 15,000~60,000라인을 정상 범위로 본다.
if [ "$OSM_FEATURE_COUNT" -lt 15000 ] || [ "$OSM_FEATURE_COUNT" -gt 60000 ]; then
  log "실패: OSM 추출 라인 수(${OSM_FEATURE_COUNT})가 예상 범위(15,000~60,000) 밖 — 태그 필터가 깨졌을 수 있음. 중단(기존 tourism.db 유지)."
  exit 1
fi
log "OSM 추출 검증 통과: ${OSM_FEATURE_COUNT}라인"

# ── 2. data.go.kr 전국관광지정보표준데이터 다운로드(보강용, 실패해도 계속 진행) ──
# 이 데이터셋은 "표준데이터"(standard.do) 탭이라 fileData.do류처럼 JSON-LD
# contentUrl로 바로 받아지는 zip이 없다. 대신 그리드 다운로드 버튼이 클라이언트에서
# 페이지네이션 JSON API 2개를 호출해 조립한다(2026-08-06 확인, 로그인/서비스키 불필요):
#   1) GET /download/columList.json?pk=<PK>&ext=CSV → 컬럼 목록 + totalCount
#   2) GET /download/standard.json?publicDataPk=<PK>&colNmList=...(반복)&totalCount=..
#      &svcTableNm=<svcTableNm>&perPage=10000&page=N → 레코드 JSON 배열(페이지당 최대
#      1만 건, 그리드 다운로드 전체 상한 5만 건)
STD_CSV="$STAGING/tourism_std.csv"
STD_OK=0
DETAIL_URL="https://www.data.go.kr/data/${STD_DATASET_PK}/standard.do"

HEADER_JSON=$(curl -sL -A "Mozilla/5.0" -e "$DETAIL_URL" \
  "https://www.data.go.kr/download/columList.json?pk=${STD_DATASET_PK}&ext=CSV" || true)

TOTAL_COUNT=$(echo "$HEADER_JSON" | jq -r '.totalCount // empty' 2>/dev/null || true)
SVC_TABLE=$(echo "$HEADER_JSON" | jq -r '.tableVO.svcTableNm // empty' 2>/dev/null || true)
COL_LIST=$(echo "$HEADER_JSON" | jq -r '.tableVO.colNmList // [] | @tsv' 2>/dev/null || true)

if [ -z "$TOTAL_COUNT" ] || [ -z "$SVC_TABLE" ] || [ -z "$COL_LIST" ] || ! [[ "$TOTAL_COUNT" =~ ^[0-9]+$ ]]; then
  log "경고: data.go.kr 헤더 조회 실패(페이지 구조가 바뀌었거나 로그인/서비스키가 필요해졌을 수 있음) — 표준데이터 보강 스킵, OSM 단독으로 진행."
elif [ "$TOTAL_COUNT" -gt 49000 ]; then
  log "경고: data.go.kr 총 건수(${TOTAL_COUNT})가 그리드 다운로드 5만건 제한에 근접/초과 — 이 스크립트는 페이지네이션 상한 대응 미구현. 표준데이터 보강 스킵."
else
  log "data.go.kr 헤더 조회 성공: totalCount=${TOTAL_COUNT} svcTableNm=${SVC_TABLE}"

  QS=""
  while IFS=$'\t' read -r -a cols; do
    for c in "${cols[@]}"; do
      [ -n "$c" ] && QS="${QS}colNmList=${c}&"
    done
  done <<< "$COL_LIST"

  PAGE_SIZE=10000
  PAGES=$(( (TOTAL_COUNT + PAGE_SIZE - 1) / PAGE_SIZE ))

  echo "name,category_raw,road_addr,lot_addr,lat,lon,description,institution" > "$STD_CSV"
  DOWNLOAD_FAILED=0
  for ((p = 1; p <= PAGES; p++)); do
    PAGE_URL="https://www.data.go.kr/download/standard.json?publicDataPk=${STD_DATASET_PK}&${QS}totalCount=${TOTAL_COUNT}&svcTableNm=${SVC_TABLE}&perPage=${PAGE_SIZE}&page=${p}"
    PAGE_JSON=$(curl -sL -A "Mozilla/5.0" -e "$DETAIL_URL" "$PAGE_URL" || true)
    if ! echo "$PAGE_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
      log "경고: data.go.kr ${p}페이지 응답이 JSON 배열이 아님 — 표준데이터 보강 중단(이번 실행은 OSM 단독)."
      DOWNLOAD_FAILED=1
      break
    fi
    echo "$PAGE_JSON" | jq -r '.[] | [
        (.TRRSRT_NM // ""), (.TRRSRT_SE // ""), (.RDNMADR // ""), (.LNMADR // ""),
        (.LATITUDE // ""), (.LONGITUDE // ""), (.TRRSRT_INTRCN // ""), (.INSTITUTION_NM // "")
      ] | @csv' >> "$STD_CSV"
  done

  if [ "$DOWNLOAD_FAILED" -eq 0 ]; then
    STD_ROWS=$(( $(wc -l < "$STD_CSV") - 1 ))
    if [ "$STD_ROWS" -lt 1 ]; then
      log "경고: data.go.kr 표준데이터 행이 0건 — 표준데이터 보강 스킵."
    else
      log "data.go.kr 표준데이터 다운로드 완료: ${STD_ROWS}행(기대 ${TOTAL_COUNT}행)"
      STD_OK=1
    fi
  fi
fi

# ── 3. raw 디렉터리 보관(감사/재현용) ──────────────────────────────
mkdir -p "$RAW_DIR"
cp "$OSM_GEOJSONSEQ" "$RAW_DIR/osm_tourism.geojsonseq"
if [ "$STD_OK" -eq 1 ]; then
  cp "$STD_CSV" "$RAW_DIR/tourism_std.csv"
else
  rm -f "$RAW_DIR/tourism_std.csv"
fi
log "raw 디렉터리 갱신 완료: $RAW_DIR"

# ── 4. ingest_tourism 빌드 + 적재(임시 파일에, 검증 후 원자적 교체) ──
NATIVE_DIR=/data/projects/yurunavi/native
( cd "$NATIVE_DIR" && cargo build --release --bin ingest_tourism )

NEW_DB="$STAGING/tourism.db.new"
INGEST_ARGS=(--osm-geojsonseq "$OSM_GEOJSONSEQ" --output "$NEW_DB" --match-radius-m "$MATCH_RADIUS_M")
if [ "$STD_OK" -eq 1 ]; then
  INGEST_ARGS+=(--std-csv "$STD_CSV")
fi
"$NATIVE_DIR/target/release/ingest_tourism" "${INGEST_ARGS[@]}"

NEW_DB_SIZE=$(stat -c%s "$NEW_DB" 2>/dev/null || echo 0)
# 2026-08-06 기준 실측 약 5~8MB대(RECON §9-4 추정치 ~5MB 근사). 넉넉하게 1MB~50MB를
# 정상 범위로 본다.
if [ "$NEW_DB_SIZE" -lt 1048576 ] || [ "$NEW_DB_SIZE" -gt 52428800 ]; then
  log "실패: 새 DB 크기(${NEW_DB_SIZE} bytes)가 예상 범위(1MB~50MB) 밖 — 기존 tourism.db 유지, 중단."
  exit 1
fi

# ── 5. 원자적 교체 ──────────────────────────────────────────────────
# 같은 파일시스템(/data) 내 mv는 원자적 rename. 이번 청크(O0)는 온라인 경로
# (`native/src/main.rs` `/poi/nearby`) 통합 전 단계라 서비스 재시작은 하지 않는다
# — tourism.db를 실제로 서빙에 연결하는 작업은 다음 청크(§2-4)에서 한다.
mv "$NEW_DB" "$DB_PATH"
log "tourism.db 교체 완료: $DB_PATH ($NEW_DB_SIZE bytes)"

log "완료"
