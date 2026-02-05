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

show_menu() {
    echo -e "\n${GREEN}請選擇動作:${NC}"
    echo "1) Android (APK)"
    echo "2) Android (AppBundle)"
    echo "3) iOS (build)"
    echo "4) macOS Desktop (build)"
    echo "5) Windows Desktop (僅限 Windows)"
    echo "6) Linux Desktop (僅限 Linux)"
    echo "7) Web"
    echo "---------------------------------------"
    echo -e "${YELLOW}8) 在裝置上執行 Release 模式 (flutter run --release)${NC}"
    echo "9) macOS Debug 執行 (flutter run -d macos)"
    echo "10) 清理專案 (flutter clean + flutter pub get)"
    echo "---------------------------------------"
    echo "q) 退出 (Quit)"
    echo -ne "${BLUE}請輸入選項: ${NC}"
}

while true; do
    show_menu
    read choice
    case $choice in
        1) flutter build apk --release --split-per-abi ;;
        2) flutter build appbundle --release ;;
        3) flutter build ios --release ;;
        4) flutter build macos --release ;;
        5) flutter build windows --release ;;
        6) flutter build linux --release ;;
        7) flutter build web --release ;;
        8) 
            echo -e "${YELLOW}提示: 請確保手機已連線並開啟開發者模式${NC}"
            flutter run --release ;;
        9) flutter run -d macos ;;
        10)
            flutter clean
            flutter pub get ;;
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
