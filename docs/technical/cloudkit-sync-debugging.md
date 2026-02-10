# CloudKit 同步問題排查與建立紀錄

本文件紀錄一次「iOS / macOS Release 同步失敗」的排查流程與關鍵結論，包含 CloudKit Dashboard 操作、Schema 建立、索引設定與同步觸發條件。

## 問題背景
- iOS 已新增單字，但 macOS 沒有同步（單字數仍為 0）。
- 兩端都使用 release 版本執行。

## 根因與關鍵結論
1) **CloudKit Production 缺少 Record Type**
   - Release 使用 Production 環境，若 `WordCard` 在 Production 不存在，會出現：
     - `Did not find record type: WordCard`
2) **macOS Release 需要網路權限**
   - `macos/Runner/Release.entitlements` 必須包含：
     - `com.apple.security.network.client`
3) **同步觸發條件**
   - 同步目前僅在以下時機觸發：
     - App 啟動時
     - 本地新增/更新/刪除時
   - App 開啟後不會自動輪詢，需重啟或手動觸發。
4) **CloudKit 查詢時間為 UTC**
   - Dashboard 查詢時若用 `updatedAt > 某時間`，需注意 UTC 時區換算，避免誤判「沒有資料」。

## CloudKit Dashboard 操作步驟
### 1. 進入 CloudKit Database
- Apple Developer Account → CloudKit → CloudKit Dashboard
- Container：`iCloud.com.yunxu.yunxulearn`
- Environment：`Development`

### 2. 建立 Record Type（WordCard）
> 如果 `WordCard` 不存在，需要新增並建立欄位

必要欄位與型別：
- `word` (String)
- `meaning` (String)
- `partOfSpeech` (String)
- `sentences` (String, List)
- `reviewSchedule` (Int64, List)
- `nextReviewIndex` (Int64)
- `createdAt` (Date/Time)
- `updatedAt` (Date/Time)
- `nextReviewDate` (Date/Time)
- `history` (Date/Time, List)
- `isDeleted` (Int64)
- `image` (Asset)

> 備註：若 UI 不提供 Boolean，可用 Int64（0/1）存 `isDeleted`。

### 3. 建立 Index（updatedAt）
- 需要兩個索引：
  - `updatedAt` Queryable
  - `updatedAt` Sortable

### 4. Deploy 到 Production
- 左下 `Deploy Schema Changes...`
- 切換到 Production 環境確認 `WordCard` 與 Index 存在

## 如何驗證資料是否上傳
1) Data → Records
2) Database：Private Database
3) Act as iCloud Account（使用同一個 Apple ID）
4) Record Type：WordCard
5) Filter：`updatedAt > 2000-01-01`

> 注意 Dashboard 預設會用 `recordName` 查詢，若未標記 queryable 會出錯。

## Private Database 原理（不同 Apple ID）
- 本專案目前使用 `CKContainer(...).privateCloudDatabase`。
- `WordCard` 是 schema（可理解為資料結構/資料表），不是共享開關。
- 同一個 Apple ID 的 iPhone 與 macOS 會連到同一份私有資料，因此可自動同步。
- 不同 Apple ID 各自有獨立私有資料空間，彼此看不到資料。
- 結論：不同使用者「都可以用」且「都能各自跨裝置同步」，但不會共享同一份單字資料。

> 名詞提醒：本專案使用的 Record Type 名稱是 `WordCard`（不是 `WordType`）。

### 驗證不同 Apple ID 是否可用（但不互通）
1) Apple ID A：在 iPhone 新增單字，確認 A 的 macOS 可同步到該單字。
2) Apple ID B：安裝同版本 App，確認看不到 A 的單字。
3) Apple ID B：自行新增單字，確認 B 的 iPhone/macOS 可互相同步。
4) CloudKit Dashboard（Production / Private Database）分別 `Act as` A 與 B，確認兩邊資料各自存在且互不重疊。

> 若需求是跨 Apple ID 共用同一份資料，需改用 CloudKit sharing（`CKShare` / Shared Database）或 Public Database 設計。

## 同步觸發與補強
- **手動同步**：在「單字列表」標題列已加入同步按鈕
- **定時輪詢**：未實作，可在 App 開啟期間定時呼叫 sync

## 目前新增的程式調整
- macOS entitlements 補上 `com.apple.security.network.client`
- CloudKit 錯誤 logging（iOS/macOS 原生）
- Flutter 端同步錯誤 logging
- UI 新增「手動同步」按鈕

## TestFlight 上線前 CloudKit 檢查清單
- [ ] Apple Developer → CloudKit Dashboard 已切到 `Production`
- [ ] `WordCard` 與必要欄位都存在於 `Production`
- [ ] `updatedAt` 的 Queryable/Sortable index 已存在於 `Production`
- [ ] iOS/macOS 版本都使用同一個 container：`iCloud.com.yunxu.yunxulearn`
- [ ] iOS `Runner.entitlements` 含 iCloud/CloudKit capability
- [ ] macOS `Release.entitlements` 含 iCloud/CloudKit capability 與 `com.apple.security.network.client`
- [ ] 使用 TestFlight 版本（非本機 Debug）進行驗證
- [ ] 測試 Apple ID A：iPhone 新增單字，macOS 可同步收到
- [ ] 測試 Apple ID B：看不到 A 的資料，但 B 自己 iPhone/macOS 可互相同步
- [ ] Dashboard（Production / Private Database）以 `Act as` 檢查 A/B 資料各自獨立

## 快速檢查清單
- [ ] iOS/macOS 使用同一 Apple ID
- [ ] CloudKit Production 有 `WordCard`
- [ ] `updatedAt` 有 Queryable/Sortable index
- [ ] macOS Release entitlements 有 network client
- [ ] 手動同步可正常拉取資料

## 相關文件
- `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudlkit-filter-by-updated.md`
