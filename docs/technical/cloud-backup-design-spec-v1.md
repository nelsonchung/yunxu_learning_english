# Cloud Data Spec v1 (Sync + Backup + Restore)

- Date: 2026-02-10
- Scope: YunxuLearn
- Platforms: iOS, macOS
- Backend: CloudKit Private Database

## 1. 目標
1. 同 Apple ID 下，iOS / macOS 資料可雙向同步。
2. 使用者可手動觸發備份，確保本機資料完整上傳到雲端。
3. App 重新安裝或手動操作時，可從雲端還原資料到本地。
4. 流程可觀測、可重試、可排查。

## 2. 身分與資料隔離
1. 同 Apple ID 視為同一使用者。
2. 不同 Apple ID 的資料彼此隔離，不互相可見。

## 3. 資料範圍與 RecordType
需要備份/同步：

| 項目 | 說明 | CloudKit RecordType |
|------|------|---------------------|
| 單字資料 | 字詞、詞性、解釋、記憶聯想、例句、建立/更新時間、刪除狀態 | `WordCard` |
| 複習資料 | `history`、`nextReviewDate`、`nextReviewIndex`、`reviewSchedule`（皆為 `WordCard` 欄位） | `WordCard` |
| 設定 | 顯示圖片、提醒相關設定、同步頻率、同步開關 | `AppSettings` |
| 通知偏好 | `reminderEnabled`、`reminderMinutes` | `AppSettings` |
| 圖片資產 | 單字圖片，以 `CKAsset` 存放 | `WordCard.image` |

不備份：
1. 純暫存資料。
2. 可由其他資料推導出的中間狀態。

## 4. 同步資料契約
所有可同步實體至少包含：
1. `id`（穩定主鍵，UUID）
2. `updatedAt`（UTC epoch milliseconds，顯示/除錯用途）
3. `deviceId`（來源裝置識別）
4. `opSeq`（裝置內單調遞增操作序號）
5. `isDeleted`（soft delete / tombstone 標記）

## 5. 衝突與刪除策略
採用 server time 優先的 LWW：
1. 同一筆資料先以 CloudKit server time（`modificationDate`）判定新舊。
2. 若 server time 相同，以 `deviceId + opSeq` 作 tie-breaker。
3. `updatedAt` 不作最終仲裁依據。

刪除策略（soft delete + tombstone）：
1. 刪除資料時，改寫 `isDeleted = true`，不做實體刪除。
2. 刪除操作需更新 `updatedAt`、`deviceId`、`opSeq`。
3. 若一般更新與 tombstone 衝突，tombstone 優先。
4. tombstone 保留至少 30 天；僅在保留期達標且最近同步檢查無落後裝置時可清理。

## 6. 同步（Sync）
定義：雙向增量資料對齊。

觸發：
1. App 啟動：先載入本地，再觸發同步。
2. 本地新增/修改/刪除：觸發同步。
3. 定時同步：`5s`, `10s`, `20s`, `30s`, `60s`, `3600s`（設定可調）。
4. 手動同步：由紀錄頁按鈕觸發。
5. 提供 switch button，允許使用者 enable/disable 同步功能。

流程邊界：
1. 一般情境以 incremental pull/push 為主。
2. 首次安裝或重裝時，走還原流程（見 Section 8）。

## 7. 備份（Backup）
定義：將本機資料完整寫入 CloudKit（非打包單一備份檔）。

觸發：
1. 日常同步流程中的上傳行為。
2. 設定頁手動「立即備份」。

備份形態：
1. `WordCard` 多筆記錄（每筆單字一筆）。
2. `AppSettings` 單筆記錄（`recordName = app_settings`）。

## 8. 還原（Restore）
定義：從 CloudKit 拉取資料回本地（全量拉取 + 合併規則）。

