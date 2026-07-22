#!/usr/bin/env bash
# loop/curate_wiki.sh — C: 위키 큐레이션 (일 1회 cron)
#
# loop/RECON_*.md + REPORT_*.md 를 인덱스(loop/WIKI_INDEX.md) 하나로 재정리한다.
# 소스 문서는 절대 안 건드리고, git 커밋도 안 하며, 오직 WIKI_INDEX.md 하나만 쓴다.
# 100개+ 파일을 모델이 하나씩 읽는 비용을 피하려고, 스크립트가 먼저
# [날짜+파일명+제목] 다이제스트를 뽑아 넘기고 모델은 분류·훅 작성만 한다.
#
# 출력은 한 파일 안에 두 가지 뷰를 같이 담는다:
#   1부 날짜순(사람이 시간 흐름으로 훑는 용도, 기본 정렬)
#   2부 주제별 색인(검색/Claude 참조 — 카테고리별로 파일명만 모아둔 크로스 인덱스)
# 날짜는 git 최초 커밋일(`git log --follow --diff-filter=A`)로 뽑는다 — 파일 mtime은
# archive 이동·일괄 편집으로 쉽게 오염되므로 신뢰하지 않는다.
#
# 사용법: loop/curate_wiki.sh [--timeout N] [--effort LEVEL]
# cron 예: 매일 04:10 →  10 4 * * *  /data/projects/yurunavi/loop/curate_wiki.sh

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

# claude 바이너리 탐색. cron은 로그인 셸 PATH(nvm 등)를 물려받지 않으므로 PATH만
# 믿으면 안 된다 — nvm 설치 경로까지 직접 훑는다(node 버전이 올라가도 최신 것을 잡도록
# 버전 정렬 후 마지막 것 선택). 못 찾으면 조용히 실패하지 말고 즉시 종료한다.
resolve_claude() {
  local c
  c="$(command -v claude 2>/dev/null)" && [ -x "$c" ] && { echo "$c"; return 0; }
  [ -x "$HOME/.local/bin/claude" ] && { echo "$HOME/.local/bin/claude"; return 0; }
  c="$(ls -1 "$HOME"/.nvm/versions/node/*/bin/claude 2>/dev/null | sort -V | tail -1)"
  [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  return 1
}
if ! CLAUDE_BIN="$(resolve_claude)"; then
  echo "FATAL: claude 실행 파일을 못 찾음 (PATH/~/.local/bin/~/.nvm 모두 확인함)." >&2
  exit 1
fi
LOG_DIR="loop/.auto/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/curate_wiki_$(date +%m%d_%H%M).log"
INDEX="loop/WIKI_INDEX.md"

DIGEST="$(mktemp)"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$DIGEST" "$PROMPT_FILE"' EXIT

# 각 RECON/REPORT 파일의 [git최초커밋일 + 파일명 + 첫 제목]을 다이제스트로 수집.
# 날짜순 정렬을 스크립트가 미리 해서 넘긴다(모델이 날짜를 재배열하다 틀리는 걸 방지).
for f in loop/RECON_*.md loop/REPORT_*.md; do
  [ -e "$f" ] || continue
  title=$(grep -m1 -E '^#{1,3} +\S' "$f" 2>/dev/null | sed -E 's/^#+ *//')
  [ -z "$title" ] && title=$(grep -m1 -vE '^[[:space:]]*$' "$f" 2>/dev/null | head -c 160)
  # --diff-filter=A + tail -1 = 이 경로에 파일이 "처음 추가된" 커밋의 날짜.
  # git 이력에 없는(아직 미커밋) 파일은 빈 값 → 정렬 맨 뒤로 가도록 9999로 채움.
  cdate=$(git log --follow --diff-filter=A --format=%ad --date=short -- "$f" 2>/dev/null | tail -1)
  [ -z "$cdate" ] && cdate="9999-99-99"
  printf '%s\t%s\t%s\n' "$cdate" "$(basename "$f")" "${title:0:160}"
done | sort -t"$(printf '\t')" -k1,1 -k2,2 > "$DIGEST"

n=$(wc -l < "$DIGEST" | tr -d ' ')
echo "curate_wiki: 대상 ${n}개 파일 다이제스트 수집 완료" | tee -a "$LOG"
if [ "$n" -eq 0 ]; then
  echo "WARNING: 인덱싱할 RECON/REPORT 파일이 없음 — 종료" | tee -a "$LOG"
  exit 0
fi

cat > "$PROMPT_FILE" <<PROMPT
너는 유루나비 프로젝트의 문서 큐레이터다. 아래는 loop/ 디렉토리의 정찰(RECON)·
결과(REPORT) 문서 ${n}개의 [git최초커밋일 <탭> 파일명 <탭> 제목/첫줄] 다이제스트다
(이미 날짜 오름차순으로 정렬해서 준다). 이걸 **하나의 파일에 두 가지 뷰**로 정리하는
것이 너의 유일한 임무다.

## 규칙 (반드시 지켜라)
- 오직 loop/WIKI_INDEX.md 파일 하나만 새로 써라(덮어쓰기). 다른 파일은 절대 건드리지 마라.
- 코드를 고치지 마라. git 커밋/스테이징 하지 마라. 소스 문서(RECON/REPORT)를 수정하지 마라.
- 다이제스트에 있는 파일은 하나도 빠뜨리지 마라(1부에 전부 1회씩 등장해야 함).
- 날짜를 네가 다시 계산하거나 재배열하지 마라 — 준 값을 그대로 써라.
- 맨 위에 \`# YuruNavi RECON/REPORT 인덱스\` 제목, 생성 시각, 총 문서 수, 그리고
  "1부=날짜순 본문 / 2부=주제별 색인"이라는 한 줄 안내를 적어라.

## 1부: 날짜순 본문 (기본 정렬)
- \`## 2026-06\` 처럼 **연-월 단위로 그룹**을 나누고, 그 안에서 날짜 오름차순.
- 각 항목은 한 줄로:
  \`- **YYYY-MM-DD** [파일명](파일명) — 한 줄 훅(무엇에 대한 문서인지)\`
- 훅은 제목을 그대로 베끼지 말고, 뭘 조사/구현한 문서인지 한눈에 알게 짧게 요약해라.
- 제목이 비었거나 불명확하면 파일명에서 유추해 달아라.

## 2부: 주제별 색인 (검색·참조용 크로스 인덱스)
- 1부 아래에 \`---\` 구분선 후 \`## 주제별 색인\` 섹션으로 붙여라.
- 카테고리는 내용에서 자연스럽게 도출해라(예: 라우팅/코스팅, 내비게이션/안내,
  지도/타일/스타일, 위치/GPS, 음성/TTS, UI/화면, 인프라/자동화 등). 억지로 맞추지 말 것.
- 여기서는 **훅을 반복하지 마라** — 파일명 링크만 쉼표로 나열해 압축한다:
  \`- **라우팅/코스팅**: [A.md](A.md), [B.md](B.md), [C.md](C.md)\`
- 한 문서가 두 주제에 걸치면 양쪽에 넣어도 된다(1부와 달리 중복 허용).
- 목적: 사람은 1부로 시간 흐름을 훑고, 검색/Claude는 2부로 주제를 바로 찾는다.

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
