# 字庫搜尋效能技術決策

- Date: 2026-04-09
- Status: Proposed
- Scope: `WordBankPage`、`BuiltinWordBankRepository`、字庫搜尋資料來源與查詢策略

## 1. 目的

本文不是泛用 Flutter 搜尋提案，而是針對本 repo 目前字庫搜尋卡頓問題的技術決策摘要。

目標是回答三件事：

1. 目前真正的瓶頸在哪裡
2. 哪些方案適合這個專案，哪些不適合
3. 應該依什麼順序落地

## 2. 目前 repo 現況

依 2026-04-09 workspace 實際內容整理：

- 內建字庫已拆成 `word_bank_main-a.json` 到 `word_bank_main-z.json`
- 字庫總筆數約 `199,869`
- 26 個 shard 資產總大小約 `96.7 MB`
- `BuiltinWordBankRepository.fetchAll()` 仍會把 26 份 shard 全部讀入、`jsonDecode()`、轉成 `BuiltinWordEntry` 後合併快取
- `WordBankPage` 在每次 `TextField.onChanged` 時直接 `setState()`
- `WordBankSearchService.search()` 會在 UI isolate 線性掃描整份 entries，且對每筆資料重做 `normalize`
- `TodayPage` 目前也還會走 `fetchAll()`
- 以目前搜尋規則做本地粗測，單次查詢約落在 `0.37s - 0.47s`

目前已確認的程式碼位置：

- `lib/presentation/pages/word_bank_page.dart`
- `lib/domain/services/word_bank_search_service.dart`
- `lib/data/repositories/builtin_word_bank_repository.dart`
- `lib/presentation/pages/today_page.dart`

## 3. 問題判斷

這個 repo 現在的卡頓，不是單一原因，而是三個問題疊加：

### 3.1 輸入事件過於頻繁

目前每輸入一個字母就立即觸發搜尋。

結果：

- 使用者持續打字時，舊查詢還沒做完，新查詢又開始
- 體感會變成每個字之間都停一下

### 3.2 搜尋仍是全量線性掃描

雖然字庫已拆成 A-Z shard，但執行期仍會先合併成單一 `_entries` 再查。

因此目前的 shard 只降低單檔 asset 管理壓力，沒有解決查詢成本：

- 查詢仍是 `O(n)`
- 字庫愈大，單次搜尋愈慢
- 中文 meaning search 與英文 contains 都無法自然利用目前 shard 結構

### 3.3 每次搜尋重做字串正規化

目前搜尋邏輯在每次查詢時，都會對每筆 entry 重新計算：

- `normalizedWord`
- `normalizedMeaning`
- `relaxedMeaning`

當字庫接近 20 萬筆時，這種重複計算本身就是明顯成本。

## 4. 這次決策的關鍵結論

### 4.1 已經不是「要不要先優化」的問題

目前資料量已經接近 20 萬筆、資產約 96.7 MB，這不是未來風險，而是現況問題。

因此這次不建議只做表面止血後就結案。

### 4.2 A-Z 分 shard 不是最終解

本 repo 已經先做了 shard，但 UI 與 repository 仍然依賴 `fetchAll()`。

這代表：

- shard 不能根本解決輸入卡頓
- shard 也不能支援目前需要的中文 meaning search 與英文 contains

### 4.3 長期主方案應明確選擇 SQLite，不建議把 Isar 與 SQLite 並列為同級首選

原因：

- 本 repo 目前搜尋語意包含 `exact`、`prefix`、`contains`、中文 meaning 搜尋
- `SQLite FTS5` 對 substring / full-text 查詢更貼近現況需求
- 內建字庫是 build-time 產物，適合做預建的唯讀查詢資料庫
- 後續 `filter count`、today 推薦候選、分頁、排序也更容易收斂到同一個查詢層

## 5. 方案評估

### 5.1 方案 A：SQLite 唯讀查詢庫

評估：最適合本 repo 的正式方案

優點：

- 可用索引與 FTS5 取代 Flutter 端全表掃描
- 可把查詢、filter count、today 推薦候選整合到同一層
- 不需要把整份字庫常駐成大量 Dart object
- 與目前「JSON 作為內容來源、runtime 離線查詢」的工作流相容

缺點：

- 需要新增 build-time 轉檔流程
- 需要處理 DB asset 複製、版本化與驗證

結論：

- 建議作為正式主方案

### 5.2 方案 B：Isar

評估：不建議作為本專案主方案

原因：

- Isar 很適合物件儲存與部分 index 查詢
- 但本 repo 目前痛點不是單純 Flutter-friendly local DB，而是大規模查詢語意
- 官方 full-text recipe 比較偏 token / prefix 思路，對目前的 contains 與 meaning search 沒有 SQLite FTS5 那麼直接

結論：

- 可作為替代路線討論
- 不建議與 SQLite 並列為同級首選

### 5.3 方案 C：Trie

評估：不適合作為主方案

優點：

- 英文 prefix search 很快

缺點：

- 記憶體常駐成本高
- 對中文 meaning search 幫助有限
- 對 `filter`、`today 推薦候選` 幾乎沒有直接幫助
- 最後往往還是要再補第二套查詢結構

結論：

- 不建議採用

### 5.4 方案 D：繼續強化 JSON shard

評估：只能當過渡止血

原因：

- 本 repo 已經是 A-Z shard，證明 shard 本身不足以解決互動卡頓
- 若仍要支援 contains / meaning 搜尋，最後還是會往「自建查詢引擎」演化

結論：

- 可當短期過渡
- 不建議視為長期架構

### 5.5 方案 E：Isolate / `compute()`

