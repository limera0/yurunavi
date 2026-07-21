#!/usr/bin/env bash
# 프로덕션 Valhalla 타일을 apply_overlays.py가 검증한 staging 빌드로 교체한다.
#
# apply_overlays.py가 이미 PASS(격리 컨테이너 target/regression 테스트 통과)한
# 뒤에만 실행할 것 — LAST_VERIFIED_PASS 마커가 없거나 --korea-only로 검증된
# 빌드면 거부한다(프로덕션은 한국+일본 타일을 같이 서비스하므로).
#
# 롤백 지점: [1] 백업 -> [2] tile_extract(.tar) 재생성 -> [3] 스왑 -> [4] 재기동 후
# 회귀 curl 자동 확인 -> 실패 시(ERR trap) [1]의 백업으로 자동 복원.
set -euo pipefail

CUSTOM_FILES="/data/valhalla/custom_files"
STAGING_DIR="/data/valhalla/staging_impossible_turns"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != "--yes-i-am-sure" ]]; then
  echo "이 스크립트는 프로덕션 Valhalla 타일을 교체합니다 (yurunavi-valhalla 컨테이너, 8002)." >&2
  echo "확인했으면: $0 --yes-i-am-sure" >&2
  exit 1
fi

MARKER="$STAGING_DIR/LAST_VERIFIED_PASS"
if [[ ! -f "$MARKER" ]]; then
  echo "FAIL: $MARKER 없음 — apply_overlays.py를 먼저 PASS 시킬 것" >&2
  exit 1
fi
if grep -q "korea_only=True" "$MARKER"; then
  echo "FAIL: 마지막 검증이 --korea-only 모드였음 — 프로덕션은 한국+일본을 같이 서비스하므로" >&2
  echo "      apply_overlays.py를 --korea-only 없이 재실행해 다시 PASS 시킬 것" >&2
  exit 1
fi
echo "마커 확인:"; cat "$MARKER"

STAGED_TILES="$STAGING_DIR/tiles"
if [[ ! -d "$STAGED_TILES" ]]; then
  echo "FAIL: $STAGED_TILES 없음" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_TILES="$CUSTOM_FILES/valhalla_tiles.bak.$STAMP"
BACKUP_TAR="$CUSTOM_FILES/valhalla_tiles.tar.bak.$STAMP"
BACKUP_PBF="$CUSTOM_FILES/south-korea-latest.osm.pbf.bak.$STAMP"

echo "=== [1] 백업 ==="
cp -a "$CUSTOM_FILES/valhalla_tiles" "$BACKUP_TILES"
cp "$CUSTOM_FILES/valhalla_tiles.tar" "$BACKUP_TAR"
cp "$CUSTOM_FILES/south-korea-latest.osm.pbf" "$BACKUP_PBF"
echo "백업 완료: $BACKUP_TILES , $BACKUP_TAR , $BACKUP_PBF"

SWAPPED=0
rollback() {
  if [[ "$SWAPPED" -eq 0 ]]; then
    echo "=== 스왑 전 실패 — 프로덕션 미변경, 롤백 불필요 ===" >&2
    return
  fi
  echo "=== 롤백: 백업으로 복원 ===" >&2
  rm -rf "$CUSTOM_FILES/valhalla_tiles"
  cp -a "$BACKUP_TILES" "$CUSTOM_FILES/valhalla_tiles"
  cp "$BACKUP_TAR" "$CUSTOM_FILES/valhalla_tiles.tar"
  cp "$BACKUP_PBF" "$CUSTOM_FILES/south-korea-latest.osm.pbf"
  (cd "$COMPOSE_DIR" && docker compose restart valhalla)
  echo "롤백 완료 — 프로덕션은 스왑 이전 상태로 돌아옴" >&2
}
trap 'echo "실패 — 롤백 실행"; rollback' ERR

