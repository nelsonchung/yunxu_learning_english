# Android Google Play 發版快速流程

- Last updated: 2026-04-03
- App: YunxuLearn
- Android package: `com.yunxu.yunxulearn`

## 1. 這份文件的用途

這份文件給「已經完成過第一次 Android 發佈設定」的人使用。

也就是說，你的專案中已經有以下檔案：

- `android/key.properties`
- `android/app/upload-keystore.jks`

在這個前提下，之後每次要產出新的 Android 發行檔，只要透過 `build_app.sh` 的 `16) 準備下一個 Google Play 版本` 即可。

## 2. 結論

如果前面的 release signing 都已經設定完成，那麼：

1. 執行 `./build_app.sh`
2. 選 `16) 準備下一個 Google Play 版本`
3. 確認或修改下一版版本號
4. 在 `是否立即建立 Android AppBundle? [Y/n]:` 直接按 Enter 或輸入 `Y`

完成後產出的檔案：

```text
build/app/outputs/bundle/release/app-release.aab
```

這個 `app-release.aab` 就是可以上傳到 Google Play Console 的檔案。

上傳完成後，可以透過 Google Play 的測試 track 發布，再把測試連結分享給客戶。

## 3. 實際操作步驟

### 3.1 在專案根目錄執行

```bash
./build_app.sh
```

### 3.2 選擇功能

在選單中輸入：

```text
16
```

也就是：

```text
16) 準備下一個 Google Play 版本
```

### 3.3 確認版本號

腳本會讀取目前 `pubspec.yaml` 的版本，例如：

```text
目前版本：1.0.7+2
建議下一版：1.0.8+3
```

接著你可以：

- 直接按 Enter 使用建議版本
- 或手動輸入你要的 `versionName`
- 或手動輸入你要的 `build number`

版本規則：

- `x.y.z` 會成為 Android `versionName`
- `+n` 會成為 Android `versionCode`
- `versionCode` 必須大於 Google Play 上一版

### 3.4 建立 App Bundle

腳本接著會問：

```text
是否立即建立 Android AppBundle? [Y/n]:
```

此時請直接按 Enter 或輸入 `Y`。

這一步很重要。

如果你選擇 `Y`，腳本會直接建立 release App Bundle，也就是 Google Play 要上傳的正式檔案。

### 3.5 取得輸出檔案

建立成功後，輸出檔案位置為：

```text
build/app/outputs/bundle/release/app-release.aab
```

這就是要上傳到 Google Play Console 的檔案。

不要上傳：

- `APK`

Google Play 正式發布請以上傳 `.aab` 為主。

## 4. `16)` 實際做了什麼

`build_app.sh` 的 `16)` 會呼叫：

```bash
./tools/prepare_google_play_release.sh
```

這個腳本會做以下事情：

1. 讀取目前 `pubspec.yaml` 的版本
2. 建議下一版的 `versionName` 與 `build number`
3. 更新 `pubspec.yaml`
4. 在你確認後執行 `flutter build appbundle --release`
5. 產出 `app-release.aab`

所以對已經完成初次設定的人來說，`16)` 就是平常發版最方便的入口。

## 5. 上傳到 Google Play Console

拿到 `app-release.aab` 後，在 Google Play Console：

1. 進入 App
2. 選擇要使用的 release track
3. 建立新版本
4. 上傳 `build/app/outputs/bundle/release/app-release.aab`
5. 填寫 release notes
6. 發布該版本

如果你的目的是讓客戶先安裝測試，通常會用測試 track，而不是直接上正式版。

常見做法：

- `Internal testing`：快速內部驗證
- `Closed testing`：提供指定客戶或指定名單測試

## 6. 分享給客戶的方式

當版本已經發布到測試 track 後，可以在 Google Play Console 複製測試連結，再把該連結提供給客戶。

客戶通常需要：

1. 使用指定的 Google 帳號開啟測試連結
2. 加入測試
3. 從 Google Play 安裝 App

如果你是要給外部客戶驗收，通常建議使用 `Closed testing`，方便控制可安裝的人員名單。

## 7. 最短工作流程

每次發版時，可以直接照下面做：

1. 執行 `./build_app.sh`
2. 選 `16)`
3. 確認版本號
4. 選擇立即建立 App Bundle
5. 取得 `build/app/outputs/bundle/release/app-release.aab`
6. 上傳到 Google Play Console
7. 發布到測試 track
8. 複製測試連結給客戶

## 8. 補充說明

如果你在 `16)` 的最後選了 `n`，那就只會更新版本號，不會立即產出 `.aab`。

這種情況下，你還需要再執行一次：

```bash
./build_app.sh
```

然後選：

```text
2) Android (AppBundle)
```

## 9. 常見失敗原因

### 9.1 缺少 `android/key.properties`

代表本機沒有完成 Android release signing 設定。

### 9.2 缺少 `android/app/upload-keystore.jks`

代表本機沒有對應的 upload keystore，因此無法產出可上傳的 release 檔。

### 9.3 `versionCode` 沒有增加

Google Play 會拒絕上傳版本號未遞增的檔案。

## 10. 相關文件

- [android-google-play-release.md](./android-google-play-release.md)
- [../technical/google-play-internal-testing-and-release.md](../technical/google-play-internal-testing-and-release.md)
