# Cloud Backup Design Overview (iOS + macOS)

- Date: 2026-02-10
- Scope: YunxuLearn
- Platforms: iOS, macOS

本文件已拆分為兩份技術文件，避免同步規則與備份/還原流程混在同一份規格中。

## 文件導覽
1. 同步功能規格：
   - `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/cloud-sync.md`
2. 備份與還原規格：
   - `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/backup-restore.md`
3. 架構決策（ADR）：
   - `/Users/nelsonchung/development/yunxu_learning_english/docs/technical/adr-cloud-backup-cloudkit-private-db.md`

## 拆分原則
1. `cloud-sync.md`：只包含同步策略、衝突規則、刪除語義、觸發條件與可觀測性。
2. `backup-restore.md`：只包含備份範圍、重裝還原判定、使用者還原流程與驗收條件。
