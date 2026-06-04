#!/usr/bin/env bash
# 버전 bump 스크립트 — patch 버전 +1, pubspec.yaml 자동 수정
# 사용법: bash scripts/bump_version.sh [patch|minor|major]
# 기본값: patch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"

BUMP="${1:-patch}"

# 현재 버전 파싱
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //' | tr -d ' ')
VERSION_PART="${CURRENT%%+*}"   # e.g. 1.0.0
BUILD_PART="${CURRENT##*+}"     # e.g. 1

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_PART"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Usage: $0 [patch|minor|major]" && exit 1 ;;
esac

NEW_BUILD=$((BUILD_PART + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${NEW_BUILD}"

# pubspec.yaml 수정
sed -i "s/^version: .*/version: ${NEW_VERSION}/" "$PUBSPEC"

echo "버전 업데이트: ${CURRENT} → ${NEW_VERSION}"
