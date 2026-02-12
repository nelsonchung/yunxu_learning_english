# CloudKit Schema 從 Development 部署到 Production

- Date: 2026-02-12
- Container: `iCloud.com.yunxu.yunxulearn`
- Scope: iOS + macOS（CloudKit Private Database）

## 1. 這份流程在解決什麼
CloudKit 有 `Development` 與 `Production` 兩個環境。

每次你在 `Development` 新增或修改 Record Type / 欄位 / Index 後，必須手動執行 `Deploy Schema Changes...` 到 `Production`，否則正式版 App 會因找不到 schema 而失敗。

## 2. 一句話結論
1. Schema：要從 Development deploy 到 Production。
2. 資料：不會自動從 Development 複製到 Production。

## 3. 什麼屬於 Schema
1. Record Type（例如 `WordCard`、`AppSettings`）。
2. 欄位定義（名稱、型別、是否 list）。
3. Index（Queryable / Sortable）。
4. Security Roles（若有調整）。

## 4. 正規操作步驟
1. 進入 CloudKit Dashboard，選 `iCloud.com.yunxu.yunxulearn`。
2. 切到 `Development`，確認要發布的 schema 已完整：
   - `Record Types` 存在且欄位型別正確。
   - `Indexes` 已建立（例如 `updatedAt` queryable/sortable）。
3. 點左下 `Deploy Schema Changes...`。
4. 檢查 deploy 清單（Record Types / Fields / Indexes / Roles）。
5. 確認後執行 deploy。
6. 切換到 `Production`，逐項確認 schema 已存在。

## 5. 發版前最小檢查清單
- [ ] `WordCard` 已在 Production。
- [ ] `AppSettings` 已在 Production。
- [ ] `updatedAt` 相關 Index 已在 Production（依需求 queryable/sortable）。
- [ ] iOS/macOS 使用同一 CloudKit container：`iCloud.com.yunxu.yunxulearn`。
- [ ] 使用 Distribution 版本（TestFlight 或正式簽章）驗證 Production 寫入/讀取。

## 6. 常見誤解
### Q1. 我在 Development 已有資料，Production 會自動有嗎？
不會。Development 與 Production 的資料是分開的。

### Q2. 我跑 `flutter run --release`，是不是一定走 Production？
不一定。本機 release run 常仍屬開發簽章流程，實務上常看到 Development。  
要驗證 Production，建議用 TestFlight 或正式 Distribution 流程。

### Q3. Production 要不要手動新增測試資料？
通常不用。建議透過 Production 版 App 寫入資料，確保流程和真實用戶一致。

## 7. 建議的團隊規範
1. 任何 schema 變更都要附一筆「是否已 deploy 到 Production」勾選紀錄。
2. 每次發版前固定執行本文件的檢查清單。
3. 若有新增欄位，需同步更新技術文件與驗收案例。

## 8. 相關文件
- `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudkit-sync-debugging.md`
- `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudlkit-filter-by-updated.md`
- `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloud-backup-design-spec-v1.md`
