#!/usr/bin/env bash
# Claude commit gate: run checks for the staged code surface only.
set -uo pipefail

FLUTTER="/data/projects/flutter/bin/flutter"
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ "$cmd" == *"git commit"* ]] || exit 0

mapfile -t staged < <(git diff --cached --name-only --diff-filter=ACMR)
((${#staged[@]})) || { echo "BLOCKED: staged files 없음." >&2; exit 2; }

need_flutter=false
need_rust=false
for f in "${staged[@]}"; do
  case "$f" in
    lib/*|test/*|pubspec.yaml|pubspec.lock|analysis_options.yaml|l10n.yaml) need_flutter=true ;;
    native/*.toml|native/*.lock|native/src/*) need_rust=true ;;
  esac
done

if $need_flutter; then
  echo "GATE: staged Flutter surface — analyze + complete test suite" >&2
  "$FLUTTER" analyze || { echo "BLOCKED: flutter analyze 실패." >&2; exit 2; }
  "$FLUTTER" test || { echo "BLOCKED: 현재 전체 flutter test 실패." >&2; exit 2; }
fi
if $need_rust; then
  echo "GATE: staged Rust surface — cargo build + test" >&2
  (cd native && cargo build && cargo test) || { echo "BLOCKED: Rust build/test 실패." >&2; exit 2; }
fi
if ! $need_flutter && ! $need_rust; then
  echo "GATE: staged docs/config/automation only — surface-specific checks are the orchestrator's responsibility" >&2
fi
exit 0
