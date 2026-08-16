#!/usr/bin/env bash
# loop/gen_status.sh — D: Claude 세션 진입점(loop/STATUS.md) 자동 생성
#
# 목적: RELEASE_ROADMAP.md(62KB, 사람용 상세)를 매 세션 통째로 컨텍스트에 넣는 부담을
# 없앤다. Claude는 여기서 생성한 작은 STATUS.md 하나만 읽고, 필요한 항목만 줄번호를
# 따라 상세 문서로 들어간다.
#
# LLM을 쓰지 않는다 — 전부 git/파일에서 결정적으로 추출하므로 빠르고 공짜다.
# 그래서 자주(매일 cron + 야간루프 종료 시) 돌려도 부담이 없고, 늘 최신이라
# 과거 BACKLOG.md처럼 stale해지지 않는다.
#
# 사용법: loop/gen_status.sh
# cron 예: 매일 04:00 →  0 4 * * *  /data/projects/yurunavi/loop/gen_status.sh

set -uo pipefail
cd /data/projects/yurunavi || exit 1

if [ "$(id -u)" -eq 0 ]; then
  echo "FATAL: root로 실행 금지. 일반 계정에서 실행하세요." >&2
  exit 1
fi

OUT="loop/STATUS.md"
ROADMAP="loop/RELEASE_ROADMAP.md"
HANDOFF="loop/.auto/handoff.md"
PID_FILE="loop/.auto/agent_run.pid"
# 임시파일은 반드시 $OUT과 같은 디렉토리에 만든다 — /tmp는 별개 파일시스템이라
# 거기서 mv하면 rename(2)이 아니라 복사가 되어 원자성이 깨진다(중간에 죽으면
# STATUS.md가 잘린 채로 남음).
TMP="$(mktemp "$OUT.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
head_short=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
dirty_n=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# 야간루프 실행 여부 — pid 파일이 있어도 죽은 프로세스일 수 있으니 실제로 살아있는지 확인.
loop_state="정지"
if [ -f "$PID_FILE" ]; then
  pid=$(tr -d ' \n' < "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    loop_state="실행중 (pid $pid)"
  else
    loop_state="정지 (pid 파일은 남아있음 — 비정상 종료 흔적)"
  fi
fi

handoff_line="(없음)"
handoff_when=""
if [ -f "$HANDOFF" ]; then
  handoff_line=$(head -n1 "$HANDOFF" 2>/dev/null)
  handoff_when=$(date -d "@$(stat -c %Y "$HANDOFF" 2>/dev/null || echo 0)" '+%Y-%m-%d %H:%M' 2>/dev/null)
fi

{
  echo "# YuruNavi STATUS — Claude 세션 진입점"
  echo
  echo "> **자동 생성 파일이다. 직접 편집하지 마라 — \`loop/gen_status.sh\` 다음 실행에 덮어써진다.**"
  echo "> 사람이 읽는 상세 문서는 [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)(62KB)다."
  echo "> Claude는 이 파일을 먼저 읽고, 필요한 항목만 아래 줄번호로 찾아 들어가라"
  echo "> (예: \`sed -n '161,183p' loop/RELEASE_ROADMAP.md\`). 로드맵을 통째로 읽지 마라."
  echo
  echo "생성: $(date '+%Y-%m-%d %H:%M') · 브랜치 \`$branch\` · HEAD \`$head_short\`"
  echo

  echo "## 1. 지금 상태"
  echo
  echo "- 야간루프: $loop_state"
  echo "- 마지막 handoff: \`$handoff_line\`${handoff_when:+ (갱신 $handoff_when)}"
  if [ "$dirty_n" -eq 0 ]; then
    echo "- 작업트리: clean"
  else
    echo "- 작업트리: **미커밋 ${dirty_n}건** — 다른 세션 작업일 수 있으니 \`git status\`로 확인 후"
    echo "  내 파일만 골라 스테이징할 것(.ai/GIT_SAFETY.md 규칙: \`git add -A\` 금지)"
  fi
  echo

  echo "## 2. 미완료 릴리스 항목"
  echo
  echo "\`$ROADMAP\`의 \`### N.\` 항목 중 DONE이 아닌 것. 옆 숫자는 그 문서의 줄번호다."
  echo
  if [ -f "$ROADMAP" ]; then
    # 항목 헤딩 형식이 문서 내에서 일관되지 않다('### 13. 제목 — DONE'가 표준이지만
    # '## 17번 — 제목'처럼 쓰인 것도 있음). 미완료 항목이 조용히 누락되면 이 파일을
    # 믿을 수 없게 되므로 두 형식을 모두 잡는다.
    ITEM_RE='^#{2,3} *[0-9]+ *[.번]'
    # DONE만 제외 — PARTIAL/TODO/BLOCKED/무표기는 미완료로 남긴다.
    if grep -nE "$ITEM_RE" "$ROADMAP" 2>/dev/null | grep -qvE '\bDONE\b'; then
      grep -nE "$ITEM_RE" "$ROADMAP" 2>/dev/null \
        | grep -vE '\bDONE\b' \
        | sed -E 's/^([0-9]+):#+ *(.*)$/- **\2**  —  `RELEASE_ROADMAP.md:\1`/'
    else
      echo "- (미완료 항목 없음 — 전부 DONE)"
    fi
  else
    echo "- ⚠️ $ROADMAP 를 못 찾음"
  fi
  echo

  echo "## 3. 최근 실행 결과"
  echo
  found_report=0
  for f in $(ls -t loop/MORNING_REPORT_*.md 2>/dev/null | head -3); do
    found_report=1
    base=$(basename "$f")
    verdict=$(grep -m1 "목표 달성 판정" "$f" 2>/dev/null | sed -E 's/^[[:space:]]*[-*]?[[:space:]]*//' | cut -c1-200)
    echo "- [$base]($base)"
    if [ -n "$verdict" ]; then
      echo "  - $verdict"
    else
      echo "  - _(달성도 판정 줄 없음 — `.ai/REPORTING.md` 달성도 판정 누락)_"
    fi
  done
  [ "$found_report" -eq 0 ] && echo "- (리포트 없음)"
  echo

  echo "## 4. 최근 작업 지시서"
  echo
  found_handoff=0
  for f in $(ls -t loop/HANDOFF_*.md 2>/dev/null | head -3); do
    found_handoff=1
    base=$(basename "$f")
    echo "- [$base]($base)"
  done
  [ "$found_handoff" -eq 0 ] && echo "- (지시서 없음)"
  echo

  echo "## 5. 최근 커밋"
  echo
  echo '```'
  git log --oneline -10 2>/dev/null || echo "(git log 실패)"
  echo '```'
  echo

  echo "## 6. 더 깊이 볼 때"
  echo
  echo "- 과거 조사·구현 색인(RECON/REPORT 전체): [WIKI_INDEX.md](WIKI_INDEX.md)"
  echo "  — 1부 날짜순, 2부 주제별 색인. 새 조사 전에 여기부터 grep할 것."
  echo "- 릴리스 상세(사람용, 통째로 읽지 말 것): [RELEASE_ROADMAP.md](RELEASE_ROADMAP.md)"
  echo "- 인프라 상세: [../docker/INFRA.md](../docker/INFRA.md)"
  echo "- 실주행 피드백 버그픽스 진행: [feedback/BUGFIX_progress.md](feedback/BUGFIX_progress.md)"
} > "$TMP"

# 원자적 교체 — 생성 중 실패해도 기존 STATUS.md가 반쯤 쓰인 상태로 남지 않게.
mv "$TMP" "$OUT"
trap - EXIT
echo "gen_status: $OUT 생성 완료 ($(wc -l < "$OUT" | tr -d ' ')줄)"
