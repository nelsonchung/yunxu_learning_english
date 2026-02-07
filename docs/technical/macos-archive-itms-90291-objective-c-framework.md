# macOS Archive 上傳 ITMS-90291 排查紀錄

本文件記錄一次 macOS 版上傳 App Store Connect 失敗（`ITMS-90291`）的完整排查與最終可行流程。

## 問題背景
- 專案可正常執行：
  - `flutter build macos --release` 成功
  - Xcode `Product -> Archive` 成功
- 但上傳 App Store Connect 後收到 Apple 信件：
  - `ITMS-90291: Malformed Framework`
  - `objective_c.framework` 缺少正確 symlink：
    - 期待：`Resources -> Versions/Current/Resources`
    - 實際：`Resources -> Versions/A/Resources`

## 關鍵觀念
1. `.xcarchive` 是 **Xcode 產生**。
2. 但 archive 內的某些 framework 來自外部建置鏈（Flutter/Dart native assets），再被 Xcode 打包。
3. Apple 驗證的是「最終上傳的 archive 內容」。
4. 因此只要在上傳前修正 archive 內 framework 結構，重新驗證後再上傳即可生效。

## 根因判斷結論
- 問題不在 Xcode 是否太舊（本案例 Xcode 16.2）。
- 問題點是 `objective_c.framework` 的 symlink 結構不符合 Apple Framework Anatomy 規範。
- `objective_c` 是 Flutter 依賴鏈中的 transitive 套件，不是 Apple 內部工具。

## 這次可用的標準流程
1. 在 Xcode 執行 `Product -> Archive`。
2. **先不要上傳**。
3. 在專案根目錄執行：
   - `./fix_macos_archive_frameworks.sh`
   - `./check_macos_archive_frameworks.sh`
4. 確認檢查結果為 `RESULT: PASS (可上傳)`。
5. 回 Xcode Organizer 上傳同一個 archive。

> 注意：每次重新 Archive 都會產生新的 `.xcarchive`，需要重新執行 `fix + check`。

## 已加入的腳本
- `check_macos_archive_frameworks.sh`
  - 用途：檢查最新（或指定）archive 內所有 versioned framework 的 `Resources` symlink 是否正確。
- `fix_macos_archive_frameworks.sh`
  - 用途：修正最新（或指定）archive 內不符合規範的 framework symlink，並自動呼叫 check 再驗證。

## 指令範例
```bash
cd /Users/nelsonchung/development/yunxu_learning_english

# 修正最新 archive（預設 app 名稱 YunxuLearn）
./fix_macos_archive_frameworks.sh

# 再次驗證
./check_macos_archive_frameworks.sh
```

指定 archive 的用法：
```bash
./fix_macos_archive_frameworks.sh YunxuLearn "/Users/nelsonchung/Library/Developer/Xcode/Archives/2026-02-07/Runner 2026-2-7, 9.16 AM.xcarchive"
./check_macos_archive_frameworks.sh YunxuLearn "/Users/nelsonchung/Library/Developer/Xcode/Archives/2026-02-07/Runner 2026-2-7, 9.16 AM.xcarchive"
```

## 驗收標準
- App Store Connect `TestFlight -> macOS 建置版本` 中，該 build 狀態為 `完成`。
- 不再收到 `ITMS-90291`（或同 build 沒有該驗證錯誤）。

## 相關參考
- Apple: Framework Anatomy（symlink 規範）
  - https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html