首次啟動判定：
1. 判定依據為本地是否存在任何已備份資料（WordCard 或 AppSettings），而非僅看單字數。
2. 本地判定需搭配 metadata：`hasEverSynced`、`lastRestoreAttemptAt`、`restoreStatus`。
3. 本地無資料時先做 full pull；若雲端無資料則 `newInstall`，有資料且達成最小完整性條件才標記 `restored`。
4. 本地已有資料時執行 merge，套用 Section 5 的衝突與 tombstone 規則。

還原成功最小完整性條件：
1. WordCard 主資料拉取並落地成功（含 tombstone 同步）。
2. AppSettings 拉取並落地成功。
3. 本地 merge 完成且無 blocking error。

圖片資產：
1. `CKAsset` 若部分失敗，不阻擋主流程 restored 判定。
2. 需在紀錄頁顯示警告與待補抓數量（例如 `pendingAssetCount`）。
3. 背景重試 asset 下載，直到成功或使用者手動重試。

使用者視角：
1. 還原開始顯示 `RestoreStatus.restoring`。
2. 完成顯示資料筆數與最後同步時間。
3. 失敗顯示錯誤碼與錯誤描述，提供重試。

## 9. 錯誤碼與 CKError 映射
產品錯誤碼：
1. `icloud_not_signed_in`
2. `icloud_permission_denied`
3. `quota_exceeded`
4. `network_unavailable`
5. `schema_version_mismatch`
6. `server_error`
7. `sync_failed`

最低映射規則：
1. `CKError.notAuthenticated` -> `icloud_not_signed_in`
2. `CKError.permissionFailure` / `CKError.missingEntitlement` -> `icloud_permission_denied`
3. `CKError.quotaExceeded` -> `quota_exceeded`
4. `CKError.networkUnavailable` / `CKError.networkFailure` -> `network_unavailable`
5. `CKError.serviceUnavailable` / `CKError.requestRateLimited` -> `server_error`
6. 其餘錯誤 -> `sync_failed`

## 10. CloudKit 限制與注意事項
1. Private Database 儲存配額取決於使用者 iCloud 方案。
2. `CKAsset` 大小上限依 Apple 官方文件；實作端保守壓縮至 1 MB 內。
3. `CKModifyRecordsOperation` 每次最多 400 筆記錄，超過需分批處理。
4. Settings push 應使用 `CKModifyRecordsOperation` 搭配 `.changedKeys`。
5. Schema/index 排查與 Dashboard 操作見：
   - `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudkit-sync-debugging.md`

## 11. Schema 版本遷移
1. 每個 RecordType 預留 `schemaVersion` 欄位（初始值 `1`）。
2. 雲端版本高於本地可識別版本時，略過不相容記錄並記錄警告。
3. 雲端版本低於本地版本時，本地向上遷移欄位。

## 12. 驗收條件
1. iOS 新增/更新資料後，macOS 可看到一致結果。
2. 刪除 App 後重裝，在同 Apple ID 可還原既有資料。
3. 離線雙端修改後，上線最終能收斂一致。
4. `isDeleted` 能跨裝置傳播，不會被舊資料復活。
5. 超過 400 筆單字時，備份與還原仍能正常完成。
6. 還原後 AppSettings 與原裝置一致。
7. 還原後通知偏好與原裝置一致（僅驗證 App 內偏好值，不等同 OS 授權）。
8. 含圖片單字還原後，圖片可正常下載與顯示。

## 13. 已知實作落差（待修復）
1. P0: 補上 `deviceId + opSeq`。
2. P0: 衝突策略改用 server time（`modificationDate`）。
3. P0: 實作 tombstone 優先規則。
4. P1: 補上 `schemaVersion` 欄位與遷移流程。
5. P1: 還原判定全面對齊 metadata 規則。
6. P2: 錯誤碼分類與 UI 文案完整對齊。

## 14. 非目標
1. 跨 Apple ID 共享資料（`CKShare` / Shared DB）。
2. Android/Web 同步。
3. 還原前本地快照（rollback）機制。

## 15. 相關文件
1. 架構決策（ADR）：
   - `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/adr-cloud-backup-cloudkit-private-db.md`