評估：值得做，但只能當短期止血或 DB 前的過渡

優點：

- 可避免大量運算直接堵塞 UI isolate

缺點：

- 若每次輸入都把大批資料丟到 isolate，資料搬運仍然昂貴
- 它改善的是執行位置，不是查詢複雜度

結論：

- 可作為短期配套
- 不能取代查詢架構重構

## 6. 建議決策

本 repo 建議採以下決策：

1. 短期先止血，但不把止血視為結案
2. 中期把搜尋頁改成 query-based repository，切斷 UI 對 `fetchAll()` 的依賴
3. 長期以 build-time JSON -> SQLite 唯讀查詢庫作為正式架構

補充決策：

1. 保留 `assets/word_bank/*.json` 作為內容編修來源
2. 不建議新增 Trie 作為第二套索引
3. 不建議只靠 A-Z shard 持續堆補丁
4. `filter count`、today 推薦候選、搜尋結果應最終收斂到同一個查詢來源

## 7. 執行順序

本專案建議依以下順序執行：

也可以把它理解成：

- Phase 1：把「每打一字就卡」先止住
- Phase 2：把「頁面架構和資料流」整理對，讓載入、切 filter、分頁、記憶體體感明顯變好
- Phase 3：把「查詢本身」從線性掃描換成索引查詢，才是根本性的速度提升

### Phase 1：立即止血

目的：先把「每打一字就卡」降到可接受範圍，避免等待正式架構完成前頁面持續難用。

建議項目：

1. 搜尋輸入加入 `250-300ms debounce`
2. `1` 字 query 只做 `word prefix search`
3. `word contains` 至少在 query 長度達 `2` 後才啟動
4. `meaning search` 至少在 query 長度達 `2` 或 `3` 後才啟動
5. 預先快取每筆 entry 的：
   - `normalizedWord`
   - `normalizedMeaning`
   - `relaxedMeaning`
6. 搜尋結果列表改用 `ListView.builder`
7. 視情況把高成本搜尋搬到常駐 isolate，而不是每次重新大量搬運資料

驗收方向：

- 連續輸入時不再出現明顯逐字停頓
- 空 query 與短 query 時間明顯下降
- 搜尋行為仍與目前結果大致相容

### Phase 2：中期重構

目的：先把頁面結構改成 query-based，讓之後換底層資料來源時不必重寫整個 UI。

建議項目：

1. `WordBankPage` 不再直接持有整份 `_entries`
2. `BuiltinWordBankRepository` 新增 query-oriented API
3. UI 改成持有：
   - `query`
   - `selectedFilter`
   - `currentResultPage`
   - `count summary`
4. 搜尋頁先不再依賴 `fetchAll()`
5. today 推薦頁同步規劃移除 `fetchAll()` 依賴

驗收方向：

- 搜尋頁可只取得「目前需要的結果」
- UI 與資料來源解耦
- 正式切 DB 時，主要改動集中在 repository 層
- 目前階段允許底層仍以 JSON shard 為資料來源，但搜尋頁不應再直接依賴 `fetchAll()`

### Phase 3：正式方案

目的：把內建字庫查詢正式遷移到可擴張的離線查詢架構。

建議項目：

1. 保留 JSON 作為內容維護來源
2. build 時將 JSON 轉成唯讀 SQLite 資產
3. runtime 首次啟動或版本升級時複製 DB 到 app support directory
4. 搜尋、filter count、today 推薦候選都改查 DB
5. 視搜尋語意導入：
   - `word_lower` 索引
   - audience / school / exam 對應欄位索引
   - `FTS5` 處理 contains 與 meaning search
6. 最後移除大型字庫路徑對 `fetchAll()` 的依賴

驗收方向：

- 搜尋頁不再需要全量載入 JSON
- 字庫成長到 20 萬以上時仍可維持可接受延遲
- today 推薦不再在 Flutter 端對整份字庫做粗暴掃描

## 8. 為什麼是這個順序

這個順序的理由是：

1. Phase 1 能最快改善目前最痛的互動卡頓
2. Phase 2 能先把架構介面整理好，避免之後 DB 上線時 UI 再大改一次
3. Phase 3 才是從根本解掉大字庫查詢問題的正式方案

若直接跳到 Phase 3，開發時間會較長，使用者在此期間仍會持續承受卡頓。

若只做 Phase 1，不做後續重構，問題會在字庫繼續成長後再次回來。

## 9. 已修正的觀念

本次評估後，以下幾點應視為已確認：

1. 目前 repo 已有全 app 共用的 `BuiltinWordBankRepository` 單例 cache，不是每個頁面各自 new repository
2. 目前搜尋頁的 `filter count` 已在載入後預先建立，不是每次 build 都重新掃描
3. 目前真正更優先的瓶頸是：
   - `fetchAll()`
   - 每字即搜
   - 線性掃描
   - 每次搜尋重做 normalize

## 10. 待確認事項

進入實作前，建議再確認：

1. 英文搜尋是否一定要保留任意 substring contains
2. 中文 meaning 搜尋是否要與 word prefix 同等即時
3. `meaning search` 的最低啟動字數要訂為 `2` 還是 `3`
4. 搜尋頁是否要加入分頁或 infinite scroll
5. DB 導入後要採 `drift`、`sqflite`，或更底層的 `sqlite3` 封裝

## 11. 參考文件

- `docs/technical/word-bank-230k-refactor-plan.md`
- Isar full-text search: <https://isar.dev/recipes/full_text_search.html>
- SQLite FTS5: <https://www.sqlite.org/fts5.html>
- Drift native database / background isolate: <https://drift.simonbinder.eu/platforms/vm/>
