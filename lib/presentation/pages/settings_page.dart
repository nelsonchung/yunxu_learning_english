import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_notifier.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _pickTime(BuildContext context) async {
    final notifier = context.read<SettingsNotifier>();
    final initial = notifier.reminderTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      await notifier.setReminderTime(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsNotifier, WordsNotifier>(
      builder: (context, notifier, wordsNotifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;
        const syncIntervals = [5, 10, 20, 30, 60, 3600];
        final cloudSupported = wordsNotifier.syncSupported;
        final isCloudBusy =
            wordsNotifier.isSyncing ||
            wordsNotifier.isBackingUp ||
            wordsNotifier.isRestoring;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '提醒功能',
              subtitle: '開啟後會在設定時間提醒複習',
              trailing: const Icon(Icons.alarm, color: Color(0xFF0B6E99)),
              child: Row(
                children: [
                  const Expanded(child: Text('啟用提醒')),
                  Switch(
                    value: notifier.reminderEnabled,
                    onChanged: notifier.setReminderEnabled,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '提醒時間',
              subtitle: '設定每天提醒複習的時間',
              trailing: const Icon(
                Icons.notifications_active_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Row(
                children: [
                  Text('目前：${notifier.reminderTime.format(context)}'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: notifier.reminderEnabled
                        ? () => _pickTime(context)
                        : null,
                    child: const Text('設定時間'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '圖片欄位顯示',
              subtitle: '控制新增/編輯頁是否顯示圖片欄位',
              trailing: const Icon(
                Icons.image_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Row(
                children: [
                  const Expanded(child: Text('顯示圖片欄位')),
                  Switch(
                    value: notifier.showImages,
                    onChanged: notifier.setShowImages,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '雲端同步',
              subtitle: '開啟後自動同步與手動同步才會生效',
              trailing: const Icon(Icons.cloud_sync, color: Color(0xFF0B6E99)),
              child: Row(
                children: [
                  const Expanded(child: Text('啟用同步功能')),
                  Switch(
                    value: notifier.syncEnabled,
                    onChanged: (value) async {
                      await notifier.setSyncEnabled(value);
                      if (context.mounted) {
                        context.read<WordsNotifier>().setSyncEnabled(value);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '同步頻率',
              subtitle: 'App 開啟時每隔固定秒數同步',
              trailing: const Icon(Icons.sync, color: Color(0xFF0B6E99)),
              child: Row(
                children: [
                  const Expanded(child: Text('同步間隔')),
                  DropdownButton<int>(
                    value: notifier.syncIntervalSeconds,
                    items: syncIntervals
                        .map(
                          (seconds) => DropdownMenuItem(
                            value: seconds,
                            child: Text(
                              seconds >= 3600
                                  ? '${seconds ~/ 3600} 小時'
                                  : '$seconds 秒',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: notifier.syncEnabled
                        ? (value) async {
                            if (value == null) {
                              return;
                            }
                            await notifier.setSyncIntervalSeconds(value);
                            if (context.mounted) {
                              context
                                  .read<WordsNotifier>()
                                  .setSyncIntervalSeconds(value);
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
            if (!notifier.syncEnabled) ...[
              const SizedBox(height: 10),
              Text(
                '同步已停用：不會自動同步，也無法手動同步。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: '雲端備份與還原',
              subtitle: '手動備份本機資料，或立即從雲端還原',
              trailing: const Icon(
                Icons.cloud_upload_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (!cloudSupported || isCloudBusy)
                              ? null
                              : () async {
                                  final ok = await wordsNotifier.backupNow();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? '備份完成' : '備份失敗，請稍後重試'),
                                    ),
                                  );
                                },
                          icon: wordsNotifier.isBackingUp
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.backup_outlined),
                          label: Text(
                            wordsNotifier.isBackingUp ? '備份中...' : '立即備份',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (!cloudSupported || isCloudBusy)
                              ? null
                              : () async {
                                  final shouldRestore = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('從雲端還原'),
                                      content: const Text(
                                        '將從 iCloud 拉取資料並合併本機資料，是否繼續？',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                          child: const Text('開始還原'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (shouldRestore != true) {
                                    return;
                                  }
                                  final ok = await wordsNotifier.restoreNow();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? '還原完成' : '還原失敗，請稍後重試'),
                                    ),
                                  );
                                },
                          icon: wordsNotifier.isRestoring
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(
                            wordsNotifier.isRestoring ? '還原中...' : '立即還原',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!cloudSupported) ...[
                    const SizedBox(height: 10),
                    Text(
                      '目前平台不支援 CloudKit，無法使用手動備份/還原。',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
