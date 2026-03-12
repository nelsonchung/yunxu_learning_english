# Google Play 內部測試與 Android 上架流程

- Date: 2026-03-12
- App: YunxuLearn
- Android applicationId: `com.yunxu.yunxulearn`
- Current version at time of writing: `1.0.3+1`

## 1. 目的

這份文件用來記錄本專案目前的 Android 發佈流程，讓之後可以重複完成以下工作：

1. 建立 Android upload keystore
2. 產出可上傳到 Google Play Console 的 `.aab`
3. 上傳到 Google Play 內部測試
4. 把測試安裝連結提供給測試人員
5. 進行下一版更新時正確遞增版本號

## 2. 目前專案設定

目前 Android 發佈相關設定如下：

- `applicationId`: `com.yunxu.yunxulearn`
- `namespace`: `com.yunxu.yunxulearn`
- release signing config 由 `android/key.properties` 讀取
- keystore 預設位置：`android/app/upload-keystore.jks`

相關檔案：

- [pubspec.yaml](/Users/nelsonchung/development/yunxu_learning_english/pubspec.yaml)
- [android/app/build.gradle.kts](/Users/nelsonchung/development/yunxu_learning_english/android/app/build.gradle.kts)
- [android/key.properties.example](/Users/nelsonchung/development/yunxu_learning_english/android/key.properties.example)
- [build_app.sh](/Users/nelsonchung/development/yunxu_learning_english/build_app.sh)
- [tools/generate_android_keystore.sh](/Users/nelsonchung/development/yunxu_learning_english/tools/generate_android_keystore.sh)

## 3. 第一次建立 Android 發佈金鑰

如果本機還沒有以下兩個檔案：

- `android/app/upload-keystore.jks`
- `android/key.properties`

請在專案根目錄執行：

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

填寫建議：

- `Key alias`: 直接按 Enter，使用預設 `upload`
- `Keystore validity days`: 直接按 Enter，使用預設 `10000`
- `Certificate DName`: 可直接按 Enter 使用預設值
- `Store password`: 自訂強密碼
- `Key password`: 可與 `Store password` 相同，便於管理

完成後會產生：

- `android/app/upload-keystore.jks`
- `android/key.properties`

注意：

- `upload-keystore.jks` 與密碼一定要安全備份
- `android/key.properties` 不應提交到 git
- keystore 遺失後雖然仍可透過 Play App Signing 補救，但流程會更麻煩

## 4. 產出可上傳的 App Bundle

在專案根目錄執行：

```bash
flutter build appbundle --release
```

或執行：

```bash
./build_app.sh
```

然後選：

```text
2) Android (AppBundle)
```

成功後產物位置：

```text
build/app/outputs/bundle/release/app-release.aab
```

如果 release signing 檔案缺失，build 會直接失敗並提示：

- 缺少 `android/key.properties`
- `android/key.properties` 少欄位
- keystore 路徑錯誤

## 5. Google Play Console 上傳流程

### 5.1 上傳內部測試版本

在 Google Play Console：

1. 進入此 App
2. 選擇 `測試 > 內部測試`
3. 建立新版本或升級現有版本
4. 上傳 `app-release.aab`
5. 填寫版本名稱
6. 填寫版本資訊
7. 發布到內部測試

本專案第一次上傳時，Google Play 會顯示：

- 版本：`1 (1.0.3)`
- 最低 API：`24`
- 目標 SDK：`36`

### 5.2 第一次內部測試可能出現的暫時顯示

第一次建立 Play 測試版本時，安裝頁可能暫時顯示：

- `com.yunxu.yunxulearn (unreviewed)`
- 暫定應用程式名稱
- 非最終商店圖示

這通常不是 Android 程式碼壞掉，而是 Google Play 在第一次審核完成前的暫時狀態。

需要另外確認兩件事：

1. `Main store listing` 已填好正式 app 名稱
2. `Main store listing` 已上傳高解析度 app icon

本專案可直接使用的 Play icon 素材：

- [docs/publication/google-play/google-play-icon-512.png](/Users/nelsonchung/development/yunxu_learning_english/docs/publication/google-play/google-play-icon-512.png)

建議：

1. 在 Play Console 的主商店資訊上傳這張 `512x512` PNG
2. 完成商店資訊後送審
3. 等待 Play 處理完成後再確認安裝頁名稱與圖示是否恢復正常
### 5.3 版本名稱建議

版本名稱是 Play Console 內部辨識用，使用者通常不會看到。

建議格式：

- `1.0.3 (1) 首次上架`
- `prod-1.0.3+1`
- `internal-1.0.3+1`

### 5.4 版本資訊範例

首次上架可用：

```text
<zh-TW>
首次上架版本。

功能包含：
- 英文單字學習與複習
- 單字發音播放
- 單字圖片新增與編輯
- 複習提醒通知
</zh-TW>
```

## 6. 內部測試人員安裝流程

### 6.1 加入測試人員

在 `內部測試 > 測試人數`：

1. 建立電子郵件名單
2. 把測試人員的 Google 帳號 email 加進名單
3. 勾選該名單到這個內部測試 track

### 6.2 提供安裝連結

Google Play Console 不一定會自動寄出安裝邀請信。

目前本專案採用的方式是：

1. 在 `內部測試 > 測試人數`
2. 找到「測試人員可透過網路加入您的測試」
3. 點 `複製連結`
4. 由開發者手動把連結傳給測試人員

### 6.3 測試人員需要注意

測試人員必須：

1. 使用被加入名單的 Google 帳號開啟連結
2. Android 裝置上的 Play 商店最好也登入同一個帳號
3. 點擊連結後加入測試，再前往 Play 商店安裝

如果點了連結還無法安裝，優先檢查：

1. 是否用錯 Google 帳號
2. Play 商店是否登入同一帳號
3. 版本是否剛發布，尚未完成同步
4. 裝置是否不相容

## 7. 下一次發版前要做的事

每次要上傳新版本前，先修改 [pubspec.yaml](/Users/nelsonchung/development/yunxu_learning_english/pubspec.yaml)：

```yaml
version: 1.0.4+2
```

規則：

- 前面的 `1.0.4` 是 `versionName`
- 後面的 `+2` 是 `versionCode`
- `versionCode` 必須比上一版大

範例：

- 第一版：`1.0.3+1`
- 下一版：`1.0.4+2`
- 再下一版：`1.0.5+3`

改完後重新產出：

```bash
flutter build appbundle --release
```

再上傳到 Play Console 新版本即可。

## 8. 建議的發版檢查清單

每次 Android 發版前，至少檢查以下項目：

1. `pubspec.yaml` 版本號已遞增
2. `android/key.properties` 存在且內容正確
3. `android/app/upload-keystore.jks` 存在
4. `flutter build appbundle --release` 成功
5. 已確認上傳的是最新的 `app-release.aab`
6. Play Console 版本資訊已更新
7. 內部測試 email 名單已正確勾選
8. 已把內部測試連結傳給測試人員

## 9. 目前已驗證成功的事項

截至 2026-03-12，以下流程已實際驗證成功：

1. 產生 Android upload keystore
2. 產出 `app-release.aab`
3. 成功上傳到 Google Play Console
4. 成功建立內部測試版本
5. 測試人員可透過測試連結與 Google Play 安裝 App

## 10. 備註

- `applicationId` 目前已與 Apple bundle identifier 對齊：`com.yunxu.yunxulearn`
- Play Console 內部測試最多可提供 100 位內部測試人員
- `android/key.properties` 與 keystore 屬於敏感資料，不應提交到版本控制