echo "=== [2] tile_extract(.tar) 재생성 ==="
# 프로덕션 valhalla.json은 tile_dir뿐 아니라 tile_extract(.tar)도 참조하고
# Valhalla는 있으면 .tar를 우선 읽으므로, tile_dir만 바꾸면 반영되지 않는다.
# staged tile_dir을 가리키는 임시 config로 valhalla_build_extract를 돌려
# 새 .tar를 만든 뒤, tile_dir/.tar를 함께 스왑한다.
NEW_TAR="$STAGING_DIR/valhalla_tiles.new.tar"
EXTRACT_CFG="$(mktemp)"
trap 'rm -f "$EXTRACT_CFG"' EXIT
python3 - "$CUSTOM_FILES/valhalla.json" "$EXTRACT_CFG" <<'PYEOF'
import json, sys
base_cfg, out_cfg = sys.argv[1], sys.argv[2]
cfg = json.load(open(base_cfg))
cfg["mjolnir"]["tile_dir"] = "/work/tiles"
cfg["mjolnir"]["tile_extract"] = "/work/out.tar"
json.dump(cfg, open(out_cfg, "w"), indent=2)
PYEOF
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$STAGED_TILES:/work/tiles:ro" -v "$EXTRACT_CFG:/work/valhalla_extract.json:ro" \
  -v "$STAGING_DIR:/out" "$(docker inspect -f '{{.Config.Image}}' yurunavi-valhalla)" \
  bash -c "valhalla_build_extract -c /work/valhalla_extract.json -e /out/valhalla_tiles.new.tar -O"

echo "=== [3] 스왑 ==="
cp "$STAGING_DIR/korea_patched_sorted.osm.pbf" "$CUSTOM_FILES/south-korea-latest.osm.pbf.new"
rm -rf "$CUSTOM_FILES/valhalla_tiles.new"
cp -a "$STAGED_TILES" "$CUSTOM_FILES/valhalla_tiles.new"

# 첫 mv부터가 실제 프로덕션 상태 변경 시작점 — 그 직전에 SWAPPED=1을 세워야
# 이 블록 중간(예: 세 번째 mv)에서 실패해도 ERR trap이 rollback()을 실행한다.
# (code-audit 지적: 마지막 mv 뒤에 세우면 중간 실패 시 롤백이 스킵됨)
SWAPPED=1
mv "$CUSTOM_FILES/valhalla_tiles" "$CUSTOM_FILES/valhalla_tiles.old"
mv "$CUSTOM_FILES/valhalla_tiles.new" "$CUSTOM_FILES/valhalla_tiles"
mv "$CUSTOM_FILES/valhalla_tiles.tar" "$CUSTOM_FILES/valhalla_tiles.tar.old"
mv "$NEW_TAR" "$CUSTOM_FILES/valhalla_tiles.tar"
mv "$CUSTOM_FILES/south-korea-latest.osm.pbf.new" "$CUSTOM_FILES/south-korea-latest.osm.pbf"
(cd "$COMPOSE_DIR" && docker compose restart valhalla)

echo "=== [4] 재기동 후 자동 회귀 확인 (프로덕션 8002 직접) ==="
for i in $(seq 1 20); do
  curl -s -o /dev/null -w '' --max-time 2 http://localhost:8002/status && break
  sleep 2
done
python3 - <<'PYEOF'
import json, subprocess, sys
checks = [
    # (설명, from, to, 조건)
    ("pt1 target: 유령 관통이 사라졌는지", (37.0919082,127.0919759), (37.0918174,127.0920029), "min", 0.2),
    ("pt2 target: 유령 좌회전이 사라졌는지", (37.13692,127.07857), (37.1406573,127.0783435), "min", 0.6),
]
for desc, frm, to, kind, thresh in checks:
    body = json.dumps({"locations": [{"lat": frm[0], "lon": frm[1]}, {"lat": to[0], "lon": to[1]}], "costing": "motorcycle"})
    out = subprocess.run(["curl", "-s", "-X", "POST", "http://localhost:8002/route",
                          "-H", "Content-Type: application/json", "-d", body],
                         capture_output=True, text=True, timeout=20)
    data = json.loads(out.stdout)
    km = data["trip"]["summary"]["length"]
    ok = km >= thresh if kind == "min" else km <= thresh
    print(f"{'OK' if ok else 'FAIL'} {desc}: {km:.3f}km (기준 {kind} {thresh}km)")
    if not ok:
        sys.exit(1)
PYEOF

trap - ERR
# valhalla_tiles.old의 내용물은 컨테이너(root)가 만든 것이라 호스트 rm -rf가
# 권한 오류로 실패한다 (2026-07-21 실제 스왑에서 확인) — 같은 이미지로 root
# 컨테이너를 띄워 지우면 조용히 끝난다.
docker run --rm -v "$CUSTOM_FILES:/cf" alpine sh -c 'rm -rf /cf/valhalla_tiles.old /cf/valhalla_tiles.tar.old'
echo "=== 완료 === 이전 타일 백업은 $BACKUP_TILES / $BACKUP_TAR / $BACKUP_PBF 에 보관됨"
