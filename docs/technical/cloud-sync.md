# Cloud Sync Spec v1 (iOS + macOS)

- Date: 2026-02-10
- Scope: YunxuLearn
- Platforms: iOS, macOS
- Backend: CloudKit Private Database

## 1. 目標
1. 同 Apple ID 下，iOS / macOS 資料可雙向同步。
2. 離線後重新連線，資料最終可收斂一致。
3. 同步狀態可觀測、可排查（log + 紀錄頁）。

## 2. 身分與資料隔離
1. 同 Apple ID 視為同一使用者。
2. 不同 Apple ID 的資料彼此隔離，不互相可見。

## 3. 同步資料契約
所有可同步實體至少包含：
1. `id`（穩定主鍵，UUID）
2. `updatedAt`（UTC epoch milliseconds，顯示/除錯用途）
3. `deviceId`（來源裝置識別）
4. `opSeq`（裝置內單調遞增操作序號）
5. `isDeleted`（soft delete / tombstone 標記）

## 4. 衝突策略（已定案）
採用 server time 優先的 `Last-write-wins`（LWW）：
1. 同一筆資料先以 CloudKit server time（`modificationDate`）判定新舊。
2. 若 server time 相同，以 `deviceId + opSeq` 作 tie-breaker。
3. `updatedAt` 不作最終仲裁依據。

## 5. 刪除策略（soft delete + tombstone）
1. 刪除資料時，改寫 `isDeleted = true`，不做實體刪除。
2. 刪除操作需更新 `updatedAt`、`deviceId`、`opSeq`。
3. 若「一般更新」與「tombstone」衝突，`tombstone` 優先。
4. tombstone 保留至少 30 天；僅在保留期達標且最近同步檢查無落後裝置時才可清理。

## 6. 同步觸發
1. App 啟動：先載入本地，再觸發同步。
2. 本地新增/修改/刪除：觸發同步。
3. 定時同步：`5s`, `10s`, `20s`, `30s`, `60s`, `3600s`（設定可調）。
4. 手動同步：由紀錄頁按鈕觸發。
5. 提供 switch button，允許使用者 enable/disable 同步功能。

## 7. 同步流程邊界
1. 一般情境：以 incremental pull/push 為主。
2. 首次安裝或重裝還原：由 `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/backup-restore.md` 定義 full pull 與判定流程。

## 8. 可觀測性與錯誤排查
1. 紀錄頁至少顯示：最後同步時間、同步中狀態、同步可用性、本地資料統計。
2. 同步事件需有可讀日誌：成功/失敗、錯誤碼、重試次數。
3. CloudKit schema/index 問題的排查流程見 `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudkit-sync-debugging.md`。

## 9. 驗收條件
1. iOS 新增/更新資料後，macOS 可看到一致結果。
2. 離線雙端修改後，上線最終以 server time 優先的 LWW 規則收斂一致。
3. `isDeleted` 能跨裝置傳播，不會被舊資料復活。
4. 紀錄頁可顯示最後同步時間與同步狀態。

## 10. 非目標（本文件）
1. 跨 Apple ID 的資料共享（`CKShare` / Shared DB）不在本版範圍。
2. Android/Web 同步不在本版範圍。
