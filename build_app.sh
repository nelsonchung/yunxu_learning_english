#!/bin/bash

# 定義顏色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE}   Flutter 跨平台工具 (編譯與執行)      ${NC}"
echo -e "${BLUE}=======================================${NC}"

# 檢查是否在 Flutter 專案目錄
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}錯誤: 請在 Flutter 專案根目錄執行此腳本${NC}"
    exit 1
fi

run_macos_pod_install() {
    (
        cd macos || exit 1
        LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
    )
}

run_ios_pod_install() {
    (
        cd ios || exit 1
        LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
    )
}

select_ios_release_device() {
    local devices physical_devices device_id device_name selection
    local device_ids=() device_names=()
    command -v python3 >/dev/null 2>&1 || {
        echo -e "${RED}錯誤: 需要 python3 解析 Flutter 裝置清單${NC}"
        return 1
    }
    devices=$(flutter devices --machine) || return 1
    physical_devices=$(printf '%s' "$devices" | python3 -c '
import json, sys
for device in json.load(sys.stdin):
    if (device.get("targetPlatform") == "ios"
            and device.get("emulator") is False
            and device.get("isSupported") is True):
        print(device["id"] + "\t" + device["name"])
') || return 1
    while IFS=$'\t' read -r device_id device_name; do
        [ -n "$device_id" ] || continue
        device_ids+=("$device_id")
        device_names+=("$device_name")
    done <<< "$physical_devices"
    if [ "${#device_ids[@]}" -eq 0 ]; then
        echo -e "${RED}找不到可用的 iOS 實機。請連接 iPhone、解鎖並信任此電腦，且開啟開發者模式後重試。${NC}"
        echo -e "${YELLOW}iOS 模擬器不支援 Release 執行；可用 flutter devices 檢查裝置。${NC}"
        return 1
    fi
    selection=1
    if [ "${#device_ids[@]}" -gt 1 ]; then
        echo "請選擇 iOS 實機："
        for ((selection=0; selection<${#device_ids[@]}; selection++)); do
            printf '%s) %s (%s)\n' "$((selection + 1))" "${device_names[$selection]}" "${device_ids[$selection]}"
        done
        read -r -p "請輸入裝置編號: " selection || return 1
        case "$selection" in
            ''|*[!0-9]*) echo "無效的裝置編號"; return 1 ;;
        esac
        # Compare against valid indices without evaluating user input as arithmetic.
        local index matched=false
        for ((index=1; index<=${#device_ids[@]}; index++)); do
            if [ "$selection" = "$index" ]; then matched=true; break; fi
        done
        if [ "$matched" != true ]; then
            echo "無效的裝置編號"
            return 1
        fi
    fi
    ios_release_device_id="${device_ids[$((selection - 1))]}"
    echo "使用 iOS 實機：${device_names[$((selection - 1))]} ($ios_release_device_id)"
}

run_ios_release() {
    local ios_release_device_id
    select_ios_release_device || return 1
    build_and_run_ios_release
}

build_and_run_ios_release() {
    # Flutter can reuse simulator frameworks from this shared output directory.
    # Invalidate Flutter's install stamps as well so it recreates the output.
    rm -rf build/native_assets/ios &&
    rm -f .dart_tool/flutter_build/*/install_code_assets.stamp &&
    flutter build ios --release --dart-define=ENABLE_IOS_CLOUD_SYNC=false &&
    flutter run -d "$ios_release_device_id" --release --use-application-binary=build/ios/iphoneos/YunxuLearn.app
}

clean_and_run_ios_release() {
    if [ ! -f "ios/Podfile" ]; then
        echo -e "${RED}錯誤: 找不到 ios/Podfile，請確認此專案使用 iOS CocoaPods${NC}"
        return 1
    fi

    local ios_release_device_id
    select_ios_release_device || return 1
    echo -e "${YELLOW}適用於升級 macOS / Xcode 後重新建置 iOS App，首次編譯可能較久${NC}"
    flutter clean &&
    flutter pub get &&
    run_ios_pod_install &&
    build_and_run_ios_release
}

current_project_version() {
    sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1
}

require_android_release_signing() {
    if [ ! -f "android/key.properties" ]; then
        echo -e "${RED}缺少 android/key.properties${NC}"
        echo -e "${YELLOW}先執行 ./tools/generate_android_keystore.sh，或複製 android/key.properties.example 後填入正式 keystore 設定。${NC}"
        return 1
    fi
}

build_android_release_apk() {
    require_android_release_signing || return 1
    flutter build apk --release --split-per-abi
}

build_android_release_appbundle() {
    require_android_release_signing || return 1
    flutter build appbundle --release
    local bundle_path="build/app/outputs/bundle/release/app-release.aab"
    if [ -f "$bundle_path" ]; then
        echo -e "${GREEN}AAB 產物：${bundle_path}${NC}"
    fi
}

show_menu() {
    echo -e "\n${GREEN}請選擇動作:${NC}"
    echo -e "${BLUE}目前版本：$(current_project_version)${NC}"
    echo "1) Android (APK)"
    echo "2) Android (AppBundle)"
    echo "3) iOS (build)"
    echo "4) macOS Desktop (build)"
    echo "5) Windows Desktop (僅限 Windows)"
    echo "6) Linux Desktop (僅限 Linux)"
    echo "7) Web"
    echo "---------------------------------------"
    echo -e "${YELLOW}8) iOS 裝置 Release 執行 (Personal Team，停用 iCloud)${NC}"
    echo -e "${YELLOW}9) macOS Release 執行 (flutter run -d macos --release)${NC}"
    echo "10) macOS Debug 執行 (flutter run -d macos)"
    echo "11) 清理專案 (flutter clean + flutter pub get + macOS pod install)"
    echo "12) Xcode Archive 前準備 (11 + flutter build macos --release)"
    echo "13) 修正並檢查最新 macOS Archive (fix + check)"
    echo "14) macOS DMG (build + package)"
    echo "15) 產生 Android upload keystore"
    echo "16) 準備下一個 Google Play 版本"
    echo "17) iOS 清理並 Release 執行 (clean + pub get + iOS pod install + run)"
    echo "---------------------------------------"
    echo "q) 退出 (Quit)"
    echo -ne "${BLUE}請輸入選項: ${NC}"
}

while true; do
    show_menu
    read choice
    case $choice in
        1) build_android_release_apk ;;
        2) build_android_release_appbundle ;;
        3) flutter build ios --release ;;
        4) flutter build macos --release ;;
        5) flutter build windows --release ;;
        6) flutter build linux --release ;;
        7) flutter build web --release ;;
        8)
            echo -e "${YELLOW}提示: 請確保 iPhone 已連線並開啟開發者模式${NC}"
            echo -e "${YELLOW}提示: Personal Team 不支援 iCloud capability，此版本會停用 iCloud 同步功能${NC}"
            run_ios_release ;;
        9) flutter run -d macos --release ;;
        10) flutter run -d macos ;;
        11)
            flutter clean &&
            flutter pub get &&
            run_macos_pod_install ;;
        12)
            flutter clean &&
            flutter pub get &&
            run_macos_pod_install &&
            flutter build macos --release ;;
        13)
            ./fix_macos_archive_frameworks.sh &&
            ./check_macos_archive_frameworks.sh ;;
        14) ./build_dmg.sh ;;
        15) ./tools/generate_android_keystore.sh ;;
        16) ./tools/prepare_google_play_release.sh ;;
        17) clean_and_run_ios_release ;;
        q) echo "離開程式..."; exit 0 ;;
        *) echo -e "${RED}無效選項${NC}" ;;
    esac

    # 檢查指令執行結果
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✔ 指令執行成功！${NC}"
    else
        echo -e "\n${RED}✘ 指令執行失敗，請檢查錯誤訊息。${NC}"
    fi
done
