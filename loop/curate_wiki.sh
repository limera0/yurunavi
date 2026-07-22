#!/usr/bin/env bash
# loop/curate_wiki.sh — C: 위키 큐레이션 (주 1회 권장)
#
# loop/RECON_*.md + REPORT_*.md 를 카테고리별 인덱스(loop/WIKI_INDEX.md)로 재정리한다.
# 소스 문서는 절대 안 건드리고, git 커밋도 안 하며, 오직 WIKI_INDEX.md 하나만 쓴다.
# 100개+ 파일을 모델이 하나씩 읽는 비용을 피하려고, 스크립트가 먼저 [파일명+제목]
# 다이제스트를 뽑아 넘기고 모델은 분류·훅 작성만 한다. cron/수동/틱 어디서든 단발 실행 가능.
#
# 사용법: loop/curate_wiki.sh [--timeout N] [--effort LEVEL]
# cron 예: 매주 일요일 04:00 →  0 4 * * 0  /data/projects/yurunavi/loop/curate_wiki.sh

set -uo pipefail
cd /data/projects/yurunavi || exit 1

if [ "$(id -u)" -eq 0 ]; then
  echo "FATAL: root로 실행 금지. 일반 계정에서 실행하세요." >&2
  exit 1
fi

# .env는 claude 실행 환경 일관성용(없어도 무방)
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

TIMEOUT=900        # 15min — 단발 큐레이션 틱 하드 타임아웃
EFFORT="high"
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
LOG_DIR="loop/.auto/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/curate_wiki_$(date +%m%d_%H%M).log"
INDEX="loop/WIKI_INDEX.md"

DIGEST="$(mktemp)"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$DIGEST" "$PROMPT_FILE"' EXIT

# 각 RECON/REPORT 파일의 파일명 + 첫 제목(없으면 첫 유의미한 줄)을 다이제스트로 수집.
for f in loop/RECON_*.md loop/REPORT_*.md; do
  [ -e "$f" ] || continue
  title=$(grep -m1 -E '^#{1,3} +\S' "$f" 2>/dev/null | sed -E 's/^#+ *//')
  [ -z "$title" ] && title=$(grep -m1 -vE '^[[:space:]]*$' "$f" 2>/dev/null | head -c 160)
  printf '%s\t%s\n' "$(basename "$f")" "${title:0:160}"
done > "$DIGEST"

n=$(wc -l < "$DIGEST" | tr -d ' ')
echo "curate_wiki: 대상 ${n}개 파일 다이제스트 수집 완료" | tee -a "$LOG"
if [ "$n" -eq 0 ]; then
  echo "WARNING: 인덱싱할 RECON/REPORT 파일이 없음 — 종료" | tee -a "$LOG"
  exit 0
fi

cat > "$PROMPT_FILE" <<PROMPT
너는 유루나비 프로젝트의 문서 큐레이터다. 아래는 loop/ 디렉토리의 정찰(RECON)·
결과(REPORT) 문서 ${n}개의 [파일명 <탭> 제목/첫줄] 다이제스트다. 이걸 주제
카테고리로 묶어 사람이 빠르게 훑을 수 있는 인덱스를 만드는 게 너의 유일한 임무다.

## 규칙 (반드시 지켜라)
- 오직 loop/WIKI_INDEX.md 파일 하나만 새로 써라(덮어쓰기). 다른 파일은 절대 건드리지 마라.
- 코드를 고치지 마라. git 커밋/스테이징 하지 마라. 소스 문서(RECON/REPORT)를 수정하지 마라.
- 카테고리는 다이제스트 내용에서 자연스럽게 도출해라(예: 라우팅/코스팅, 내비게이션/안내,
  지도/타일/스타일, 위치/GPS, 음성/TTS, UI/화면, 인프라/자동화 등). 억지로 맞추지 말 것.
- 각 항목은 한 줄로: \`- [파일명](파일명) — 한 줄 훅(무엇에 대한 문서인지)\`
- 제목이 비었거나 불명확하면 파일명에서 유추해 짧은 훅을 달아라.
- 맨 위에 \`# YuruNavi RECON/REPORT 인덱스\` 제목, 생성 시각, 총 문서 수를 적어라.
- 다이제스트에 있는 파일은 하나도 빠뜨리지 마라(전부 어느 카테고리든 들어가야 함).

## 다이제스트
$(cat "$DIGEST")
PROMPT

echo "curate_wiki: claude 실행 (timeout ${TIMEOUT}s, effort ${EFFORT})" | tee -a "$LOG"
mtime_before=$(stat -c %Y "$INDEX" 2>/dev/null || echo 0)

timeout --signal=TERM --kill-after=30s "$TIMEOUT" \
  "$CLAUDE_BIN" --permission-mode bypassPermissions --effort "$EFFORT" -p --verbose \
  < "$PROMPT_FILE" >> "$LOG" 2>&1
rc=$?

mtime_after=$(stat -c %Y "$INDEX" 2>/dev/null || echo 0)
if [ "$mtime_after" -gt "$mtime_before" ]; then
  echo "curate_wiki: 완료 — $INDEX 갱신됨 (exit=$rc, log=$LOG)"
else
  echo "WARNING: $INDEX 갱신 안 됨 (exit=$rc) — 로그 확인: $LOG"
fi
