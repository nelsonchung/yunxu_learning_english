#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
KEY_PROPERTIES_PATH="$ROOT_DIR/android/key.properties"
OUTPUT_AAB_PATH="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"

if [ ! -f "$PUBSPEC_PATH" ]; then
  echo "找不到 pubspec.yaml，請在 Flutter 專案根目錄下執行。" >&2
  exit 1
fi

version_line="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' "$PUBSPEC_PATH" | head -n 1)"

if [ -z "$version_line" ]; then
  echo "無法從 pubspec.yaml 讀取 version。" >&2
  exit 1
fi

if [[ ! "$version_line" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "目前 version 格式不符合 x.y.z+n：$version_line" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
build="${BASH_REMATCH[4]}"

suggested_patch=$((patch + 1))
suggested_build=$((build + 1))
default_build_name="${major}.${minor}.${suggested_patch}"
default_build_number="$suggested_build"

echo "目前版本：${version_line}"
echo "建議下一版：${default_build_name}+${default_build_number}"
echo

read -r -p "下一版 versionName [${default_build_name}]: " input_build_name
build_name="${input_build_name:-$default_build_name}"

read -r -p "下一版 build number [${default_build_number}]: " input_build_number
build_number="${input_build_number:-$default_build_number}"

if [[ ! "$build_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "versionName 必須是 x.y.z 格式，例如 1.0.4" >&2
  exit 1
fi

if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo "build number 必須是整數，例如 2" >&2
  exit 1
fi

next_version="${build_name}+${build_number}"

perl -0pi -e "s/^version:\\s*[^\\n]+/version: ${next_version}/m" "$PUBSPEC_PATH"

echo
echo "已更新 pubspec.yaml 版本為：${next_version}"
echo

read -r -p "是否立即建立 Android AppBundle? [Y/n]: " should_build
should_build="${should_build:-Y}"

case "$should_build" in
  [Nn]*)
    echo "已略過 build。之後可執行 ./build_app.sh 並選 2) Android (AppBundle)。"
    exit 0
    ;;
esac

if [ ! -f "$KEY_PROPERTIES_PATH" ]; then
  echo "缺少 android/key.properties，無法建立 release AppBundle。" >&2
  echo "請先執行 ./tools/generate_android_keystore.sh" >&2
  exit 1
fi

(
  cd "$ROOT_DIR"
  flutter build appbundle --release
)

echo
if [ -f "$OUTPUT_AAB_PATH" ]; then
  echo "已產出：$OUTPUT_AAB_PATH"
fi
echo "下一步：把新的 app-release.aab 上傳到 Google Play Console。"
