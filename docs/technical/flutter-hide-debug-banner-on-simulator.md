# Flutter 在 iPhone/iPad 模擬器隱藏 DEBUG 標記

- Date: 2026-02-12
- Commit: `1ef30b3ade1218e3db2dfe2c61e50791cd165d2b`
- Scope: Flutter UI（`MaterialApp`）

## 1. 背景
在 iPhone / iPad 模擬器以 Debug 模式執行時，畫面右上角會出現 `DEBUG` 標記，影響畫面展示與截圖。

## 2. 變更內容
於 `MaterialApp` 設定中加入：

```dart
debugShowCheckedModeBanner: false,
```

實際位置：`lib/main.dart`

## 3. 影響與說明
1. 僅隱藏視覺上的 `DEBUG` 標記，不改變 Debug 模式行為。
2. 不影響 Release 版功能與效能。
3. iOS 與 iPadOS 模擬器畫面會更接近正式展示效果。

## 4. 驗證方式
1. 執行 `flutter run`（iPhone 或 iPad 模擬器）。
2. 確認畫面右上角不再顯示 `DEBUG`。
3. 基本檢查主要頁面是否可正常啟動與操作。

## 5. 回復方式
若後續需要重新顯示標記，可移除或改回該設定。
