# 版本控制盤點（2026-11-08）

`.gitignore` 已經使用者確認並提交為 `43b28c15`。以下批次是待 review 草案，尚未執行 `git add` 或 `git commit`。
所有指令由專案根目錄執行，且應分批執行與提交，不使用 `git add .`。

## 批次一：單字延伸功能（16 檔）

頁面修改依賴新增服務及 widget，必須一起納管；關係資料、測試與三份說明文件屬於同一功能。

```bash
git add -- \
  lib/main.dart \
  lib/domain/models/word_extension.dart \
  lib/domain/services/common_word_relations.dart \
  lib/domain/services/word_extension_service.dart \
  lib/domain/services/word_relation_data.dart \
  lib/presentation/pages/word_detail_page.dart \
  lib/presentation/widgets/word_extension_section.dart \
  test/word_detail_page_test.dart \
  test/word_extension_candidate_quality_test.dart \
  test/word_extension_coverage_test.dart \
  test/word_extension_dictionary_test.dart \
  test/word_extension_generalization_test.dart \
  test/word_extension_service_test.dart \
  docs/technical/word-extension-common-relations-2026-11-07.md \
  docs/technical/word-extension-generality-audit-2026-11-07.md \
  docs/technical/word-extension-recommendations.md
```

建議 commit 內容：

```text
讓使用者依目前詞義探索用法並將相關字加入複習

根因 (Root cause):
單字詳情缺少依義項與詞性尋找相關字、易混淆字及延伸用法的入口。

解法 (Solution):
接入延伸推薦服務、字庫索引及人工關係資料；展開時載入結果，
支援失敗重試、避免重複新增，並保留既有單字的複習狀態。
一併納入推薦品質、通用性與頁面互動測試及驗證文件。

Constraint: 推薦依賴現有字庫內容品質，缺乏可靠證據時允許空結果
Confidence: medium
Scope-risk: moderate
Tested: 102 個單字延伸與詳情頁測試通過
Not-tested: 實機操作、全字庫逐項人工語義審核
```

## 批次二：iOS Release 實機選擇（2 檔）

```bash
git add -- build_app.sh test/build_app_ios_release_test.py
```

建議 commit 內容：

```text
避免 iOS Release 安裝選錯裝置或在無實機時繼續建置

根因 (Root cause):
Release 執行未指定實機 ID，且清理流程未先確認是否有可用實機。

解法 (Solution):
先解析 Flutter 裝置清單，只接受受支援的 iOS 實機；
多台時驗證使用者選擇，將選定 ID 保留至建置後執行，
並在清理前完成裝置檢查。

Confidence: high
Scope-risk: narrow
Tested: 8 個模擬 Flutter CLI 測試、bash -n build_app.sh
Not-tested: 真實 iPhone 的簽署、建置及安裝
```

## 批次三：專案協作與盤點文件（4 檔）

`.codex/` 目前只有兩份專案技能，並非執行狀態。AGENTS.md 是協作指引。
此批只保存現有規範，並未認定所有舊技能內的參考資料仍然有效。

```bash
git add -- \
  AGENTS.md \
  .codex/skills/code-change-with-commit/SKILL.md \
  .codex/skills/word-bank-h-curator/SKILL.md \
  docs/technical/version-control-review-2026-11-08.md
```

建議 commit 內容：

```text
讓專案協作規範與版本控制決策可隨程式碼保存

根因 (Root cause):
專案指引與兩份本地技能尚未納管，未提交檔案也缺少明確分組依據。

解法 (Solution):
保存現有 AGENTS.md、專案技能及此次版本控制盤點，
記錄可提交批次、驗證結果及需要後續處理的檔案。

Confidence: high
Scope-risk: narrow
Tested: 檔案用途及路徑盤點、git diff --check
Not-tested: 兩份技能完整工作流程
```

## 批次四：字庫稽核與候選佇列工具（2 檔）

兩支工具不會直接覆寫字庫；稽核工具產生 logs 報表，候選工具整理審查輸入。
仍需實際資料執行驗證，不能將語法通過視為結果品質保證。

```bash
git add -- tools/audit_word_bank_p_quality.py tools/queue_sentence_refine_candidates.py
```

建議 commit 內容：

