# AGENTS.md

Flutter 英文學習 App,支援 Android / iOS / macOS / Windows / Linux / Web。Dart SDK ^3.10.8,使用 `flutter_lints`、Hive 做本機儲存、Provider 做依賴注入與狀態管理。

## 指令

- 靜態分析:`flutter analyze`
- 全部測試:`flutter test`
- 單一測試檔:`flutter test test/today_page_test.dart`
- macOS debug 執行:`flutter run -d macos`
- 各平台建置/執行/發佈的互動式選單:`./build_app.sh`

## 架構

- `lib/` 下採近似 Clean Architecture 分層:`data/`(repository + Hive 本地 db + 圖片儲存)、`domain/`(model + service)、`presentation/`(頁面、state notifier、主題)。
- 進入點 `lib/main.dart` 用 `MultiProvider` 手動接線 — 沒有 DI framework;新增 service 必須在那裡建構並往下傳。
- 持久化用 Hive(`WordLocalDb`、`SettingsLocalDb`、`SyncStateLocalDb`),沒有 SQL/migration 工具。

## 平台陷阱

- iCloud 同步只在 macOS 啟用;iOS 需以 `--dart-define=ENABLE_IOS_CLOUD_SYNC=true` 建置才啟用(見 `lib/main.dart`)。Personal Team 的 iOS 建置無法使用 iCloud capability。
- macOS Archive 上傳會遇到 ITMS-90291(`objective_c.framework`)— 每次 Xcode Archive 後、上傳到 App Store Connect 前,必須重新執行 `./fix_macos_archive_frameworks.sh && ./check_macos_archive_frameworks.sh`。詳見 README.md。
- 在 `macos/` 目錄執行 `pod install` 需要 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`,否則會失敗(見 `docs/technical/macos-pod-install-utf8-locale-issue.md`;`build_app.sh` 已處理)。
- Android release 建置需要 `android/key.properties` 簽署設定(透過 `./tools/generate_android_keystore.sh` 產生)。

## 單字庫資產

- 內建字典放在 26 個 JSON shard `assets/word_bank/word_bank_main-[a-z].json`,全部明確列在 `pubspec.yaml`。新增 shard 必須同步編輯 pubspec。
- 不要隨手手改 shard — 改完必須驗證:
  1. `python3 tools/audit_word_bank_shards.py`
  2. `python3 tools/validate_word_bank_main.py --path assets/word_bank/word_bank_main-X.json`
  3. `python3 tools/review_word_bank_content.py --path assets/word_bank/... --format json`

## tools 目錄

`tools/` 混雜了正式腳本與舊版/一次性腳本。使用任何腳本前先讀 `tools/README.md` — 它標示了哪些是正式入口(如 `letter_word_bank_workflow.py`、`run_letter_local_round.py`)、哪些已棄用或壞掉(如 `rebuild_letter_review_candidates.py` 目前無法執行)。

## 測試

`test/` 的 widget/service 測試各自建立 Provider tree 與假 repository(沒有共用 test harness)。新增頁面/provider 若需要新依賴,請比照 `test/today_page_test.dart` 的設定模式。

## 文件

詳細疑難排解與設計文件在 `docs/technical/`;商店上架流程在 `docs/release/` 與 `docs/publication/`。
