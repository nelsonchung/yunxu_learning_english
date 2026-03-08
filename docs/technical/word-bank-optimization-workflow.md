# 單字庫例句優化技術流程 (Word Bank Optimization Workflow)

本文詳細記錄了對 `assets/word_bank/pdf_word_bank.json` 進行大規模例句更新時所採用的技術方案與操作流程。

## 1. 背景與目標

原本的單字庫中存在大量「模板化」的例句（例如："The professor discussed the concept of '...' in great detail."），這些句子缺乏生活化語境且重複性高。
目標是將約 1,000 多個單字的例句替換為：
- **自然語境**：符合日常生活、工作或學術場景。
- **準確翻譯**：使用繁體中文，且翻譯中不包含該單字的英文原文。
- **結構完整**：確保 JSON 格式在更新後依然整齊、合法。

## 2. 核心技術策略：混合式批量處理 (Hybrid Batch Processing)

由於目標 JSON 文件體量巨大（超過 5 萬行），傳統的字串替換工具（如 `replace`）極易因為空格、縮進或轉義字元（Escape characters）的微小差異而失敗。因此，採用了 **AI 生成內容 + Python 結構化寫入** 的混合方案。

### 第一步：精準定位 (Fetch Pending Words)

利用 Python 腳本讀取 JSON，找出指定起始單字後的 50 個單字名稱。

```python
import json

# 定義起始單字
target_word = "previous_processed_word"

with open("assets/word_bank/pdf_word_bank.json", "r") as f:
    data = json.load(f)

# 找到起始索引
start_index = next(i for i, item in enumerate(data) if item["word"] == target_word) + 1

# 提取後續 50 個單字
words = [item["word"] for item in data[start_index : start_index + 50]]
print(json.dumps(words, ensure_ascii=False))
```

### 第二步：高品質內容生成 (AI Brainstorming)

將提取出的單字列表交由 AI 模型進行處理：
1.  **構思例句**：針對單字的多重語義構思兩個具代表性的句子。
2.  **翻譯審核**：確保翻譯符合台灣繁體中文用語習慣。
3.  **格式化準備**：將生成內容整理為一個臨時的 `updates` 陣列（JSON 格式）。

### 第三步：自動化批量寫入 (Atomic Update Script)

這步最為關鍵，透過 Python 直接操作 JSON 物件而非操作純文字，避免了格式損毀的風險。

在實際寫回前，還要補兩個必要步驟：

1. **Sanitize 來源文字**
   - 若詞典或例句來源帶有 `<a ...>`、`<span ...>`、`<b>...</b>` 等 HTML / wiki 標記，必須先轉成純文字。
   - 不能把帶標記內容直接當成 definition 或 sentence 寫回 JSON。
2. **Validate 主庫**
   - 寫回前後都要檢查 JSON 是否合法、是否排序、是否有重複 `word`、是否出現 HTML 標記、是否每筆都有固定 schema。

```python
import json

# 由 AI 產生的更新列表
updates = [
  {"word": "example", "meaning": "例子", "partOfSpeech": "noun", "sentences": ["Sentence 1", "Sentence 2"]},
  # ... 更多單字
]

# 1. 讀取原始文件
with open("assets/word_bank/pdf_word_bank.json", "r", encoding="utf-8") as f:
    data = json.load(f)

# 2. 在記憶體中進行比對與更新
for update in updates:
    for item in data:
        if item["word"] == update["word"]:
            item["meaning"] = update["meaning"]
            item["partOfSpeech"] = update["partOfSpeech"]
            item["sentences"] = update["sentences"]
            break

# 3. 以標準化格式寫回文件
with open("assets/word_bank/pdf_word_bank.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
```

## 3. 採用的技術參數

- **批次大小 (Batch Size)**：50 個單字/次。
  - *考量點*：平衡 AI 的脈絡長度（Context Window）與寫入效率。
- **字元處理 (Encoding)**：統一使用 `utf-8`。
- **JSON 序列化**：
  - `ensure_ascii=False`：確保中文字元不會被轉換成 `\uXXXX` 格式，保持文件可讀性。
  - `indent=2`：保持文件縮進與專案現有風格一致。
- **資料驗證**：
  - 寫回前後執行 `python3 tools/validate_word_bank_main.py`
  - 若要把歷史資料也一起收斂到新標準，再使用 `python3 tools/validate_word_bank_main.py --fail-on-warnings`

## 4. 方案優點

1.  **原子性 (Atomicity)**：Python `json` 模組確保了更新是基於結構的。如果腳本運行失敗，文件不會被寫入，避免產生損毀的 JSON。
2.  **精準度 (Precision)**：不依賴正則表達式，直接針對 key-value 進行更新，解決了同一個單字在不同地方出現可能導致誤換的問題。
3.  **可擴展性 (Scalability)**：這套流程可以輕易擴展到數千甚至數萬個節點的批量更新。

## 5. 總結

透過 Python 腳本輔助，我們在短時間內完成了對 `pdf_word_bank.json` 最後 1,000 多個單字的高品質翻新，確保了單字庫數據的一致性與教學品質。
