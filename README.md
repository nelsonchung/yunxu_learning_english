# yunxu_learning_english
yunxu推出學習英文的app

## macOS 上傳注意事項（ITMS-90291）
若遇到 Apple 驗證錯誤：
- `ITMS-90291: Malformed Framework`
- `objective_c.framework` 的 `Resources` symlink 不符規範

請使用以下流程：
1. Xcode 執行 `Product -> Archive`
2. 先不要上傳，改到專案根目錄執行：
   - `./fix_macos_archive_frameworks.sh`
   - `./check_macos_archive_frameworks.sh`
3. 確認結果是 `RESULT: PASS (可上傳)` 後，再回 Xcode Organizer 上傳

每次重新 Archive 都要重新執行一次 `fix + check`。

完整排查文件：
- `docs/technical/macos-archive-itms-90291-objective-c-framework.md`
