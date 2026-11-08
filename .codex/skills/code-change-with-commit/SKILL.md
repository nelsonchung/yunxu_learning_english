---
name: code-change-with-commit
description: 當使用者要求修改程式碼、實作功能、修正 bug，並希望同時提供 git add 與 git commit 指令時使用。特別適用於需要整理本次變更檔案、避免混入無關變更、並以繁體中文撰寫 commit 訊息的情境。若使用者要求 commit 內容包含 Root cause 與 Solution，也應套用此 skill。
---

# Code Change With Commit

此 skill 用於以下情境：
- 使用者要求修改程式碼
- 使用者希望同時取得 `git add` 與 `git commit` 指令
- 使用者希望 commit message 使用繁體中文
- 使用者希望 commit body 包含 `Root cause` 與 `Solution`

## Workflow

1. 先完成程式碼修改、格式化、必要驗證。
2. 檢查目前 git worktree 狀態，例如 `git status --short`。
3. 只整理與本次需求直接相關的檔案，不要把無關變更放進 `git add`。
4. 如果 worktree 很髒，優先提供明確列檔案的 `git add`，不要用過度寬鬆的寫法。
5. `git commit` 訊息預設使用繁體中文。
6. 若使用者有要求，commit body 必須包含以下段落：
   - `Root cause:`
   - `Solution:`
7. `Root cause` 要說明目前問題或缺口。
8. `Solution` 要說明這次修改怎麼解決問題。
9. 若適合，可提供 2 到 3 個 commit message 版本供使用者 review。
10. 除非使用者明確要求，不要直接執行 `git add` 或 `git commit`，只提供指令內容。

## Output Rules

當使用者要求 git 指令時，輸出應包含：

- 一段 `git add` 指令
- 一段 `git commit` 指令
- 如有需要，可附上 2 到 3 個 commit 訊息版本

## Commit Format

預設 commit 格式如下：

`git commit -m "<繁體中文標題>" -m "Root cause:
<問題原因>

Solution:
<解法描述>"`

## Commit Writing Guidelines

- 標題要短，能直接描述這次改動
- `Root cause` 寫「為什麼需要改」
- `Solution` 寫「這次怎麼改」
- 避免空泛描述，例如「修正問題」或「更新程式」
- 若本次只 stage 部分檔案，要在回覆中明確說明這是為了避免混入其他未相關變更

## Example Response Pattern

```bash
git add \
  path/to/file_a \
  path/to/file_b \
  path/to/file_c

git commit -m "新增單字自訂標籤與列表篩選功能" \
  -m "Root cause:
目前使用者新增單字缺少可自訂分類欄位，導致課次與考試範圍無法整理。

Solution:
新增 customTags 欄位，串接新增、編輯、列表篩選、匯入匯出與同步流程，讓標籤可持久化並可用於複習範圍管理。"
```

## Notes

- 若專案中已有 commit 規範，優先遵守該規範
- 若使用者指定語言，優先遵守使用者要求
- 若有無關變更，應主動避開，不要納入建議的 `git add`
