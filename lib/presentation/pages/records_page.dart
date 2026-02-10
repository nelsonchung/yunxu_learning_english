import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/sync_state.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        final syncSupported = notifier.syncSupported;
        final syncEnabled = notifier.syncEnabled;
        final canSync = notifier.canSync;
        final isSyncing = notifier.isSyncing;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '雲端同步紀錄',
              subtitle: 'iCloud 備份與還原狀態',
              trailing: Icon(
                canSync ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: const Color(0xFF0B6E99),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: '同步功能',
                    value: syncSupported
                        ? (syncEnabled ? '可用（iOS/macOS）' : '已停用（可在設定開啟）')
                        : '目前平台不支援',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(label: '目前狀態', value: isSyncing ? '同步中' : '待命'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '最後同步',
                    value: _formatDateTime(notifier.lastSyncAt),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '最近嘗試',
                    value: _formatDateTime(notifier.lastSyncAttemptAt),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '還原判定',
                    value: _restoreStatusText(notifier.restoreStatus),
                  ),
                  if (notifier.hasSyncError) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '錯誤代碼',
                      value: notifier.lastSyncErrorCode ?? '-',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notifier.lastSyncErrorMessage ?? '未知錯誤',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (!canSync || isSyncing)
                          ? null
                          : () async {
                              final ok = await notifier.syncNow();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '同步完成' : '同步失敗，請稍後重試'),
                                ),
                              );
                            },
                      icon: isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(isSyncing ? '同步中...' : '立即同步'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '本地資料統計',
              subtitle: '裝置內目前資料量',
              trailing: const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: '單字總數', value: '${notifier.totalWords}'),
                  const SizedBox(height: 8),
                  _InfoRow(label: '待複習數', value: '${notifier.dueWordsCount}'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _restoreStatusText(RestoreStatus status) {
    switch (status) {
      case RestoreStatus.idle:
        return '待判定';
      case RestoreStatus.restoring:
        return '還原中';
      case RestoreStatus.restored:
        return '重裝還原成功';
      case RestoreStatus.newInstall:
        return '新安裝用戶';
      case RestoreStatus.failed:
        return '還原失敗（可重試）';
    }
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}