```text
保留可重用的字庫品質稽核與例句候選整理工具

根因 (Root cause):
既有品質稽核與候選整理腳本尚未納管，難以追溯後續字庫維護依據。

解法 (Solution):
保存 p 字庫品質稽核與例句候選佇列工具，供後續審查流程使用。

Confidence: medium
Scope-risk: narrow
Tested: Python AST 語法檢查、既有 review_entry 介面相容性檢查
Not-tested: 使用完整字庫執行與輸出內容人工審核
```

## 其餘檔案的處理結論

| 檔案或目錄 | 處理與理由 |
|---|---|
| `macos/Runner.xcodeproj/project.pbxproj` | 暫緩。三處 SDKROOT 從 macosx 改成 iphoneos，且新增 iPhone 簽署設定；應先查明變更原因並驗證 macOS 建置。沒有擅自還原。 |
| `tools/expand_word_bank_main.py`（刪除） | 舊單檔字庫擴充器，目前搜尋僅見 README 引用；可作 legacy 退役候選，但需連同 README 說明一起處理，未還原也未暫存刪除。 |
| `tools/README.md` | 應保存，但先修正已刪腳本的可用性描述及補齊新增工具定位。 |
| `mempalace.yaml` | 可選保存。程式碼地圖設定，未發現秘密或本機絕對路徑；與 App 執行無直接關係，暫留供獨立決定。 |
| `frontend/yunxu-learning-english-project-overview.html` | 暫緩。介紹頁含 App Store placeholder ID 與缺失圖片路徑，應修復後獨立提交。 |
| `docs/technical/word-bank-review-2026-09-30/` | 4 檔約 19.8 MB 的歷史稽核資料；3 檔含本機絕對路徑，建議先改用相對路徑，再獨立保存歷史報告。 |
| `docs/word-picture-generation/` | 1,658 檔約 16.1 MB，含 620 檔本機路徑及 state、queue、session、run-log；4 張草稿圖合計約 12.5 MB。先分離可重用提示詞／內容來源與執行產物，避免整目錄直接提交。 |

其餘九支字庫修補／循環工具先保留於工作樹，不納入上述批次：

- `tools/apply_manual_sentence_fixes_m.py`：一次性覆寫；找不到指定詞仍先寫檔後回傳錯誤，內容未驗證。
- `tools/repair_prompt_polluted_word_bank_entries.py`：預設改寫多 shard，呼叫 Codex 使用繞過 sandbox／approval 旗標，模板句品質待驗證。
- `tools/repair_word_bank_p_autoloop.py`：與 batch 成對，預設套用修改，需驗證停止條件及品質檢查。
- `tools/repair_word_bank_p_batch.py`：依賴 audit JSON 與 Codex CLI，使用繞過 sandbox 旗標；草稿與 dry-run 尚未做功能驗證。
- `tools/repair_word_bank_t_templates.py`：依賴未納管的 logs review JSON 及外部字典／翻譯來源，僅 `--apply` 寫字庫。
- `tools/repair_word_bank_template_sources.py`：依賴 `/tmp` 下的 GCIDE／WordNet（可用環境變數覆寫），來源安裝未文件化，仍生成模板句。
- `tools/run_ai_refine_until_done.sh`：反覆套用 Gemini 修補，模型錯誤無限重試，缺總輪數／時間上限。
- `tools/update_placeholder_meanings.py`：依賴 Dictionary API／Google Translate，通用詞性模板不能證明例句語義正確。
- `tools/wait_gemini_and_refine_n.sh`：一次性 n 字庫任務，等待 Gemini 額度後啟動上述無上限寫入流程。

這些檔案需要逐項確認寫入副作用、硬編碼的執行環境、字庫語義品質及已缺失的輸入／工具依賴。
尚未執行任何字庫修補或自動循環工具，也未修改字庫 shard。

## 驗證與限制

- 本輪重新執行六份單字延伸／詳情頁測試：102 個通過。
- 本輪重新執行 iOS Release 選單 Python 測試：8 個通過。
- `bash -n build_app.sh` 與 `git diff --check` 通過。
- 前一輪完整 `flutter test`：294 個通過；本輪未修改 App 原始碼。
- 前一輪 `flutter analyze`：18 個 info，位於未修改的主題及共用 widget 檔案，退出碼 1，不能宣稱完全通過。
- 文件掃描未發現典型 credential assignment、private key 或 OpenAI token 格式；這不是秘密資訊不存在的完整證明。
- `.gitignore` 僅提交排除規則；忽略檔仍保留本機，並未刪除、上傳或推送。
