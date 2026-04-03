# Android 發行說明

- Last updated: 2026-04-03
- App: YunxuLearn
- Android package: `com.yunxu.yunxulearn`

如果你已經完成過第一次 Android 發佈設定，只想看每次發版的最短流程，請改看：

- [android-google-play-release-quickstart.md](./android-google-play-release-quickstart.md)

## 1. 目的

這份文件說明本專案如何產出可上傳到 Google Play Console 的 Android 發行檔，並整理每次發版時應該遵循的標準流程。

本專案上傳到 Google Play 時，應使用：

- Android App Bundle：`.aab`

不要把 `APK` 當成 Google Play 正式上架檔案。

## 2. 相關檔案

- [../../build_app.sh](../../build_app.sh)
- [../../tools/generate_android_keystore.sh](../../tools/generate_android_keystore.sh)
- [../../tools/prepare_google_play_release.sh](../../tools/prepare_google_play_release.sh)
- [../../android/app/build.gradle.kts](../../android/app/build.gradle.kts)
- [../../android/key.properties.example](../../android/key.properties.example)
- [../../pubspec.yaml](../../pubspec.yaml)
- [../technical/google-play-internal-testing-and-release.md](../technical/google-play-internal-testing-and-release.md)

## 3. 發行前置條件

在產出 release App Bundle 前，請先確認以下檔案存在：

- `android/key.properties`
- `android/app/upload-keystore.jks`

這兩個檔案用於 Android release signing。若缺少其一，release build 會失敗。

如果是第一次設定發佈金鑰，可執行：

```bash
./tools/generate_android_keystore.sh
```

或執行：

```bash
./build_app.sh
```

然後選：

```text
15) 產生 Android upload keystore
```

完成後請務必安全備份：

- `android/app/upload-keystore.jks`
- keystore 密碼
- key alias
- key password

## 4. 標準發版流程

### 4.1 更新版本號

本專案 Android 版本號來自 `pubspec.yaml`：

```yaml
version: x.y.z+n
```

規則：

- `x.y.z` 會成為 Android `versionName`
- `n` 會成為 Android `versionCode`
- `versionCode` 每次上傳到 Google Play 都必須比上一版大

推薦做法：

```bash
./tools/prepare_google_play_release.sh
```

或執行：

```bash
./build_app.sh
```

然後選：

```text
16) 準備下一個 Google Play 版本
```

這個腳本會：

1. 讀取目前版本
2. 預設遞增 patch 與 build number
3. 更新 `pubspec.yaml`
4. 詢問是否立即建立新的 release App Bundle

如果你想手動調整版本，也可以直接編輯 `pubspec.yaml`。

### 4.2 建立可上傳的 AAB

執行：

```bash
./build_app.sh
```

然後選：

```text
2) Android (AppBundle)
```

等同於執行：

```bash
flutter build appbundle --release
```

成功後輸出檔案位置為：

```text
build/app/outputs/bundle/release/app-release.aab
```

這個 `.aab` 就是要上傳到 Google Play Console 的檔案。

## 5. 上傳到 Google Play Console

在 Google Play Console 中：

1. 進入此 App
2. 選擇要發佈的 track
3. 建立新版本或編輯現有版本
4. 上傳 `app-release.aab`
5. 填寫 release name 與 release notes
6. 完成檢查後送出發布

常見 track 包含：

- Internal testing：內部測試
- Closed testing：封閉測試
- Production：正式上架

如果是第一次上架，除了上傳 AAB 之外，通常還需要先補齊商店素材與商店資訊，例如：

- App 名稱
- App icon
- Feature graphic
- 手機螢幕截圖
- App 描述

## 6. 發版檢查清單

每次 Android 發版前，至少確認以下項目：

1. `pubspec.yaml` 版本號已更新
2. `versionCode` 比 Google Play 上一版大
3. `android/key.properties` 內容正確
4. `android/app/upload-keystore.jks` 存在
5. `flutter build appbundle --release` 成功
6. 要上傳的是最新產出的 `app-release.aab`
7. 已準備好 release notes
8. 若為首次上架，商店素材已補齊

## 7. 常見問題

### 7.1 缺少 `android/key.properties`

代表 release signing 尚未設定完成。

處理方式：

1. 執行 `./tools/generate_android_keystore.sh`
2. 或參考 `android/key.properties.example` 手動建立設定

### 7.2 找不到 keystore

通常表示 `android/key.properties` 內的 `storeFile` 路徑錯誤，或 `upload-keystore.jks` 不在預期位置。

### 7.3 版本無法上傳到 Google Play

最常見原因是 `versionCode` 沒有遞增。請更新 `pubspec.yaml` 後重新 build。

### 7.4 上傳了錯的檔案

Google Play 正式上傳請使用：

- `build/app/outputs/bundle/release/app-release.aab`

不是 `APK`。

## 8. 建議操作範例

```bash
./build_app.sh
```

建議流程：

1. 先選 `16) 準備下一個 Google Play 版本`
2. 確認版本號
3. 讓腳本直接建立 App Bundle，或之後再選 `2) Android (AppBundle)`
4. 上傳 `build/app/outputs/bundle/release/app-release.aab` 到 Google Play Console

## 9. 備註

- release signing 設定由 `android/app/build.gradle.kts` 讀取 `android/key.properties`
- `applicationId` 目前為 `com.yunxu.yunxulearn`
- `android/key.properties` 與 keystore 屬於敏感資料，不應提交到版本控制
