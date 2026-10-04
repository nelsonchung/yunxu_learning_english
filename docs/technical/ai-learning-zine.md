# AI 單字小誌與費用追蹤

## 使用方式

1. 在設定頁的「AI 學習圖卡」輸入並儲存個人 OpenAI API Key。
2. 選擇精緻模式（Sunburst，預設）或快速模式（Flare）。
3. 在單字詳情點選「AI 生成學習圖卡」，再點「核對並生成圖片」。
4. 有詞義差異時選擇目前內容或核對內容；選擇只影響圖片，不修改單字文字。
5. 預覽並放大檢查繁體中文、例句與圖解，按「使用這張圖片」才保存。

模型可能寫錯字或圖解，使用前需檢查。每次生成、重新生成都可能計費。重新生成沿用已核對內容，只呼叫圖片 API。App 內可以返回其他頁面，工作仍繼續；關閉 App 或切至背景後不保證完成，也不提供工作恢復。

## 設定與資料

- 支援目標：macOS、iOS、Android。使用個人金鑰直接呼叫 `https://api.openai.com`，沒有共用後端。
- 金鑰經 `flutter_secure_storage` 保存在裝置安全儲存區。iOS 使用不可移轉、不同步的 Keychain 存取；macOS 使用 legacy Keychain，避免增加 Keychain Sharing provisioning 要求。Android 備份／裝置移轉排除安全儲存檔案。
- 金鑰不寫入 Hive、AppSettings、iCloud、費用紀錄、匯出檔或日誌。
- 非敏感模式設定、費用嘗試紀錄及圖卡來源放在獨立的 `learning_image_local` Hive box。來源按目前圖片檔名識別，不會出現在不同圖片上；這些 metadata 不隨既有 iCloud 單字同步。
- 已套用圖片沿用原有本機圖片儲存與 iCloud 流程。iCloud 的平台及建置開關維持原有設定。

## API 與費用

前置核對使用 `gpt-5.4-mini` Responses API、`web_search` 及結構化 JSON 輸出。圖片使用 Image API：

- 精緻：`gpt-image-2.5-sunburst`
- 快速：`gpt-image-2.5-flare`
- 固定設定：`1536x2304`、`high`、PNG、`n=1`

費率版本為 **2026-10-04**，標準處理，美元／百萬 tokens：

| 模型 | 文字輸入 | 快取文字輸入 | 輸出 |
| --- | ---: | ---: | ---: |
| gpt-5.4-mini | 0.75 | 0.075 | 4.50 |
| GPT Image 2.5（兩種模式） | 5.00 | 直接 Image API 不套用快取價 | 圖片 30.00 |

費率對應已知官方 snapshot（文字 `2026-03-17`、圖片 `2026-09-08`）；未知回傳版本不推測費率。

圖片輸入費率為 US$8／百萬 tokens；第一版文字產圖不傳參考圖片。每個可確認的搜尋動作為 US$0.01，搜尋內容 tokens 包含在文字 API 用量中，不能重複計帳。推理 tokens 已包含在文字輸出總數中，不額外再加一次。

生成前顯示預算估價，完成後標示「依實際用量計算的費用」。台幣固定以 US$1＝NT$32 作預算換算，不代表信用卡實際匯率或最終帳單。已知金額及未知費用分開顯示，不把未知記為零。

在送出付費請求前寫入 pending 紀錄，收到回應即先保存 allowlist 用量欄位，再解析內容／解碼圖片。紀錄包含模型、時間、request ID、用量、搜尋次數、費率日期與算出的美元金額，不保存完整提示詞或 API Key。歷史費用按儲存時的版本保存，不因日後改價重新計算。

取消只放棄結果，不保證上游停止計費。等待前一個請求結束才可再次送出，逾時／無回應費用標記未知。沒有自動重送或模型 fallback。費用紀錄亦涵蓋未套用、放棄及重生圖片，不能用「保存的圖片數」當作請求數。

官方來源：

- [圖片生成與計費](https://developers.openai.com/api/docs/guides/image-generation)
- [模型定位與提示詞](https://developers.openai.com/api/docs/guides/image-prompting)
- [官方費率](https://developers.openai.com/api/docs/pricing)
- [GPT-5.4-mini 費率](https://developers.openai.com/api/docs/models/gpt-5.4-mini)

## 安全套用

`WordsNotifier.updateWordImage` 只更新最新單字圖片與時間。套用前檢查單字仍存在，文字與詞性／例句未變更；圖片變更需要使用者確認。新圖片成功存檔及更新 repository 後才刪舊圖片；失敗會清除未提交的新圖並保留舊圖。相關本機寫入序列化，避免文字編輯、複習與圖片提交互相覆蓋。

## 驗證

自動測試使用假 API、假金鑰儲存與本機測試資料，不會產生 API 費用。

```sh
flutter analyze
flutter test
```

實際驗收需在各平台輸入自己的有效金鑰，測試 `chirp`、抽象詞、多義詞及缺少例句的單字。檢查搜尋來源可開啟、文字正確、圖片可讀、費用 ledger 用量與 OpenAI 帳戶紀錄一致，以及重啟後能讀取金鑰／模式／費用。一般金鑰不查組織 Costs API；帳單對帳仍以 OpenAI 平台為準。

## 本次實作檔案與驗證紀錄

- 介面：`lib/presentation/pages/settings_page.dart`、`word_detail_page.dart`、新增 `learning_image_page.dart` 與 `lib/presentation/widgets/ai_learning_image_settings.dart`。
- 接線／狀態：`lib/main.dart`、`lib/presentation/state/words_notifier.dart`、新增 `learning_image_notifier.dart`。
- 新增核心：`lib/domain/models/learning_image.dart`、`lib/domain/services/learning_image_service.dart`、`lib/data/storage/learning_image_store.dart`。
- 平台／依賴：`pubspec.yaml`／lock、Apple Podfile locks、plugin registrants、iOS Runner entitlements、Android manifest 與兩個備份排除 XML。
- 新增測試：`test/learning_image_test.dart`、`ai_learning_image_settings_test.dart`、`word_image_update_test.dart`、`learning_image_credentials_test.dart`、`learning_image_model_resolution_test.dart`。

2026-10-04 驗證：全套 121 個測試通過；後續來源過濾／已知 snapshot 對應的 22 個相關測試通過。`flutter analyze` 無新增問題，仍有既有 18 項 info（因此預設命令退出碼為 1）。`git diff --check` 通過。

Android debug APK、iOS debug 不簽章建置成功。macOS 既有專案的 SDKROOT 為 iphoneos，且正常簽章遇到既有 push entitlement 與 provisioning profile 不相容；未更動這些原有設定。以下參數覆寫的不簽章編譯成功：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk macosx ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath build/macos_unsigned \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet build
```

實際付費 API、真機安全儲存與 iCloud 圖片傳輸未做端到端驗收；自動測試涵蓋假 API 及安全儲存 method channel 的三平台選項。保留工作區原有變更，未建立 git commit。
