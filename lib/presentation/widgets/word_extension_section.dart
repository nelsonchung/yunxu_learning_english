import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../../domain/models/word_extension.dart';
import '../../domain/services/word_extension_service.dart';
import '../state/words_notifier.dart';
import 'section_card.dart';

class WordExtensionSection extends StatefulWidget {
  const WordExtensionSection({super.key, required this.card});

  final WordCard card;

  @override
  State<WordExtensionSection> createState() => _WordExtensionSectionState();
}

class _WordExtensionSectionState extends State<WordExtensionSection> {
  Future<WordExtensionResult>? _result;
  final _addingWords = <String>{};

  @override
  void didUpdateWidget(covariant WordExtensionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.card;
    final card = widget.card;
    if (old.word != card.word ||
        old.meaning != card.meaning ||
        !listEquals(old.partsOfSpeech, card.partsOfSpeech) ||
        !listEquals(old.sentences, card.sentences)) {
      _result = null;
    }
  }

  void _load() {
    setState(() {
      _result = context.read<WordExtensionService>().recommend(widget.card);
    });
  }

  WordCard? _existing(WordsNotifier words, String word) {
    for (final card in words.words) {
      if (!card.isDeleted &&
          card.word.trim().toLowerCase() == word.trim().toLowerCase()) {
        return card;
      }
    }
    return null;
  }

  Future<void> _add(WordExtensionRecommendation recommendation) async {
    final entry = recommendation.entry;
    final key = entry.word.trim().toLowerCase();
    if (_addingWords.contains(key)) return;
    final words = context.read<WordsNotifier>();
    if (_existing(words, entry.word) != null) return;
    setState(() => _addingWords.add(key));
    try {
      await words.addWord(
        word: entry.word,
        meaning: entry.meaning,
        partsOfSpeech: entry.partsOfSpeech,
        sentences: recommendation.examples,
        memoryHint: entry.memoryHint,
        origin: WordOrigin.builtinWordBank,
        customTags: const ['延伸學習'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已將「${entry.word}」加入複習')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加入失敗，請稍後再試')));
    } finally {
      if (mounted) setState(() => _addingWords.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = context.watch<WordsNotifier>();
    return SectionCard(
      title: '延伸學習',
      subtitle: '依目前意思尋找字庫中的用法與相關字',
      child: ExpansionTile(
        key: ValueKey((
          widget.card.word,
          widget.card.meaning,
          widget.card.partsOfSpeech.join(','),
          widget.card.sentences.join('\n'),
        )),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text('探索用法與相關字'),
        onExpansionChanged: (expanded) {
          if (expanded && _result == null) _load();
        },
        children: [
          if (_result != null)
            FutureBuilder<WordExtensionResult>(
              future: _result,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 8),
                        Text('正在尋找延伸內容，首次載入可能需要一些時間…'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text('載入延伸內容失敗，請重試。'),
                      TextButton(onPressed: _load, child: const Text('重新載入')),
                    ],
                  );
                }
                final result = snapshot.data!;
                if (result.isEmpty) {
                  return const Text('目前沒有足夠的字庫或關係資料可推薦延伸內容。');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final usage in result.usages) ...[
                      _ExtensionBlock(
                        title: '用法例句',
                        explanation: '${usage.description}\n來源：${usage.source}',
                        example: usage.example,
                      ),
                      const Divider(height: 24),
                    ],
                    for (final item in result.related) ...[
                      _recommendation(item, words, allowAdd: true),
                      const Divider(height: 24),
                    ],
                    for (final item in result.confused) ...[
                      _recommendation(item, words, allowAdd: false),
                      const Divider(height: 24),
                    ],
                    if (result.related.isEmpty && result.confused.isEmpty)
                      const Text('目前沒有足夠資料推薦相關字或易混淆字。'),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _recommendation(
    WordExtensionRecommendation item,
    WordsNotifier words, {
    required bool allowAdd,
  }) {
    final entry = item.entry;
    final existing = _existing(words, entry.word);
    final adding = _addingWords.contains(entry.word.trim().toLowerCase());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExtensionBlock(
          title: '${allowAdd ? '相關字' : '容易混淆'}・${entry.word}',
          explanation:
              '${entry.partsOfSpeechLabel}｜${entry.meaning}\n${item.explanation}',
          example: item.comparisonExample.isEmpty
              ? item.examples.first
              : '${item.comparisonExample}\n\n${item.examples.first}',
        ),
        if (allowAdd) ...[
          const SizedBox(height: 12),
          if (existing != null)
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(
                context,
                '/detail',
                arguments: existing.id,
              ),
              icon: const Icon(Icons.check),
              label: Text('已加入・查看單字（${existing.reviewState.label}）'),
            )
          else
            FilledButton.icon(
              key: ValueKey('add-extension-${entry.word}'),
              onPressed: adding ? null : () => _add(item),
              icon: const Icon(Icons.add),
              label: Text(adding ? '加入中…' : '加入相關字到複習'),
            ),
        ],
      ],
    );
  }
}

class _ExtensionBlock extends StatelessWidget {
  const _ExtensionBlock({
    required this.title,
    required this.explanation,
    required this.example,
  });
  final String title;
  final String explanation;
  final String example;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(explanation),
          const SizedBox(height: 8),
          Text(example),
        ],
      ),
    );
  }
}
