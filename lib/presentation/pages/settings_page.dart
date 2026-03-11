import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/services/word_contribution_share_service.dart';
import '../state/settings_notifier.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isSharingDeveloperWords = false;

  Future<void> _pickTime(BuildContext context) async {
    final notifier = context.read<SettingsNotifier>();
    final initial = notifier.reminderTime;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      await notifier.setReminderTime(picked);
    }
  }

  Future<bool?> _showDeveloperShareDialog({
    required int manualCount,
    required int unknownCount,
  }) {
    var includeUnknown = manualCount == 0 && unknownCount > 0;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final totalCount =
                manualCount + (includeUnknown ? unknownCount : 0);

            return AlertDialog(
              title: const Text('分享新增單字 JSON'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('會匯出 JSON 檔並開啟系統分享表單。'),
                  const SizedBox(height: 10),
                  const Text('分享內容只包含文字資料與建立時間，不含圖片檔本體。'),
                  const SizedBox(height: 12),
                  Text('使用者新增：$manualCount 筆'),
                  if (unknownCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: includeUnknown,
                          onChanged: (value) {
                            setDialogState(() {
                              includeUnknown = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text('包含來源未知的舊資料（$unknownCount 筆）'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text('本次匯出：$totalCount 筆'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: totalCount <= 0
                      ? null
                      : () => Navigator.pop(dialogContext, includeUnknown),
                  child: const Text('匯出 JSON'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _shareDeveloperWords(BuildContext buttonContext) async {
    final wordsNotifier = context.read<WordsNotifier>();
    final shareService = context.read<WordContributionShareService>();
    final manualCount = wordsNotifier.manualWordsCount;
    final unknownCount = wordsNotifier.unknownWordsCount;

    if (!shareService.isSupported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前平台不支援 JSON 檔案分享')));
      return;
    }

    if (manualCount == 0 && unknownCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前沒有可分享的新增單字')));
      return;
    }

    final includeUnknown = await _showDeveloperShareDialog(
      manualCount: manualCount,
      unknownCount: unknownCount,
    );
    if (includeUnknown == null) {
      return;
    }

    final words = wordsNotifier.developerContributionWords(
      includeUnknown: includeUnknown,
    );
    if (words.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目前沒有可分享的單字資料')));
      return;
    }

    if (!mounted || !buttonContext.mounted) {
      return;
    }

    Rect? sharePositionOrigin;
    final renderObject = buttonContext.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      sharePositionOrigin =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }

    setState(() {
      _isSharingDeveloperWords = true;
    });

    try {
      final result = await shareService.shareWords(
        words: words,
        sharePositionOrigin: sharePositionOrigin,
      );
      if (!mounted) {
        return;
      }
      final message = switch (result.shareResult.status) {
        ShareResultStatus.success =>
          '已開啟分享表單，匯出 ${result.sharedCount} 筆到 ${result.fileName}',
        ShareResultStatus.dismissed => '已取消分享，JSON 檔仍保留在暫存資料夾',
        ShareResultStatus.unavailable => '已建立 ${result.fileName}，但系統無法回報分享結果',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSharingDeveloperWords = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsNotifier, WordsNotifier>(
      builder: (context, notifier, wordsNotifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (notifier.loadError != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Color(0xFFB3261E),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '設定載入失敗',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    notifier.loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.read<SettingsNotifier>().load(),
                    child: const Text('重新載入'),
                  ),
                ],
              ),
            ),
          );
        }

        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;
        const syncIntervals = [5, 10, 20, 30, 60, 3600];
        const pronunciationLocales = [('en-US', '美式英文'), ('en-GB', '英式英文')];
        final cloudSupported = wordsNotifier.syncSupported;
        final isCloudBusy =
            wordsNotifier.isSyncing ||
            wordsNotifier.isBackingUp ||
            wordsNotifier.isRestoring;
        final shareService = context.read<WordContributionShareService>();
        final hasDeveloperShareCandidates =
            wordsNotifier.manualWordsCount > 0 ||
            wordsNotifier.unknownWordsCount > 0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '提醒功能',
              subtitle: '開啟後會在設定時間提醒複習',
              trailing: const Icon(Icons.alarm, color: Color(0xFF0B6E99)),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('啟用提醒')),
                      Switch(
                        value: notifier.reminderEnabled,
                        onChanged: notifier.setReminderEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
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
              title: '單字發音',
              subtitle: notifier.pronunciationSupported
                  ? '使用裝置語音引擎朗讀單字'
                  : '目前平台暫不支援發音功能',
              trailing: const Icon(Icons.volume_up, color: Color(0xFF0B6E99)),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('啟用單字發音')),
                      Switch(
                        value: notifier.pronunciationEnabled,
                        onChanged: notifier.pronunciationSupported
                            ? notifier.setPronunciationEnabled
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(child: Text('發音口音')),
                      DropdownButton<String>(
                        value: notifier.pronunciationLocale,
                        items: pronunciationLocales
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item.$1,
                                child: Text(item.$2),
                              ),
                            )
                            .toList(),
                        onChanged:
                            notifier.pronunciationSupported &&
                                notifier.pronunciationEnabled
                            ? (value) async {
                                if (value == null) {
                                  return;
                                }
                                await notifier.setPronunciationLocale(value);
                              }
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(child: Text('語速')),
                      Text(notifier.pronunciationRate.toStringAsFixed(2)),
                    ],
                  ),
                  Slider(
                    min: 0.2,
                    max: 0.7,
                    divisions: 10,
                    value: notifier.pronunciationRate,
                    onChanged:
                        notifier.pronunciationSupported &&
                            notifier.pronunciationEnabled
                        ? (value) => notifier.setPronunciationRate(value)
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '雲端同步',
              subtitle: '開啟後自動同步與手動同步才會生效',
              trailing: const Icon(Icons.cloud_sync, color: Color(0xFF0B6E99)),
              child: Column(
                children: [
                  Row(
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
                  const SizedBox(height: 10),
                  Row(
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
                  if (!notifier.syncEnabled) ...[
                    const SizedBox(height: 10),
                    Text(
                      '同步已停用：不會自動同步，也無法手動同步。',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
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
            const SizedBox(height: 16),
            SectionCard(
              title: '分享新增單字',
              subtitle: '匯出 JSON，透過 Mail、AirDrop 或訊息傳給開發者',
              trailing: const Icon(Icons.ios_share, color: Color(0xFF0B6E99)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsInfoRow(
                    label: '使用者新增',
                    value: '${wordsNotifier.manualWordsCount} 筆',
                  ),
                  const SizedBox(height: 8),
                  _SettingsInfoRow(
                    label: '來源未知',
                    value: '${wordsNotifier.unknownWordsCount} 筆',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '分享內容只包含文字資料與時間，不包含圖片檔本體。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  if (!shareService.isSupported) ...[
                    const SizedBox(height: 10),
                    Text(
                      '目前平台不支援 JSON 檔案分享。',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Builder(
                    builder: (buttonContext) {
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              _isSharingDeveloperWords ||
                                  !shareService.isSupported ||
                                  !hasDeveloperShareCandidates
                              ? null
                              : () => _shareDeveloperWords(buttonContext),
                          icon: _isSharingDeveloperWords
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.file_upload_outlined),
                          label: Text(
                            _isSharingDeveloperWords ? '匯出中...' : '匯出 JSON 並分享',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
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
