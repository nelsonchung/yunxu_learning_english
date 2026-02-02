# 系統架構規劃

## 範圍與目標
- 依據 `docs/requirement/customer_requirements.md` 建立英文單字學習 App。
- 核心能力：新增單字（多句子 + 圖片）、依遺忘曲線排程複習、今日複習清單、說明頁、列表排序。

## 架構概覽
本專案為 Flutter App（iOS/Android），以本地端為主，不依賴後端服務。

分層建議：
- Presentation（UI + 狀態）
- Domain（規則/排程/排序）
- Data（本地儲存 + 檔案）

## 模組與責任
### 1) Presentation Layer
- 頁面：
  - 今日複習頁（Home/Today）
  - 新增單字頁（Add）
  - 單字列表頁（All Words + Sort）
  - 單字詳情頁（Detail）
  - 說明頁（About）
- 狀態管理（擇一）：Provider / Riverpod
- 互動與事件：
  - 新增/刪除句子
  - 上傳圖片
  - 切換排序
  - 完成複習

### 2) Domain Layer
- 排程規則（Ebbinghaus）：[1,2,3,5,7,12,19,31]
- 業務邏輯：
  - 新增單字時產生 nextReviewDate
  - 完成複習後推進 index 與更新下一次複習日期
  - 今日複習判定（nextReviewDate <= 今日）
  - 列表排序（字母 / 建立日期）

### 3) Data Layer
- 本地資料庫（擇一）：Hive / Isar
- 圖片儲存：
  - 使用 image_picker 取得圖片
  - 儲存至 App sandbox 並記錄路徑
- 資料存取介面：Repository 模式

## 主要資料模型
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
- MVP 先以「首頁顯示今日需複習清單」為主
- 進階可加入本地通知（flutter_local_notifications）

## 專案結構建議
- lib/
  - data/
    - repositories/
    - sources/
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
