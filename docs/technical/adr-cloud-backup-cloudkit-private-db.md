# ADR: 雲端備份採用 CloudKit Private Database（iOS + macOS）

- Status: Accepted
- Date: 2026-02-07
- Owners: YunxuLearn team

## 背景
- 需求：iOS 與 macOS 都能使用雲端備份，且 App 重新安裝後可從雲端還原資料。
- 目前專案已使用 Apple 生態（iOS/macOS），已有 CloudKit 同步經驗。

## 決策
本專案的雲端備份與還原，採用 `CloudKit Private Database` 作為主要資料儲存後端。

## 為什麼選這個方案
1. 與 iOS/macOS 原生整合度高，帳號與權限模型清楚。
2. 同 Apple ID 的跨裝置同步與重裝還原符合需求。
3. 不需先建置自有後端，可降低初期開發與維運成本。

## 範圍（In Scope）
1. 使用者主要學習資料（例如單字卡、複習狀態、必要設定）上雲。
2. App 重裝後，首次啟動可從雲端拉回資料。
3. iOS 與 macOS 同步資料格式一致，支援雙向更新。

## 非範圍（Out of Scope）
1. 不同 Apple ID 間的資料共享。
2. Android/Web 裝置同步。
3. 團隊協作式共享資料（多人共編）。

## 資料與同步原則（初版）
1. 每筆資料需有穩定主鍵（UUID）與 `updatedAt`。
2. 刪除採 soft delete + tombstone（例如 `isDeleted`）避免資料復活。
3. 衝突規則採 server time 優先：
   - 先以 CloudKit server time（`modificationDate`）判定新舊。
   - 若 server time 相同，以 `deviceId + opSeq`（單調遞增）作 tie-breaker。
   - `updatedAt` 保留作顯示與除錯，不作最終仲裁依據。
4. 首次還原流程：
   - 本地資料為空：先做 full pull，拉回後以雲端結果覆蓋本地。
   - 本地資料非空：做 merge，並套用上述衝突規則；tombstone 優先於一般更新。
   - 合併完成後再更新 UI。
5. tombstone 保留至少 30 天；僅在保留期達標且最近同步檢查無落後裝置時才可清理。

## 還原流程（使用者視角）
1. 安裝/重裝後第一次啟動，顯示「正在從雲端還原」。
2. 完成後顯示還原結果（筆數、最後同步時間）。
3. 失敗時可重試，並保留錯誤訊息供支援排查。

## 風險與對策
1. 風險：CloudKit schema 變動造成 release 行為不一致。  
對策：每次上線前檢查 Development/Production schema 與 index。
2. 風險：衝突處理不明確導致資料覆寫。  
對策：明訂 server time / tie-breaker 規則，加入跨裝置時鐘偏移與同時寫入測試案例。
3. 風險：使用者誤以為跨 Apple ID 可共用資料。  
對策：在說明文字中明確標註「同 Apple ID 才會還原同一份私有資料」。

## 驗收條件（MVP）
1. iPhone 新增/修改資料後，macOS 可看到一致結果。
2. 刪除 App 後重裝，在同 Apple ID 下可還原既有資料。
3. 離線修改後重新連線，資料最終能收斂一致。
4. `isDeleted` / tombstone 能跨裝置傳播，不會被舊資料復活。
5. 至少有可讀的同步日誌（成功/失敗/最後同步時間）。

## 替代方案（為何暫不採用）
1. 自建後端（Firebase/Supabase/custom API）  
優點：跨平台彈性高。  
缺點：開發與維運成本較高，超出當前需求。
2. 匯出/匯入檔案式備份  
優點：可手動控制。  
缺點：使用體驗差，重裝還原不自動。

## 後續工作項目
1. 撰寫資料契約文件（欄位、索引、版本遷移策略）。
2. 實作首次還原 UX（進度、結果、重試）。
3. 補齊測試矩陣（重裝、離線、衝突、雙平台一致性、tombstone 清理）。
