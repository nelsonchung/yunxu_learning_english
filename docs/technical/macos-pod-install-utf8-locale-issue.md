# macOS `pod install` 因 UTF-8 Locale 失敗排查紀錄

本文件記錄一次在 macOS 專案中執行 `pod install` 失敗的問題，根因是 shell locale 不是 UTF-8，造成 CocoaPods/Ruby 在字串正規化時拋錯。

## 問題背景
- 情境：使用 `flutter clean` + `flutter pub get` 後，執行 `pod install`。
- 表面上看起來 Flutter build 可能成功，但 Xcode `Product -> Archive` 時出現：
  - `No such module 'file_selector_macos'`

## 典型錯誤訊息
在終端機執行 `pod install` 時可看到：

```text
WARNING: CocoaPods requires your terminal to be using UTF-8 encoding.
Consider adding the following to ~/.profile:
export LANG=en_US.UTF-8
```

以及 Ruby 例外：

```text
Unicode Normalization not appropriate for ASCII-8BIT (Encoding::CompatibilityError)
```

## 根因
- 當前 shell 的 `LANG` / `LC_ALL` 非 UTF-8。
- CocoaPods（Ruby）讀取專案路徑或 Podfile 時觸發 Unicode normalize，因編碼不匹配而失敗。
- `pod install` 沒成功，導致 `Pods` 沒正確更新，最終在 Xcode 端出現 plugin module 缺失。

## 立即修正方式
在執行 `pod install` 時強制指定 UTF-8：

```bash
cd /Users/nelsonchung/development/yunxu_learning_english/macos
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
```

## 永久修正方式（shell）
在 shell 設定檔加入：

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

常見檔案：
- zsh: `~/.zshrc`
- bash: `~/.bash_profile` 或 `~/.profile`

加入後重開終端機，再確認：

```bash
locale
```

`LANG` 與 `LC_ALL` 應為 `en_US.UTF-8`（或其他 UTF-8 locale）。

## 本專案落地做法
已在 `build_app.sh` 加入 `run_macos_pod_install()`，內部固定用 UTF-8：

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
```

同時 `11/12/13` 選項改為 `&&` 連鎖執行，任何一步失敗就中止，避免「中間失敗但後續繼續跑」導致誤判成功。

## 建議操作流程（Archive 前）
1. 先跑 `build_app.sh` 選 `12`（清理 + 依賴 + pod install + macOS build）。
2. 用 `Runner.xcworkspace` 開 Xcode。
3. `Product -> Archive`。
4. 再跑 `build_app.sh` 選 `13`（修正與檢查 archive framework symlink）。
5. `PASS` 後再上傳。

## 相關文件
- `docs/technical/macos-archive-itms-90291-objective-c-framework.md`
