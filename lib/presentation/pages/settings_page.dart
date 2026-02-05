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
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      await notifier.setReminderTime(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;
        const syncIntervals = [5, 10, 20, 30, 60];

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
              trailing: const Icon(Icons.notifications_active_outlined,
                  color: Color(0xFF0B6E99)),
              child: Row(
                children: [
                  Text('目前：${notifier.reminderTime.format(context)}'),
                  const Spacer(),
                  OutlinedButton(
                    onPressed:
                        notifier.reminderEnabled ? () => _pickTime(context) : null,
                    child: const Text('設定時間'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '圖片欄位顯示',
              subtitle: '控制新增/編輯頁是否顯示圖片欄位',
              trailing: const Icon(Icons.image_outlined,
                  color: Color(0xFF0B6E99)),
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
                            child: Text('$seconds 秒'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) {
                        return;
                      }
                      await notifier.setSyncIntervalSeconds(value);
                      if (context.mounted) {
                        context
                            .read<WordsNotifier>()
                            .setSyncIntervalSeconds(value);
                      }
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
