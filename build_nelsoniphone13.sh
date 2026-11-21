#!/bin/bash

# 與 build_app.sh 選項 8 相同的 Release 流程，固定使用 nelsoniphone13。
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for required_command in flutter python3; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf '錯誤：需要 %s，請先安裝並加入 PATH。\n' "$required_command" >&2
        exit 1
    fi
done

devices=$(flutter devices --machine)
device_id=$(printf '%s' "$devices" | python3 -c '
import json
import sys

devices = [
    device for device in json.load(sys.stdin)
    if device.get("targetPlatform") == "ios"
    and device.get("emulator") is False
    and device.get("isSupported") is True
]
matches = [
    device for device in devices
    if device.get("name", "").casefold() == "nelsoniphone13"
]
if len(matches) != 1:
    if matches:
        print("錯誤：找到多個同名 nelsoniphone13，請先確認裝置名稱唯一。", file=sys.stderr)
    else:
        print("錯誤：找不到 nelsoniphone13。請連接手機、解鎖並信任此電腦，且開啟開發者模式。", file=sys.stderr)
    for device in devices:
        print("可用 iOS 實機：{} ({})".format(device["name"], device["id"]), file=sys.stderr)
    sys.exit(1)
print(matches[0]["id"])
')

printf '正在編譯並更新 nelsoniphone13 (%s)，使用 Release 模式並停用 iCloud 同步。\n' "$device_id"

# 避免共用輸出目錄殘留模擬器 framework；同時使 Flutter 重建 native assets。
rm -rf build/native_assets/ios
rm -f .dart_tool/flutter_build/*/install_code_assets.stamp
flutter build ios --release --dart-define=ENABLE_IOS_CLOUD_SYNC=false
flutter run -d "$device_id" --release --use-application-binary=build/ios/iphoneos/YunxuLearn.app
