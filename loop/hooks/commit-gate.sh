#!/usr/bin/env bash
FLUTTER="/data/projects/flutter/bin/flutter"
input=$(cat)

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$cmd" != *"git commit"* ]]; then
  exit 0   # git commit 아니면 통과
fi

echo "GATE: flutter analyze + test 실행 중..." >&2

if ! "$FLUTTER" analyze; then
  echo "BLOCKED: flutter analyze 실패. 커밋 전 에러 수정." >&2
  exit 2   # exit 2 = 차단, Claude에게 stderr 메시지 전달
fi

if ! "$FLUTTER" test; then
  echo "BLOCKED: flutter test 실패(51/51 필요)." >&2
  exit 2
fi

exit 0