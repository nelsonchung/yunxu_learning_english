#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

PUBSPEC_FILE="pubspec.yaml"
APP_INFO_FILE="macos/Runner/Configs/AppInfo.xcconfig"
MACOS_PODFILE="macos/Podfile"

SKIP_BUILD=0
OUTPUT_PATH=""
VOLUME_NAME=""

usage() {
    cat <<'EOF'
Usage: ./build_dmg.sh [options]

Options:
  --skip-build         Package the existing macOS release app without rebuilding
  --output <path>      Override the output DMG path
  --volname <name>     Override the mounted DMG volume name
  --help               Show this help message
EOF
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

read_app_name() {
    local value
    value="$(sed -n 's/^PRODUCT_NAME = //p' "$APP_INFO_FILE" | tail -n 1)"
    value="$(trim "$value")"
    [[ -n "$value" ]] || fail "Unable to read PRODUCT_NAME from $APP_INFO_FILE"
    printf '%s' "$value"
}

read_version() {
    local value
    value="$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC_FILE" | head -n 1)"
    value="$(trim "${value%%+*}")"
    [[ -n "$value" ]] || fail "Unable to read version from $PUBSPEC_FILE"
    printf '%s' "$value"
}

sanitize_filename() {
    printf '%s' "$1" | tr ' /' '--'
}

run_macos_pod_install() {
    if [[ -f "$MACOS_PODFILE" ]]; then
        (
            cd macos
            LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
        )
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --output)
            [[ $# -ge 2 ]] || fail "--output requires a path"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --volname)
            [[ $# -ge 2 ]] || fail "--volname requires a value"
            VOLUME_NAME="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

[[ -f "$PUBSPEC_FILE" ]] || fail "Run this script from the Flutter project root"
[[ -f "$APP_INFO_FILE" ]] || fail "Missing $APP_INFO_FILE"

require_command flutter
require_command hdiutil
if [[ $SKIP_BUILD -eq 0 ]]; then
    require_command pod
fi

APP_NAME="$(read_app_name)"
VERSION="$(read_version)"
SAFE_APP_NAME="$(sanitize_filename "$APP_NAME")"
APP_BUNDLE_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="build/dmg/${SAFE_APP_NAME}"
STAGING_CONTENT_DIR="${STAGING_DIR}/content"

if [[ -z "$VOLUME_NAME" ]]; then
    VOLUME_NAME="$APP_NAME"
fi

if [[ -z "$OUTPUT_PATH" ]]; then
    OUTPUT_PATH="dist/${SAFE_APP_NAME}-${VERSION}-macos.dmg"
fi

if [[ $SKIP_BUILD -eq 0 ]]; then
    flutter pub get
    run_macos_pod_install
    flutter build macos --release
fi

[[ -d "$APP_BUNDLE_PATH" ]] || fail "Missing app bundle: $APP_BUNDLE_PATH"

mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -rf "$STAGING_DIR"
rm -f "$OUTPUT_PATH"
mkdir -p "$STAGING_CONTENT_DIR"

cp -R "$APP_BUNDLE_PATH" "$STAGING_CONTENT_DIR/"
ln -s /Applications "$STAGING_CONTENT_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_CONTENT_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_PATH"

echo "Created DMG: $OUTPUT_PATH"
