# Cloud Backup & Restore Spec v1 (iOS + macOS)

- Date: 2026-02-10
- Scope: YunxuLearn
- Platforms: iOS, macOS
- Backend: CloudKit Private Database

## 1. 目標
1. 使用者在同 Apple ID 下可自動備份資料到雲端。
2. App 重新安裝後，可從雲端還原既有資料。
3. 還原流程可觀測、可重試、可排查。

## 2. 備份範圍

需要備份：

| 項目 | 說明 | CloudKit RecordType |
|------|------|---------------------|
| 單字資料 | 字詞、詞性、解釋、例句、建立/更新時間、刪除狀態 | `WordCard` |
| 複習資料 | `history`、`nextReviewDate`、`nextReviewIndex`、`reviewSchedule`（皆為 `WordCard` 的欄位，非獨立 RecordType） | `WordCard` |
| 設定 | 顯示圖片、提醒相關設定、同步頻率 | `AppSettings` |
| 通知偏好 | 啟用狀態（`reminderEnabled`）、提醒時間（`reminderMinutes`） | `AppSettings` |
| 圖片資產 | 單字圖片，以 `CKAsset` 存放 | `WordCard.image` |

不備份：
1. 純暫存資料。
2. 可由其他資料推導出的中間狀態。

## 3. 身分與權限模型
1. 同 Apple ID 視為同一使用者，可還原同一份私有資料。
2. 不同 Apple ID 彼此隔離，無法共享同一份資料。

## 4. 備份觸發
1. 本地新增/修改/刪除資料時觸發上傳。
2. 定時同步與手動同步會帶動備份進行。
3. 同步細節與衝突規則定義於 [cloud-sync.md](./cloud-sync.md)。

## 5. 首次啟動與還原判定

判定依據：**本地是否存在任何已備份資料（WordCard 或 AppSettings）**，而非僅看單字數。
避免使用者雲端只有設定但無單字時被誤判為新用戶。

本地判定不直接依賴「AppSettings 是否為預設值」，需搭配同步狀態 metadata：
1. `hasEverSynced`（是否曾成功完成至少一次同步或還原）。
2. `lastRestoreAttemptAt` / `lastRestoreStatus`（最近一次還原嘗試狀態）。
3. 啟動時以「資料存在性 + metadata」共同判定流程分支，避免誤判。

當啟動時本地無任何已備份資料（WordCard = 0 且無 AppSettings record）：
1. 先執行一次完整雲端拉取（full pull），同時拉取 WordCard 與 AppSettings。
2. 若拉取後全部仍無資料：判定為「新安裝用戶」（`RestoreStatus.newInstall`）。
3. 若拉取後有資料：需先檢查 Section 5.2 的最小完整性條件；符合才判定為「重新安裝還原成功」（`RestoreStatus.restored`），否則標記為 `RestoreStatus.failed` 並提供可重試狀態。

當啟動時本地已有任何已備份資料：
1. 執行雲端拉取後做 merge。
2. merge 需套用 [cloud-sync.md](./cloud-sync.md) 的衝突與 tombstone 規則。

注意：
1. 需區分「雲端真的空」與「網路/權限失敗」。
2. 若同步失敗，不可直接判為新用戶，需顯示可重試狀態（`RestoreStatus.failed`）。

### 5.1 大量資料還原策略
1. Full pull 使用 `CKQueryOperation` cursor 分頁拉取，避免單次請求過大。
2. 還原期間 UI 應顯示「還原中」狀態；若可取得已拉取筆數，可顯示進度。
3. push 端使用 `CKModifyRecordsOperation` 時，每批次不超過 400 筆記錄（CloudKit 上限）。

### 5.2 還原成功最小完整性條件
`RestoreStatus.restored` 僅在以下條件同時成立時可標記：
1. WordCard 主資料拉取並落地成功（含 tombstone 同步）。
2. AppSettings 拉取並落地成功。
3. 本地 merge 完成，且未出現 blocking error（例如 schema 不相容、寫入失敗）。

圖片資產（`CKAsset`）若有部分失敗：
1. 不阻擋主流程資料還原完成判定。
2. 必須在紀錄頁顯示警告與待補抓數量（例如 `pendingAssetCount`）。
3. 背景重試 asset 下載，直到成功或使用者手動重試。

## 6. 還原流程（使用者視角）
1. 安裝/重裝後第一次啟動，紀錄頁顯示「還原中」狀態（`RestoreStatus.restoring`）。
2. 完成後顯示還原結果（資料筆數、最後同步時間）。
3. 失敗時可重試，並保留錯誤訊息（錯誤代碼 + 錯誤描述）供支援排查。

### 6.1 錯誤碼對照表

| 錯誤碼 | 情境 | 使用者可見訊息 | 建議動作 |
|--------|------|---------------|----------|
| `icloud_not_signed_in` | 裝置未登入 iCloud 帳號 | 「請先登入 iCloud」 | 引導至系統設定 |
| `icloud_permission_denied` | 使用者拒絕 App 使用 iCloud | 「請允許本 App 使用 iCloud」 | 引導至系統設定 > App 權限 |
| `quota_exceeded` | iCloud 儲存空間不足 | 「iCloud 空間不足，無法備份」 | 提示使用者清理空間或升級方案 |
| `network_unavailable` | 無網路連線 | 「無法連線，請檢查網路」 | 自動重試（依同步排程） |
| `schema_version_mismatch` | 雲端記錄 `schemaVersion` 高於本地 App 可識別版本 | 「請更新 App 至最新版本」 | 略過不相容記錄，記錄警告日誌 |
| `server_error` | CloudKit 伺服器端錯誤 | 「雲端服務暫時無法使用」 | 自動重試（指數退避） |
| `sync_failed` | 其他未分類同步錯誤 | 「同步失敗，請稍後重試」 | 記錄完整錯誤至日誌，可手動重試 |

