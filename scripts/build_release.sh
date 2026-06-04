#!/usr/bin/env bash
# 릴리즈 APK 빌드 + 자동 파일명 생성
# 사용법: bash scripts/build_release.sh
# 출력: outputs/yurunavi_vX.X.X_YYYYMMDD.apk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 버전 파싱
VERSION=$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
DATE=$(date +%Y%m%d)
FILENAME="yurunavi_v${VERSION}_${DATE}.apk"
OUTPUTS_DIR="$ROOT/outputs"

mkdir -p "$OUTPUTS_DIR"

echo "빌드 시작: v${VERSION} (${DATE})"
flutter build apk --release 2>&1

APK_SRC="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
APK_DEST="$OUTPUTS_DIR/$FILENAME"

if [[ -f "$APK_SRC" ]]; then
  cp "$APK_SRC" "$APK_DEST"
  echo "완료: $APK_DEST"
  ls -lh "$APK_DEST"
else
  echo "오류: 빌드 결과물을 찾을 수 없습니다: $APK_SRC"
  exit 1
fi
