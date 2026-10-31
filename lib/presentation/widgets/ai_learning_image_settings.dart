import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/learning_image.dart';
import '../../domain/models/ai_provider.dart';
import '../state/learning_image_notifier.dart';
import '../pages/learning_image_history_page.dart';
import 'section_card.dart';

class AiLearningImageSettings extends StatefulWidget {
  const AiLearningImageSettings({super.key});

  @override
  State<AiLearningImageSettings> createState() =>
      _AiLearningImageSettingsState();
}

class _AiLearningImageSettingsState extends State<AiLearningImageSettings> {
  final _key = TextEditingController();
  bool _visible = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _changeKey(LearningImageNotifier notifier, bool delete) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (delete) {
        await notifier.deleteApiKey();
      } else {
        await notifier.saveApiKey(_key.text.trim());
      }
      if (mounted) _key.clear();
    } catch (_) {
      if (mounted) setState(() => _error = '無法更新金鑰，請確認裝置安全儲存可用');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<LearningImageNotifier?>();
    if (notifier == null) return const SizedBox.shrink();
    return SectionCard(
      title: 'AI 學習圖卡',
      subtitle: '選擇 OpenAI 或 Claude，金鑰只保存在此裝置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<AiProvider>(
            key: ValueKey(notifier.provider),
            initialValue: notifier.provider,
            decoration: const InputDecoration(labelText: '例句與內容查證供應商'),
            items: AiProvider.values
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(provider.label),
                  ),
                )
                .toList(),
            onChanged: _saving || notifier.isBusy
                ? null
                : (provider) async {
                    if (provider == null) return;
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    try {
                      await notifier.setProvider(provider);
                      if (mounted) {
                        setState(() {
                          _key.clear();
                          _visible = false;
                        });
                      }
                    } catch (_) {
                      if (mounted) setState(() => _error = '無法切換 AI 供應商');
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text(notifier.hasKey ? 'API Key 已設定' : '尚未設定 API Key'),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            enabled: !_saving && !notifier.isBusy,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '${notifier.provider.label} API Key',
              hintText: notifier.hasKey ? '輸入新金鑰以替換' : '輸入 API Key',
              suffixIcon: IconButton(
                tooltip: _visible ? '隱藏金鑰' : '顯示金鑰',
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed:
                    _saving || notifier.isBusy || _key.text.trim().isEmpty
                    ? null
                    : () => _changeKey(notifier, false),
                child: const Text('儲存金鑰'),
              ),
              TextButton(
                onPressed: _saving || notifier.isBusy || !notifier.hasKey
                    ? null
                    : () => _changeKey(notifier, true),
                child: const Text('刪除金鑰'),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LearningImageMode>(
            key: ValueKey(notifier.mode),
            initialValue: notifier.mode,
            decoration: const InputDecoration(labelText: '生成模式'),
            items: LearningImageMode.values
                .map(
                  (mode) =>
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                )
                .toList(),
            onChanged: _saving || notifier.isBusy
                ? null
                : (mode) async {
                    if (mode == null) return;
                    try {
                      await notifier.setMode(mode);
                    } catch (_) {
                      if (mounted) setState(() => _error = '無法保存生成模式');
                    }
                  },
          ),
          const SizedBox(height: 12),
          const Text(
            'Claude 可生成例句與查證內容；圖片生成使用 OpenAI。選擇 Claude 時，需另切換至 OpenAI 儲存圖片用金鑰，再切回 Claude。',
          ),
          if (notifier.provider == AiProvider.claude)
            Text(
              notifier.hasOpenAiKey
                  ? '圖片用 OpenAI API Key 已設定'
                  : '圖片用 OpenAI API Key 尚未設定',
            ),
          const Text('Claude 費用目前標示為未知，請以 Anthropic 帳單為準。'),
          const SizedBox(height: 12),
          const Text('每次生成或重新生成都可能計費。取消或逾時的請求仍可能產生費用。金鑰不會隨 iCloud 同步。'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const LearningImageHistoryPage(),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('AI 費用紀錄'),
          ),
        ],
      ),
    );
  }
}

class AiLearningImageSettingsPage extends StatelessWidget {
  const AiLearningImageSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 學習圖卡設定')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: AiLearningImageSettings(),
    ),
  );
}
