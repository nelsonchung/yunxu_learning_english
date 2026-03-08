# PDF 字庫整理流程

來源 PDF：
`docs/materials/20000必考單字 搞定英檢、新制多益、托福拿高分 -- 人類文化編輯部 -- 2021 -- 人類文化事業股份有限公司 -- 9786267033159 -- d9705951728e932b84d3e485e04f5b8c -- Anna’s Archive.pdf`

## 1. 產生字庫 JSON

```bash
python3 tools/extract_pdf_word_bank.py \
  --pdf "docs/materials/20000必考單字 搞定英檢、新制多益、托福拿高分 -- 人類文化編輯部 -- 2021 -- 人類文化事業股份有限公司 -- 9786267033159 -- d9705951728e932b84d3e485e04f5b8c -- Anna’s Archive.pdf" \
  --output assets/word_bank/pdf_word_bank.json \
  --start-page 20 \
  --end-page 300 \
  --dpi 260 \
  --workers 6 \
  --psm-list 6,4,11 \
  --language chi_tra+chi_sim+eng \
  --include-all-mentions \
  --include-token-mentions \
  --token-min-count 1 \
  --token-unknown-min-count 5
```

## 2. 輸出欄位

- `word`: 英文單字
- `meaning`: 中文意思
- `partOfSpeech`: 詞性（對應 `PartOfSpeech` enum）
- `sentences`: 兩個自造英文例句
- `sourcePage`: 原始 PDF 頁碼

## 3. 現況（2026-03-02）

- 目前版本輸出：`10808` 筆唯一單字（OCR + 去重後）
- 其中約 `3601` 筆為 OCR 全文 token 補抓（`meaning` 為 `（PDF提及，待補中文）`）
- 輸出檔：`assets/word_bank/pdf_word_bank.json`
