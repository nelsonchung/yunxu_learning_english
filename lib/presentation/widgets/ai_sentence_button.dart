import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/sentence_level.dart';
import '../../domain/models/word_card.dart';
import '../state/learning_image_notifier.dart';
import '../state/words_notifier.dart';
import 'ai_learning_image_settings.dart';

class AiSentenceButton extends StatelessWidget {
  const AiSentenceButton({super.key, required this.card});
  final WordCard card;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.auto_awesome),
    label: const Text('AI 生成例句'),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _SentenceDialog(card: card),
    ),
  );
}

class _SentenceDialog extends StatefulWidget {
  const _SentenceDialog({required this.card});
  final WordCard card;

  @override
  State<_SentenceDialog> createState() => _SentenceDialogState();
}

class _SentenceDialogState extends State<_SentenceDialog> {
  SentenceLevel? _level;
  List<String>? _sentences;
  bool _busy = false;
  bool _saving = false;
  String? _error;

  Future<void> _generate(LearningImageNotifier ai) async {
    if (_busy || _saving || ai.isBusy || _level == null) return;
    final source = widget.card.copyWith(
      sentences: [...?_sentences, ...widget.card.sentences],
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ai.generateSentences(source, _level!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sentences = result ?? _sentences;
      _error = result == null ? ai.error ?? 'AI 正忙碌，請稍後再試。' : null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<WordsNotifier>().appendGeneratedSentences(
        widget.card,
        _sentences!,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '無法新增例句，單字可能已變更或儲存失敗，請重試。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<LearningImageNotifier?>();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('${widget.card.word}：AI 生成例句'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('選擇學習程度'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: SentenceLevel.values
                      .map(
                        (level) => ChoiceChip(
                          label: Text(level.label),
                          selected: _level == level,
                          onSelected: _busy || _saving
                              ? null
                              : (_) => setState(() {
                                  _level = level;
                                  _sentences = null;
                                  _error = null;
                                }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                const Text(
                  '生成 3 句英文例句及繁中翻譯，預覽後可新增至此單字。使用已設定的 API Key，費用依 API 用量計算。',
                ),
                if (ai == null) const Text('AI 服務目前無法使用。'),
                if (ai != null)
                  TextButton(
                    onPressed: _busy || _saving
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const AiLearningImageSettingsPage(),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                    child: const Text('設定 API Key'),
                  ),
                if (ai != null && ai.isBusy && !_busy)
                  const Text('AI 正忙碌，請等待目前工作完成。'),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const Text('正在生成例句…'),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_sentences != null) ...[
                  const SizedBox(height: 12),
                  for (final sentence in _sentences!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(sentence),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (_sentences == null)
            FilledButton(
              onPressed: _level == null || _busy || ai == null || ai.isBusy
                  ? null
                  : () => _generate(ai),
              child: const Text('生成例句'),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _busy || _saving || ai == null || ai.isBusy
                  ? null
                  : () => _generate(ai),
              icon: const Icon(Icons.refresh),
              label: const Text('重新生成'),
            ),
            FilledButton(
              onPressed: _busy || _saving ? null : _save,
              child: Text(_saving ? '儲存中…' : '新增至例句'),
            ),
          ],
        ],
      ),
    );
  }
}
