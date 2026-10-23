# GitHub 單字圖片庫

App 的公開圖片來源為 [yunxu_learning_english_pictures](https://github.com/nelsonchung/yunxu_learning_english_pictures)，讀取 `main` 分支檔案：

```text
https://raw.githubusercontent.com/nelsonchung/yunxu_learning_english_pictures/main/manifest.json
https://raw.githubusercontent.com/nelsonchung/yunxu_learning_english_pictures/main/apple.png
```

使用者在單字詳細頁主動點擊下載，下載成功後先預覽，再決定是否套用。套用後沿用 App 本機圖片儲存流程，可離線查看；下載失敗不替換既有圖片。公開下載不需要 GitHub Token，請勿把上傳用憑證放入 App。

## 逐步補圖

建議用 `manifest.json` 對應單字與實際圖片路徑；索引鍵為檔名去除副檔名、去除前後空白後轉小寫，路徑仍保留原本大小寫。例如：

```json
{
  "version": 1,
  "images": {
    "apple": {"path": "Apple.png", "bytes": 123456}
  }
}
```

App 約每日重新整理索引。索引沒有單字時會重新查詢最新資料，避免舊的缺圖結果一直保留。索引尚未建立時，App 會依序嘗試「原單字.png」及「小寫單字.png」，因此目前根目錄的圖片仍可使用。要支援子目錄或不同大小寫的檔名，請發佈索引。

新增圖片並更新索引後，使用者下次查詢即可取得，無須為新增圖片重新上架 App。已套用圖片不會自動被遠端新圖替換。

## 產生及發佈索引

將本 App 專案的 `tools/generate_picture_manifest.py` 複製至圖片 repository 的 `tools/` 目錄，於圖片 repository 根目錄執行：

```sh
python3 tools/generate_picture_manifest.py . --output manifest.json
```

檢查 `manifest.json` 後，將新增圖片與索引一併提交及推送到 `main`。產生器只使用 Python 標準函式庫，會遞迴掃描 PNG（含 `.PNG`）、略過隱藏目錄／檔案及符號連結，依單字排序並記錄實際位元組數。相同索引鍵對應多張圖片時會報錯，請先改名或移除衝突圖片，再重新產生。請保留原圖備份。

驗證工具：

```sh
python3 -m unittest discover -s tools/tests -p 'test_generate_picture_manifest.py'
```

## 可選：在圖片 repository 自動更新

以下檔案可放在圖片 repository 的 `.github/workflows/picture-manifest.yml`。僅 PNG 或產生器變動觸發，自動提交只改索引，因此不會反覆觸發。repository 必須允許 Actions 寫入內容；也可以保留上述手動產生流程。

```yaml
name: Update picture manifest
on:
  push:
    branches: [main]
    paths:
      - '**/*.png'
      - '**/*.PNG'
      - 'tools/generate_picture_manifest.py'
  workflow_dispatch:
permissions:
  contents: write
concurrency:
  group: picture-manifest
  cancel-in-progress: false
jobs:
  manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - run: python tools/generate_picture_manifest.py . --output manifest.json
      - name: Commit changed manifest
        run: |
          git add manifest.json
          if git diff --cached --quiet; then exit 0; fi
          git config user.name 'github-actions[bot]'
          git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
          git commit -m 'Keep published picture lookup aligned with available images'
          git push
```

此功能下載公開圖片；GitHub 連線失敗或受限時應提供重試，使用者也可繼續使用本機選圖與 AI 生成。Web 平台受既有本機圖片儲存方式限制，需獨立驗證。
