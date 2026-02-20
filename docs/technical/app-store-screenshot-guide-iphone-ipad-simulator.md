# App Store 上架截圖指南（iPhone + iPad，使用 iOS 模擬器）

- Date: 2026-02-12
- Scope: App Store Connect 上架截圖產製流程（無實體裝置）
- Target: iPhone + iPad

## 1. 背景
若手上沒有對應的 iPhone 或 iPad 實體裝置，仍可使用 Xcode iOS Simulator 產製可上傳到 App Store Connect 的截圖。

本文件固定使用以下模擬器：
1. iPhone：`iPhone 14 Plus`
2. iPad：`iPad Pro 13-inch`（可用任一 `M4/M5` 版本）

## 2. App Store Connect 截圖要求（本文件撰寫時）
1. iPhone：提供 6.5" 截圖。`iPhone 14 Plus` 屬於 6.5" 類別。
2. iPad：只要 App 支援 iPad，建議直接提供 13" 截圖（`iPad Pro 13-inch`）。
3. 每個裝置類別可上傳 1-10 張，格式支援 `png/jpg/jpeg`。

> Apple 會不定期更新規格；實際上傳前請再核對：
> https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

## 3. 前置準備
1. 安裝 Xcode（含對應 iOS Simulator Runtime）。
2. 在 Xcode -> Settings -> Platforms 確認已下載可建立 `iPhone 14 Plus` 與 `iPad Pro 13-inch` 的 runtime。
3. Flutter 專案建議避免 Debug 標記污染截圖：
   - 可參考：`/Users/nelsonchung/development/yunxu_learning_english/docs/technical/flutter-hide-debug-banner-on-simulator.md`

## 4. 操作流程（手動）
1. 啟動模擬器裝置：
   - iPhone：`iPhone 14 Plus`
   - iPad：`iPad Pro 13-inch`
2. 以接近上架畫面的方式執行 App（建議使用 Release/Profile 內容畫面）。
3. 在每個頁面整理好文案、資料與 UI 狀態後截圖。
4. 截圖方式：
   - Simulator 功能列 `File -> Save Screen Shot`
   - 或快捷鍵 `Command + S`
5. 將 iPhone 與 iPad 截圖分資料夾整理，最後上傳到 App Store Connect。


## 5. 上傳前檢查清單
- [ ] iPhone 與 iPad 截圖都有準備（不要只上傳單一類別）
- [ ] 同一類別內的截圖方向一致（都直向或都橫向）
- [ ] 畫面沒有 Debug 標記、測試資料或開發用按鈕
- [ ] 文案語系與 App Store 頁面語系一致
- [ ] 截圖內容涵蓋核心功能（首頁、重點功能、設定/個人化）

## 6. 常見問題
1. 找不到 `iPad Pro 13-inch`：
   - 通常是 Xcode runtime 未安裝，先到 Xcode 平台設定下載。
2. 上傳時被拒絕尺寸不符：
   - 使用原始模擬器截圖，不要先經過二次裁切或即時通訊軟體壓縮。
3. iPhone 只準備 `iPhone 14 Plus` 會不會不行：
   - 目前可作為 6.5" 類別。
