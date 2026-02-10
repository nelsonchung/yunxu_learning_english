# CloudKit Dashboard 用 updatedAt 過濾顯示資料

- Date: 2026-02-10
- Container: `iCloud.com.yunxu.yunxulearn`
- Database: `Private Database`

## 1. 目的
在 CloudKit Dashboard 的 `Records` 頁面，避免預設查詢造成錯誤，改用 `updatedAt` 過濾來正確顯示資料（例如 `WordCard`、`AppSettings`）。

## 2. 正確查詢步驟
1. 進入 CloudKit Dashboard，選擇正確環境：
   - 本機開發/`flutter run` 通常看 `Development`
   - TestFlight / App Store 版本看 `Production`
2. 左側進入 `Data -> Records`。
3. 上方確認：
   - Database: `Private Database`
   - Zone: `_defaultZone`
4. `RECORD TYPE` 選擇要看的型別：
   - 單字資料：`WordCard`
   - App 設定：`AppSettings`
5. `FIELDS` 建議先選 `All`。
6. 在 `Add filter or sort to query` 輸入框新增過濾條件：
   - 欄位：`updatedAt`
   - 條件：`>`
   - 值：`2020-01-01 00:00:00 UTC`（或更早）
7. 按 `Query Records`。

## 3. 常見錯誤與處理
### 錯誤 A：`Field 'recordName' is not marked queryable`
原因：
1. 查詢條件混入了 `recordName`，但 schema 沒有把它設為 queryable。

處理：
1. 清空目前 query 條件。
2. 只保留 `updatedAt > ...` 這種條件。
3. 若仍失敗，重新整理頁面後重建查詢。

### 錯誤 B：`One or more parameters were invalid`
原因（常見）：
1. 把 `updatedAt` 放在 `FIELDS`，而不是在 filter 區設定條件。
2. 日期格式或時區格式不正確。

處理：
1. `FIELDS` 改為 `All`。
2. 在 `Add filter or sort to query` 增加 `updatedAt > <UTC時間>`。
3. 優先使用 UTC 時間格式，例如：`2020-01-01 00:00:00 UTC`。

## 4. 看不到資料時的檢查清單
1. 是否選錯環境（`Development` vs `Production`）。
2. 是否 `Act as iCloud Account` 且與 App 內登入 Apple ID 相同。
3. 是否選對 `RECORD TYPE`：
   - `WordCard` 是單字資料（多筆）
   - `AppSettings` 是 App 設定（通常單筆 `app_settings`）
4. `updatedAt` 是否有資料；可先把時間下限設更早。
5. 是否按了 `Query Records`（有時切換條件後未重新查詢）。

## 5. 建議固定查詢模板
### 查單字資料（WordCard）
1. `RECORD TYPE = WordCard`
2. `updatedAt > 2020-01-01 00:00:00 UTC`

### 查設定資料（AppSettings）
1. `RECORD TYPE = AppSettings`
2. `updatedAt > 2020-01-01 00:00:00 UTC`

## 6. 補充
若是要驗證「release build 寫入哪個環境」，請搭配：
- `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloudkit-sync-debugging.md`
