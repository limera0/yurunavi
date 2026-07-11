#!/usr/bin/env bash
# YuruNavi 인프라 영속 데이터 백업 (tileserver-gl mbtiles/fonts, valhalla custom_files,
# valhalla-fork 소스 — 이 소스는 origin에 push된 적 없는 로컬 전용 커밋이라 이 백업이
# 유일한 사본이다).
# 매일 cron으로 실행, 최근 KEEP개 세대를 하드링크 스냅샷으로 보관 —
# 변경되지 않은 파일은 디스크를 다시 쓰지 않아 매일 전체를 복사하는 것보다 저렴하다.
set -euo pipefail

DEST_ROOT=/data/backups/yurunavi
DATE=$(date +%Y%m%d)
KEEP=3

backup_one() {
  local name="$1" src="$2"
  local dest_dir="$DEST_ROOT/$name"
  local snapshot="$dest_dir/$DATE"
  local latest="$dest_dir/latest"

  mkdir -p "$dest_dir"

  local link_opt=()
  if [ -d "$latest" ]; then
    link_opt=(--link-dest="$latest")
  fi

  rsync -a --delete "${link_opt[@]}" "$src"/ "$snapshot"/
  ln -sfn "$snapshot" "$latest"

  # 오래된 세대 정리 (YYYYMMDD 이름 기준 정렬 — mtime이 아니라 이름으로 정렬해
  # 파일시스템 mtime 드리프트에 흔들리지 않음. latest 심링크는 글롭에서 제외됨)
  ls -1d "$dest_dir"/2[0-9][0-9][0-9][0-9][0-9][0-9][0-9] 2>/dev/null \
    | sort -r \
    | tail -n +$((KEEP + 1)) \
    | xargs -r rm -rf
}

backup_one tiles /data/tiles/data
backup_one valhalla /data/valhalla/custom_files
backup_one valhalla-src /data/projects/valhalla-src

echo "[backup] $(date -Iseconds) 완료 — 보관 위치: $DEST_ROOT (최근 ${KEEP}세대 유지)"