### 6.2 CKError 對照規則（實作指引）
Swift/Dart 層需先將 CloudKit 原生錯誤映射為產品錯誤碼，最低要求如下：
1. `CKError.notAuthenticated` -> `icloud_not_signed_in`
2. `CKError.permissionFailure` / `CKError.missingEntitlement` -> `icloud_permission_denied`
3. `CKError.quotaExceeded` -> `quota_exceeded`
4. `CKError.networkUnavailable` / `CKError.networkFailure` -> `network_unavailable`
5. `CKError.serviceUnavailable` / `CKError.requestRateLimited` -> `server_error`
6. 其餘錯誤 -> `sync_failed`

## 7. 安全與隱私
1. 使用 CloudKit Private Database 權限模型隔離資料。
2. 本版本不做額外應用層加密（依需求再決策）。

## 8. CloudKit 限制與注意事項
1. **儲存配額**：Private Database 儲存空間取決於使用者的 iCloud 方案。App 應在配額不足時給予使用者提示。
2. **CKAsset 大小限制**：單個圖片資產大小上限依 [Apple 官方文件](https://developer.apple.com/documentation/cloudkit)為準。實作端保守壓縮至 1 MB 以內，避免因限制變動導致上傳失敗。
3. **批次操作上限**：`CKModifyRecordsOperation` 每次最多 400 筆記錄，超過需分批處理。
4. **Settings push**：推送設定應使用 `CKModifyRecordsOperation` 搭配 `.changedKeys` save policy，避免因 `serverRecordChanged` 錯誤導致設定同步失敗。

## 9. Schema 版本遷移
1. 每個 RecordType 預留 `schemaVersion` 欄位（初始值 `1`）。
2. 還原時，若雲端記錄的 `schemaVersion` 高於本地 App 可識別的版本，應略過該記錄並記錄警告日誌（避免 App 崩潰）。
3. 若雲端記錄的 `schemaVersion` 低於本地版本，App 需負責向上遷移欄位（補預設值或轉換格式）。

## 10. 驗收條件（備份/還原）
1. 刪除 App 後重裝，在同 Apple ID 下可還原既有資料。
2. 重新安裝後，還原結果與同步狀態可在紀錄頁查看。
3. 失敗情境可重試，且可讀取錯誤日誌協助排查。
4. 不同 Apple ID 的裝置不會互相看到對方資料。
5. 超過 400 筆單字時，備份與還原仍能正常完成（批次處理）。
6. 還原後 AppSettings 與原裝置一致（顯示圖片、同步頻率等設定值相同）。
7. 還原後通知偏好與原裝置一致（`reminderEnabled` 狀態、`reminderMinutes` 時間相同）。
   - 註：此條僅驗證 App 內偏好值，不等同於 OS 層通知授權已開啟。
8. 含圖片的單字還原後，圖片可正常下載並顯示。

## 11. 已知實作落差（待修復）

以下為目前實作與規格之間的已知落差，需依優先序處理：

| 優先序 | 項目 | 說明 |
|--------|------|------|
| P0 | 補上 `deviceId` + `opSeq` | [cloud-sync.md](./cloud-sync.md) 要求的衝突解決欄位，目前 Dart 與 Swift 層均未實作 |
| P0 | 衝突策略改用 server time | 目前使用 app-level `updatedAt` 做 LWW，應改用 CloudKit `modificationDate` |
| P0 | 實作 tombstone 優先規則 | 刪除與一般更新衝突時，tombstone 應優先，目前未實作 |
| P1 | Settings push 改用 `CKModifyRecordsOperation` | 目前使用 `database.save()`，多裝置同步設定時可能因 `serverRecordChanged` 失敗 |
| P1 | pushChanges 批次處理 | 目前所有記錄放入單一 operation，超過 400 筆會失敗 |
| P1 | 補上 `schemaVersion` 欄位 | Section 9 已定義遷移策略，但 Dart 與 Swift 層均未實作該欄位，需同步補上 |
| P1 | 還原判定改為全域資料存在性檢查 | 目前只看 WordCard 數量，需改為同時檢查 WordCard + AppSettings |
| P1 | 補上 `hasEverSynced` 等 metadata 判定 | 需避免以「AppSettings 是否預設值」作為唯一依據，降低流程誤判 |
| P2 | 錯誤碼分類落地 | Section 6.1 已定義錯誤碼對照表，Dart 層 catch 需對應分類而非統一回傳 `sync_failed` |

## 12. 非目標（本文件）
1. 跨 Apple ID 共享資料不在本版範圍。
2. Android/Web 的備份還原不在本版範圍。
3. 還原前本地快照（rollback）機制不在本版範圍，視需求於後續版本加入。
