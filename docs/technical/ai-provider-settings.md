# OpenAI／Claude 設定

在「AI 學習圖卡設定」選擇「例句與內容查證供應商」，輸入該供應商的 API Key 並儲存。選擇會保存在此裝置，重啟後仍有效。OpenAI 與 Claude 金鑰分開存於裝置安全儲存；切換不會覆寫或刪除另一家的金鑰，既有 OpenAI Key 可直接沿用。金鑰不隨 iCloud 同步。

| 功能 | OpenAI | Claude |
| --- | --- | --- |
| 依程度生成三組雙語例句 | 支援 | 支援，使用 `claude-sonnet-4-6` |
| 上網查證圖卡內容 | 支援 | 支援，使用 Claude web search |
| 圖片生成 | 支援 | 圖片步驟仍使用 OpenAI |

選擇 Claude 且需要圖卡時，先切至 OpenAI 儲存 OpenAI Key，再切回 Claude。查證用 Claude Key，圖片用 OpenAI Key。缺少圖片金鑰時會在發出查證請求之前停止；只有 Claude Key 仍可生成例句。

Claude 的 token 用量與請求結果會記錄在 AI 費用紀錄，但金額標為未知，請以 Anthropic 帳單為準。請求取消或逾時仍可能計費；程式不會自動重送付費請求。

實作共用原有例句提示、JSON schema 與回應驗證，未新增套件。Claude 例句使用結構化輸出；網路查證因 citations 與結構化輸出的相容性限制，採 JSON 提示與本機格式驗證，來源取自搜尋工具回傳。

參考：[Claude Messages API](https://platform.claude.com/docs/en/api/messages)、[Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)、[Web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)、[Claude 圖片能力](https://support.claude.com/en/articles/9002504-can-claude-produce-images)。

驗證使用模擬 HTTP 回應，未執行實際付費 API 呼叫。
