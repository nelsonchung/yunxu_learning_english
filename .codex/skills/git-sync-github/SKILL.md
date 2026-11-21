---
name: git-sync-github
description: 將此專案當次的變更透過 git add、git commit 與 git push 同步到 GitHub。適用於要求「同步這次修改」、「提交並推送」或明確呼叫 $git-sync-github 的情境。只要求提交或撰寫 commit 訊息時，沿用原本的提交流程。
---

# Git 同步到 GitHub

1. 檢查 `git status --short`、`git diff`、`git diff --cached` 與當前分支。依本次任務與差異內容確認送出的範圍，包含相關的新檔、刪除與重新命名。用明確路徑組成 `git add -- <paths>`。若同一檔案有無關修改，只暫存可明確辨識的片段。若索引已有無關內容，保留使用者的暫存狀態，確認如何處理後才提交。
2. 查明實際推送的 remote 和分支。已設定上游時檢查其目標及任何 push override。沒有上游時，只有 GitHub remote 與目標分支都明確時才提出設定上游的指令。送審前更新目標分支的遠端追蹤資訊，列出本次 push 會一起送出的既有本機提交。若遠端分支領先或分歧，回報狀態並保留現有歷史。
3. 先提供暫存指令、完整 commit 訊息、推送指令、目標分支及任何會一併送出的既有提交，供使用者一次 review。提交依專案 `AGENTS.md` 的 Lore 格式撰寫，使用繁體中文標題說明提交意圖，內文包含「根因 (Root cause)」與「解法 (Solution)」，需要時加上 Git trailers。使用者確認執行整份方案後，依序完成暫存、提交及推送。若索引、提交範圍或推送目的地已與確認內容不同，先更新方案。
4. 暫存後用 `git diff --cached` 核對即將提交的內容。提交成功後才以明確的 remote 與 refspec 推送，例如 `git push origin HEAD:refs/heads/main`，以確認過的分支為準。需要建立上游時，確認後使用 `git push -u <remote> <local-branch>:refs/heads/<remote-branch>`。已無待提交變更但有本次尚未推送的提交時，可直接完成已確認的推送。遠端已包含所有目標提交時，回報已同步。
5. 用 push 結果或 `git ls-remote` 確認目標分支包含本次提交，回報 commit SHA、remote 與分支。若提交成功但推送失敗，保留本機提交，回報原因。遇到權限、分支保護或 non-fast-forward 拒絕時，維持遠端歷史與本機提交，讓使用者決定後續處理。
