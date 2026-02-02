# 軟體設計文件（Software Design）

## 目的
本文件承接 `docs/requirement/system_architecture.md`，細化到可實作的模組、類別、資料流程與 UI 行為，作為開發依據。

## 設計原則
- 以本地端資料為主，離線可用。
- 業務規則集中於 Domain，UI 不直接操作資料庫。
- 以 Repository 隔離資料來源，便於日後擴充。
- MVP 先完成「今日複習清單 + 新增單字 + 列表排序 + 說明頁」。

## 技術選型（建議）
- 狀態管理：Provider 或 Riverpod（二擇一）
- 本地資料庫：Hive 或 Isar（二擇一）
- 圖片選取：image_picker
- 日期處理：Dart DateTime（必要時可引入 intl）
- 通知（進階）：flutter_local_notifications

## 模組與責任
### Presentation
- pages/
  - today_page.dart：今日複習清單
  - add_word_page.dart：新增單字（多句子 + 圖片）
  - words_list_page.dart：全部單字 + 排序
  - word_detail_page.dart：單字詳情
  - about_page.dart：說明頁
- widgets/
  - sentence_field_list.dart：多句子輸入元件
  - word_card_tile.dart：單字卡片顯示
  - sort_selector.dart：排序選擇器
- state/
  - words_notifier.dart：單字列表狀態與事件
  - review_notifier.dart：今日複習狀態與事件

### Domain
- models/
  - word_card.dart
- services/
  - review_schedule_service.dart：遺忘曲線排程計算
  - sort_service.dart：排序策略

### Data
- repositories/
  - word_repository.dart（介面）
  - local_word_repository.dart（實作）
- sources/
  - word_local_db.dart（Hive/Isar 具體操作）
- storage/
  - image_storage.dart（保存/取得圖片路徑）

## 資料模型
### WordCard
- id: String
- word: String
- sentences: List<String>
- imagePath: String?
- createdAt: DateTime
- reviewSchedule: List<int> = [1,2,3,5,7,12,19,31]
- nextReviewIndex: int
- nextReviewDate: DateTime
- history: List<DateTime>

## 主要服務設計
### ReviewScheduleService
責任：
- 建立初始排程
- 推進下一次複習時間

介面（示意）：
- DateTime initialNextDate(DateTime createdAt)
- WordCard advanceReview(WordCard card, DateTime now)

行為：
- initialNextDate = createdAt + 1天
- advanceReview:
  - history.add(now)
  - nextReviewIndex += 1
  - 若 index < schedule.length => nextReviewDate = createdAt + schedule[index]天
  - 否則維持完成狀態（index == schedule.length）

### SortService
責任：
- 依條件排序 WordCard 列表

排序模式：
- AlphabetAsc（A->Z）
- AlphabetDesc（Z->A）
- CreatedAtDesc（新->舊）
- CreatedAtAsc（舊->新）

## Repository 設計
### WordRepository（介面）
- Future<List<WordCard>> fetchAll()
- Future<void> add(WordCard card)
- Future<void> update(WordCard card)
- Future<void> delete(String id)
- Future<List<WordCard>> fetchDue(DateTime day)

### LocalWordRepository（實作）
- 依賴本地 DB 來源
- 負責資料轉換與快取（若需要）

## UI 行為詳述
### 今日複習頁（today_page.dart）
- 載入時：呼叫 repository.fetchDue(today)
- 顯示今日需複習清單
- 點擊「完成複習」：
  - 使用 ReviewScheduleService.advanceReview
  - repository.update
  - UI 更新

### 新增單字頁（add_word_page.dart）
- 預設一個句子輸入框
- 可新增句子、刪除句子（至少保留 1 個）
- 選擇圖片後存本地路徑
- 儲存：建立 WordCard + repository.add

### 單字列表頁（words_list_page.dart）
- 顯示全部單字
- 提供排序 selector：
  - A->Z / Z->A / 新->舊 / 舊->新
- 切換排序後即時重排

### 單字詳情頁（word_detail_page.dart）
- 顯示 word、sentences、image、createdAt
- 顯示 nextReviewDate 與 history

### 說明頁（about_page.dart）
- App 用途
- 艾賓浩斯遺忘曲線簡介
- 複習週期（1,2,3,5,7,12,19,31）

## 狀態管理與資料流
- 頁面 -> Notifier/ViewModel -> Repository -> Local DB
- Notifier 管理：
  - 當前列表
  - 排序模式
  - 複習完成更新

## 測試建議
- ReviewScheduleService
  - 初始排程
  - 多次複習後日期推進
  - 完成週期後狀態
- SortService
  - 各排序模式正確性
- Repository
  - CRUD 正常運作

## 後續擴充點
- 本地通知提醒
- 單字熟悉度/難度調整
- 雲端同步
