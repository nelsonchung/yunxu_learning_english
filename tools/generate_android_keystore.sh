#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"
KEYSTORE_PATH="$ANDROID_DIR/app/upload-keystore.jks"
KEY_PROPERTIES_PATH="$ANDROID_DIR/key.properties"
DEFAULT_ALIAS="upload"
DEFAULT_VALIDITY_DAYS=10000
DEFAULT_DNAME="CN=YunxuLearn, OU=Mobile, O=YunxuLearn, L=Taipei, ST=Taiwan, C=TW"

find_keytool() {
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/keytool" ]; then
    echo "${JAVA_HOME}/bin/keytool"
    return 0
  fi

  if [ -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" ]; then
    echo "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
    return 0
  fi

  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    local detected_java_home
    detected_java_home="$(/usr/libexec/java_home 2>/dev/null || true)"
    if [ -n "$detected_java_home" ] && [ -x "${detected_java_home}/bin/keytool" ]; then
      echo "${detected_java_home}/bin/keytool"
      return 0
    fi
  fi

  if command -v keytool >/dev/null 2>&1 && keytool -help >/dev/null 2>&1; then
    command -v keytool
    return 0
  fi

  return 1
}

KEYTOOL_BIN="$(find_keytool || true)"

if [ -z "$KEYTOOL_BIN" ]; then
  echo "找不到可用的 keytool。請安裝 JDK，或確認 Android Studio 內建 JBR 存在。" >&2
  exit 1
fi

if [ -f "$KEYSTORE_PATH" ] || [ -f "$KEY_PROPERTIES_PATH" ]; then
  echo "android/app/upload-keystore.jks 或 android/key.properties 已存在，為避免覆寫，腳本停止。" >&2
  exit 1
fi

read -r -p "Key alias [$DEFAULT_ALIAS]: " KEY_ALIAS
KEY_ALIAS="${KEY_ALIAS:-$DEFAULT_ALIAS}"

read -r -p "Keystore validity days [$DEFAULT_VALIDITY_DAYS]: " VALIDITY_DAYS
VALIDITY_DAYS="${VALIDITY_DAYS:-$DEFAULT_VALIDITY_DAYS}"

read -r -p "Certificate DName [$DEFAULT_DNAME]: " DNAME
DNAME="${DNAME:-$DEFAULT_DNAME}"

read -r -s -p "Store password: " STORE_PASSWORD
echo
read -r -s -p "Confirm store password: " STORE_PASSWORD_CONFIRM
echo
if [ "$STORE_PASSWORD" != "$STORE_PASSWORD_CONFIRM" ]; then
  echo "Store password 不一致。" >&2
  exit 1
fi

read -r -s -p "Key password (enter for same as store password): " KEY_PASSWORD
echo
if [ -z "$KEY_PASSWORD" ]; then
  KEY_PASSWORD="$STORE_PASSWORD"
fi
read -r -s -p "Confirm key password: " KEY_PASSWORD_CONFIRM
echo
if [ -z "$KEY_PASSWORD_CONFIRM" ]; then
  KEY_PASSWORD_CONFIRM="$KEY_PASSWORD"
fi
if [ "$KEY_PASSWORD" != "$KEY_PASSWORD_CONFIRM" ]; then
  echo "Key password 不一致。" >&2
  exit 1
fi

"$KEYTOOL_BIN" -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity "$VALIDITY_DAYS" \
  -alias "$KEY_ALIAS" \
  -dname "$DNAME" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD"

cat > "$KEY_PROPERTIES_PATH" <<EOF
storeFile=app/upload-keystore.jks
storePassword=$STORE_PASSWORD
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASSWORD
EOF

echo
echo "已建立："
echo "  $KEYSTORE_PATH"
echo "  $KEY_PROPERTIES_PATH"
echo
echo "請把 keystore 與密碼安全備份。遺失 upload key 會增加後續維護成本。"
