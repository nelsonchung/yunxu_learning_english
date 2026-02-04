# 系統架構規劃

## 範圍與目標
- 依據 `docs/requirement/customer_requirements.md` 建立英文單字學習 App。
- 核心能力：新增單字（多句子 + 圖片 + 中文意義 + 詞性）、依遺忘曲線排程複習、今日複習清單、說明頁、列表排序、設定頁。
- iOS 與 macOS 之間提供 CloudKit 自動同步。

## 架構概覽
本專案為 Flutter App（iOS/macOS 為主），採本地端優先（Local-first），並以 CloudKit 進行跨裝置同步。

分層建議：
- Presentation（UI + 狀態）
- Domain（規則/排程/排序）
- Data（本地儲存 + 同步）

## 模組與責任
### 1) Presentation Layer
- 頁面：
  - 今日複習頁（Home/Today）
  - 新增單字頁（Add）
  - 單字列表頁（All Words + Sort）
  - 單字詳情頁（Detail）
  - 說明頁（About）
  - 設定頁（Settings）
- 狀態管理（擇一）：Provider / Riverpod
- 互動與事件：
  - 新增/刪除句子
  - 上傳圖片
  - 切換排序
  - 完成複習
  - 設定提醒時間/提醒開關/圖片顯示

### 2) Domain Layer
- 排程規則（Ebbinghaus）：[1,2,3,5,8,13,21,39]
- 業務邏輯：
  - 新增單字時產生 nextReviewDate
  - 完成複習後推進 index 與更新下一次複習日期
  - 今日複習判定（nextReviewDate <= 今日）
  - 列表排序（字母 / 建立日期）
  - 同步衝突策略：最後修改者勝出（Last-write-wins）

### 3) Data Layer
- 本地資料庫（擇一）：Hive / Isar
- 圖片儲存：
  - 使用 image_picker 取得圖片
  - 儲存為圖片 bytes（避免路徑失效）
- 設定資料：
  - 提醒時間 / 提醒開關 / 圖片欄位顯示
- 雲端同步：
  - iOS/macOS 使用 CloudKit（同一個 iCloud container）
  - 自動同步 + 增量同步
- 資料存取介面：Repository 模式

## 主要資料模型
### WordCard
- id: String
- word: String
- meaning: String
- partOfSpeech: String
- sentences: List<String>
- imageBytes: List<int>?
- createdAt: DateTime
- reviewSchedule: List<int> = [1,2,3,5,8,13,21,39]
- nextReviewIndex: int
- nextReviewDate: DateTime
- history: List<DateTime>

### AppSettings
- reminderMinutes: int
- reminderEnabled: bool
- showImages: bool

## 關鍵流程
### 新增單字
1. 使用者輸入 word + sentences（至少 1） + image
2. 建立 WordCard（createdAt = now）
3. nextReviewIndex = 0
4. nextReviewDate = createdAt + 1 天
5. 存入本地資料庫

### 今日複習
1. 讀取所有單字
2. 過濾 nextReviewDate <= today
3. 顯示清單
4. 完成複習後更新 WordCard

### 完成複習
1. history.add(now)
2. nextReviewIndex += 1
3. 若 index < schedule 長度：
   - nextReviewDate = createdAt + schedule[index] 天
4. 否則標記為週期完成（可用 nextReviewIndex == schedule.length 表示）

## 排序設計
- 排序模式：
  - A->Z
  - Z->A
  - 新->舊
  - 舊->新
- 排序於列表頁切換時即時套用

## 通知（可擴充）
- 本地通知（每天固定時間提醒）
- 提供提醒時間與提醒開關設定

## CloudKit 同步（iOS/macOS）
- Record Type：WordCard
- 欄位：word、meaning、partOfSpeech、sentences、image(Asset)、createdAt、updatedAt、deleted
- 同步策略：Last-write-wins（以 updatedAt 判斷）
- 刪除策略：軟刪除（deleted=true）後再同步清理
- 同步時機：App 啟動/回前景/設定開啟時觸發自動同步

## 專案結構建議
- lib/
  - data/
    - repositories/
    - sources/
    - sync/
  - domain/
    - models/
    - services/
  - presentation/
    - pages/
    - widgets/
    - state/

## 非功能性需求
- 可離線使用
- 快速啟動
- 可在 iPhone release 模式正常運行
- iOS/macOS 裝置間自動同步
