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

# 색인 대상: loop/ 하위 모든 .md. 조사(RECON)·결과(REPORT)뿐 아니라 작업 이력
# (HANDOFF 지시서 / MORNING_REPORT 실행결과 / NIGHT_TASK)과 실주행 기록(feedback/)까지
# 포함한다 — "지난달 밤에 뭘 했지?"를 찾을 수 있어야 하기 때문.
# 제외:
#   .auto/         런타임 상태(handoff/tick_prompt/로그) — 문서가 아님
#   WIKI_INDEX.md  이 스크립트의 산출물(자기 자신)
#   STATUS.md      gen_status.sh 산출물(항상 재생성되는 현재 상태)
#   RELEASE_ROADMAP.md  살아있는 트래커라 색인 대상이 아니라 참조 대상
# 최상위 archive/ 는 통째로 제외 — duplicate_recon_report_root/ 101개가 loop/ 파일과
# 내용 해시까지 동일한 중복이라 색인에 넣으면 검색 품질만 떨어진다(2026-07-22 확인).
# 반면 loop/archive/ 는 옛 세션 기록이라 포함한다.
while IFS= read -r f; do
  [ -e "$f" ] || continue
  rel="${f#loop/}"
  base=$(basename "$f")
  title=$(grep -m1 -E '^#{1,3} +\S' "$f" 2>/dev/null | sed -E 's/^#+ *//')
  [ -z "$title" ] && title=$(grep -m1 -vE '^[[:space:]]*$' "$f" 2>/dev/null | head -c 160)
  # --diff-filter=A + tail -1 = 이 경로에 파일이 "처음 추가된" 커밋의 날짜.
  # git 이력에 없는(아직 미커밋) 파일은 빈 값 → 정렬 맨 뒤로 가도록 9999로 채움.
  gdate=$(git log --follow --diff-filter=A --format=%ad --date=short -- "$f" 2>/dev/null | tail -1)
  [ -z "$gdate" ] && gdate="9999-99-99"
  cdate="$gdate"

  # 파일명에 박힌 MMDD가 있으면 그걸 우선한다. 이 프로젝트의 loop/ 문서는 오래
  # 미커밋으로 쌓이다 뒤늦게 한꺼번에 커밋되는 일이 잦아(2026-07-21에 7월 초 문서
  # 다수가 한꺼번에 커밋됨) git 최초커밋일이 실제 작업일과 2주 넘게 어긋난다.
  # 예: HANDOFF_0705_1.md → git 2026-07-21, 실제 작업일 2026-07-05.
  mmdd=$(printf '%s' "$base" | grep -oE '_[0-9]{4}(_|\.md$)' | head -1 | tr -cd '0-9')
  if [ -n "$mmdd" ]; then
    mm=$((10#${mmdd:0:2})); dd=$((10#${mmdd:2:2}))   # 10# = 08/09를 8진수로 읽지 않게
    if [ "$mm" -ge 1 ] && [ "$mm" -le 12 ] && [ "$dd" -ge 1 ] && [ "$dd" -le 31 ]; then
      # 연도는 git 커밋 연도를 따른다(하드코딩 회피). 12월 파일이 이듬해 1월에
      # 커밋된 경우만 한 해 어긋나는데, 드물어서 보정하지 않는다.
      yy="${gdate%%-*}"
      [ "$yy" = "9999" ] && yy="$(date +%Y)"
      cdate=$(printf '%04d-%02d-%02d' "$yy" "$mm" "$dd")
    fi
  fi
  # 문서 종류 태그 — 모델이 제목만 보고 잘못 분류하지 않도록 스크립트가 확정해서 넘긴다.
  # 종류는 파일명으로, 보관 여부는 경로로 따로 판정한다(옛 리포트인지 옛 정찰인지
  # 구분이 사라지면 안 되므로 archive를 종류로 덮어쓰지 않는다).
  case "$base" in
    MORNING_REPORT*)       kind="리포트" ;;
    HANDOFF*|NIGHT_TASK*)  kind="지시서" ;;
    RECON_*)               kind="정찰" ;;
    REPORT_*)              kind="결과" ;;
    SPEC_*)                kind="스펙" ;;
    RIDE_RESULTS*|VGPS_*)  kind="실주행" ;;
    *)                     kind="기타" ;;
  esac
  case "$rel" in
    archive/*)   kind="$kind·보관" ;;
    feedback/*)  kind="$kind·주행기록" ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$cdate" "$kind" "$rel" "${title:0:160}"
done < <(find loop -name '*.md' \
           -not -path 'loop/.auto/*' \
           -not -name 'WIKI_INDEX.md' \
           -not -name 'STATUS.md' \
           -not -name 'RELEASE_ROADMAP.md' 2>/dev/null) \
  | LC_ALL=C sort -t"$(printf '\t')" -k1,1 -k3,3 > "$DIGEST"
# LC_ALL=C 필수: en_US.UTF-8 로케일의 sort는 동일한 한글 문자열조차 인접 배치를
#보장하지 않아 정렬이 비결정적이 된다(2026-07-22 실측 — 같은 '정찰' 값이 여러
# 그룹으로 쪼개짐). 바이트 정렬로 고정한다.

n=$(wc -l < "$DIGEST" | tr -d ' ')
echo "curate_wiki: 대상 ${n}개 파일 다이제스트 수집 완료" | tee -a "$LOG"
if [ "$n" -eq 0 ]; then
  echo "WARNING: 인덱싱할 RECON/REPORT 파일이 없음 — 종료" | tee -a "$LOG"
  exit 0
fi

cat > "$PROMPT_FILE" <<PROMPT
너는 유루나비 프로젝트의 문서 큐레이터다. 아래는 loop/ 디렉토리 문서 ${n}개의
[git최초커밋일 <탭> 종류 <탭> loop/기준 상대경로 <탭> 제목/첫줄] 다이제스트다
(이미 날짜 오름차순으로 정렬해서 준다). 이걸 **하나의 파일에 세 가지 뷰**로 정리하는
것이 너의 유일한 임무다.

종류 태그의 뜻: 정찰=조사 문서, 결과=구현/수정 결과, 지시서=그 회차에 할 일,
리포트=그 회차 실행 결과, 실주행=실기기 라이딩 기록, 스펙=설계 명세.
\`·보관\`이 붙으면 archive로 옮겨진 옛 문서, \`·주행기록\`이면 feedback/ 아래 문서다.

## 규칙 (반드시 지켜라)
- 오직 loop/WIKI_INDEX.md 파일 하나만 새로 써라(덮어쓰기). 다른 파일은 절대 건드리지 마라.
- 코드를 고치지 마라. git 커밋/스테이징 하지 마라. 소스 문서를 수정하지 마라.
- 다이제스트에 있는 파일은 하나도 빠뜨리지 마라(1부에 전부 1회씩 등장해야 함).
- 날짜와 종류를 네가 다시 판단하거나 재배열하지 마라 — 준 값을 그대로 써라.
- **링크는 반드시 준 상대경로 그대로 써라**(예: \`archive/legacy_sessions/X.md\`,
  \`feedback/Y.md\`). 파일명만 쓰면 링크가 깨진다.
- 맨 위에 \`# YuruNavi 문서 인덱스\` 제목, 생성 시각, 총 문서 수, 그리고
  "1부=날짜순 / 2부=주제별 / 3부=작업 이력"이라는 한 줄 안내를 적어라.

## 1부: 날짜순 본문 (기본 정렬)
- \`## 2026-06\` 처럼 **연-월 단위로 그룹**을 나누고, 그 안에서 날짜 오름차순.
- 각 항목은 한 줄로:
  \`- **YYYY-MM-DD** \\\`종류\\\` [파일명](상대경로) — 한 줄 훅\`
- 훅은 제목을 그대로 베끼지 말고, 뭘 조사/구현/실행한 문서인지 한눈에 알게 짧게 요약해라.
- 제목이 비었거나 불명확하면 파일명에서 유추해 달아라.

## 2부: 주제별 색인 (검색·참조용 크로스 인덱스)
- 1부 아래에 \`---\` 구분선 후 \`## 주제별 색인\` 섹션으로 붙여라.
- 카테고리는 내용에서 자연스럽게 도출해라(예: 라우팅/코스팅, 내비게이션/안내,
  지도/타일/스타일, 위치/GPS, 음성/TTS, UI/화면, 인프라/자동화 등). 억지로 맞추지 말 것.
- 여기서는 **훅을 반복하지 마라** — 링크만 쉼표로 나열해 압축한다:
  \`- **라우팅/코스팅**: [A.md](A.md), [B.md](archive/legacy_sessions/B.md)\`
- 한 문서가 두 주제에 걸치면 양쪽에 넣어도 된다(1부와 달리 중복 허용).

## 3부: 작업 이력 (언제 무슨 작업을 했나)
- 2부 아래에 \`---\` 구분선 후 \`## 작업 이력\` 섹션으로 붙여라.
- **종류가 \`지시서\`·\`리포트\`·\`실주행\`인 문서만** 모아 날짜 **내림차순**(최신이 위)으로 나열.
- 같은 회차의 지시서와 리포트는 가능하면 붙여서 한 줄로 묶어라:
  \`- **2026-07-20** [지시서](HANDOFF_0720_night_14_16.md) → [리포트](MORNING_REPORT_0720_auto.md) — 한 줄 요약\`
- 짝이 없으면 있는 것만 써라.
- 목적: "지난달 밤에 뭘 했지?"를 이 섹션 하나로 답할 수 있게 하는 것. 훅에 그 회차에
  실제로 뭘 했는지(기능명/수정 대상)를 구체적으로 적어라 — "야간 작업" 같은 무의미한
  요약은 쓰지 마라.

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
