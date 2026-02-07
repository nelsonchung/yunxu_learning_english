#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./check_macos_archive_frameworks.sh
#   ./check_macos_archive_frameworks.sh YunxuLearn
#   ./check_macos_archive_frameworks.sh YunxuLearn "/path/to/archive.xcarchive"

APP_NAME="${1:-YunxuLearn}"
ARCHIVE_PATH="${2:-}"

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$(ls -td "$HOME"/Library/Developer/Xcode/Archives/*/*.xcarchive 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$ARCHIVE_PATH" || ! -d "$ARCHIVE_PATH" ]]; then
  echo "FAIL: 找不到可用的 .xcarchive"
  exit 1
fi

APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  # Fallback: if app name changed, pick first app under archive.
  FIRST_APP="$(ls -d "$ARCHIVE_PATH"/Products/Applications/*.app 2>/dev/null | head -n 1 || true)"
  if [[ -n "$FIRST_APP" ]]; then
    APP_BUNDLE="$FIRST_APP"
    APP_NAME="$(basename "$APP_BUNDLE" .app)"
  else
    echo "FAIL: 在 archive 找不到 app bundle"
    echo "Archive: $ARCHIVE_PATH"
    exit 1
  fi
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

expected="Versions/Current/Resources"
fail_count=0

check_one_framework() {
  local fw="$1"
  local name
  local resources_link
  local current_link
  name="$(basename "$fw")"

  # Only check versioned frameworks.
  if [[ ! -d "$fw/Versions" ]]; then
    return 0
  fi

  resources_link="$(readlink "$fw/Resources" || true)"
  current_link="$(readlink "$fw/Versions/Current" || true)"

  if [[ "$resources_link" == "$expected" ]]; then
    echo "PASS: $name  Resources -> $resources_link"
  else
    echo "FAIL: $name  Resources -> ${resources_link:-<missing>} (expected $expected)"
    fail_count=$((fail_count + 1))
  fi

  if [[ -z "$current_link" ]]; then
    echo "WARN: $name  Versions/Current 不是 symlink"
  fi
}

shopt -s nullglob
frameworks=("$FRAMEWORKS_DIR"/*.framework)
if [[ ${#frameworks[@]} -eq 0 ]]; then
  echo "FAIL: Frameworks 目錄內沒有 .framework"
  exit 1
fi

# Prioritize the framework from the Apple rejection email.
if [[ -d "$FRAMEWORKS_DIR/objective_c.framework" ]]; then
  check_one_framework "$FRAMEWORKS_DIR/objective_c.framework"
else
  echo "WARN: 沒有找到 objective_c.framework"
fi

for fw in "${frameworks[@]}"; do
  [[ "$(basename "$fw")" == "objective_c.framework" ]] && continue
  check_one_framework "$fw"
done

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "RESULT: PASS (可上傳)"
  exit 0
else
  echo "RESULT: FAIL ($fail_count 個 framework 不符合)"
  exit 2
fi
