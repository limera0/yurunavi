#!/usr/bin/env bash
# YuruNavi 통합 점검 스크립트
# 사용법: bash scripts/check_all.sh [--skip-validate]
# 종료 코드: 0=전체 PASS, 1=하나 이상 FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKIP_VALIDATE=false

for arg in "$@"; do
  [[ "$arg" == "--skip-validate" ]] && SKIP_VALIDATE=true
done

# ANSI 색상
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

OVERALL=0

# ── 1. flutter analyze ────────────────────────────────────────────────────────
info "1/3  flutter analyze …"
if flutter analyze --no-pub 2>&1; then
  pass "flutter analyze"
else
  fail "flutter analyze"
  OVERALL=1
fi

# ── 2. cargo test ─────────────────────────────────────────────────────────────
info "2/3  cargo test (native/) …"
if (cd "$ROOT/native" && cargo test 2>&1); then
  pass "cargo test"
else
  fail "cargo test"
  OVERALL=1
fi

# ── 3. validate_rural_route.py ────────────────────────────────────────────────
if [[ "$SKIP_VALIDATE" == "true" ]]; then
  info "3/3  validate_rural_route.py skipped (--skip-validate)"
else
  info "3/3  validate_rural_route.py …"
  if python3 "$ROOT/scripts/validate_rural_route.py" 2>&1; then
    pass "validate_rural_route"
  else
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 2 ]]; then
      info "validate_rural_route: Valhalla 미응답 — 서버 없이 CI 실행 시 --skip-validate 사용"
    else
      fail "validate_rural_route (exit $EXIT_CODE)"
      OVERALL=1
    fi
  fi
fi

# ── 요약 ──────────────────────────────────────────────────────────────────────
echo ""
if [[ $OVERALL -eq 0 ]]; then
  echo -e "${GREEN}══ 전체 PASS ══${NC}"
else
  echo -e "${RED}══ 하나 이상 FAIL — 위 로그 확인 ══${NC}"
fi

exit $OVERALL
