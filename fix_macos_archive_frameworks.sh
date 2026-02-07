#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./fix_macos_archive_frameworks.sh
#   ./fix_macos_archive_frameworks.sh YunxuLearn
#   ./fix_macos_archive_frameworks.sh YunxuLearn "/path/to/archive.xcarchive"

APP_NAME="${1:-YunxuLearn}"
ARCHIVE_PATH="${2:-}"
EXPECTED_LINK="Versions/Current/Resources"

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$(ls -td "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$ARCHIVE_PATH" || ! -d "$ARCHIVE_PATH" ]]; then
  echo "FAIL: 找不到可用的 .xcarchive"
  exit 1
fi

APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  FIRST_APP="$(ls -d "$ARCHIVE_PATH"/Products/Applications/*.app 2>/dev/null | head -n 1 || true)"
  if [[ -z "$FIRST_APP" ]]; then
    echo "FAIL: 在 archive 找不到 app bundle"
    echo "Archive: $ARCHIVE_PATH"
    exit 1
  fi
  APP_BUNDLE="$FIRST_APP"
  APP_NAME="$(basename "$APP_BUNDLE" .app)"
fi

FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
if [[ ! -d "$FRAMEWORKS_DIR" ]]; then
  echo "FAIL: 找不到 Frameworks 目錄"
  echo "App: $APP_BUNDLE"
  exit 1
fi

echo "Archive: $ARCHIVE_PATH"
echo "App: $APP_NAME"
echo

shopt -s nullglob
frameworks=("$FRAMEWORKS_DIR"/*.framework)
if [[ ${#frameworks[@]} -eq 0 ]]; then
  echo "FAIL: Frameworks 目錄內沒有 .framework"
  exit 1
fi

fixed_count=0
for fw in "${frameworks[@]}"; do
  [[ -d "$fw/Versions" ]] || continue

  name="$(basename "$fw")"
  current="$(readlink "$fw/Resources" || true)"

  if [[ "$current" == "$EXPECTED_LINK" ]]; then
    echo "OK: $name"
    continue
  fi

  if [[ -e "$fw/Resources" || -L "$fw/Resources" ]]; then
    rm -rf "$fw/Resources"
  fi
  ln -s "$EXPECTED_LINK" "$fw/Resources"
  echo "FIXED: $name  Resources -> $EXPECTED_LINK"
  fixed_count=$((fixed_count + 1))
done

echo
echo "修正完成，共修正 $fixed_count 個 framework。"

CHECK_SCRIPT="$(cd "$(dirname "$0")" && pwd)/check_macos_archive_frameworks.sh"
if [[ -x "$CHECK_SCRIPT" ]]; then
  echo
  echo "重新驗證："
  "$CHECK_SCRIPT" "$APP_NAME" "$ARCHIVE_PATH"
else
  echo "WARN: 找不到可執行的 check_macos_archive_frameworks.sh，請手動驗證。"
fi
