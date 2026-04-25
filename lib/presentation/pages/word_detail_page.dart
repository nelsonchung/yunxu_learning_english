import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/services/pronunciation_service.dart';
import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/app_background.dart';
import '../widgets/date_utils.dart';
import '../widgets/image_preview.dart';
import '../widgets/section_card.dart';

class WordDetailPage extends StatelessWidget {
  const WordDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final id = args is WordCard ? args.id : args as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('單字詳情'),
        actions: [
          if (id != null)
            IconButton(
              onPressed: () {
                Navigator.pushNamed(context, '/edit', arguments: id);
              },
              icon: const Icon(Icons.edit_outlined),
              tooltip: '編輯單字',
            ),
          if (id != null)
            IconButton(
              onPressed: () async {
                final notifier = context.read<WordsNotifier>();
                final card = notifier.findById(id);
                if (card == null) {
                  return;
                }
                await notifier.deleteWord(card);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
              tooltip: '刪除單字',
            ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Consumer<WordsNotifier>(
            builder: (context, notifier, _) {
              final card = id == null ? null : notifier.findById(id);
              if (card == null) {
                return const Center(child: Text('找不到單字資料'));
              }
              final settings = context.watch<SettingsNotifier>();
              final showImages = settings.showImages;
              final meaning = card.meaning.trim();
              final meaningText = meaning.isEmpty ? '未填中文意義' : meaning;
              final memoryHint = card.memoryHint.trim();
              final canSpeak =
                  settings.pronunciationSupported &&
                  settings.pronunciationEnabled;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showImages) ...[
                            if ((card.imageBytes != null &&
                                    card.imageBytes!.isNotEmpty) ||
                                card.imagePath != null)
                              ImagePreview(
                                imageFile: null,
                                imagePath: card.imagePath,
                                imageBytes: card.imageBytes,
                                height: 220,
                              ),
                            if ((card.imageBytes != null &&
                                    card.imageBytes!.isNotEmpty) ||
                                card.imagePath != null)
                              const SizedBox(height: 16),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  card.word,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ),
                              IconButton(
                                onPressed: canSpeak
                                    ? () async {
                                        final ok = await context
                                            .read<PronunciationService>()
                                            .speak(card.word);
                                        if (!ok && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('發音失敗，請確認裝置語音可用'),
                                            ),
                                          );
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.volume_up_outlined),
                                tooltip: canSpeak ? '播放發音' : '請先到設定啟用發音',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                icon: Icons.calendar_today,
                                label: '建立日 ${formatDate(card.createdAt)}',
                              ),
                              _InfoChip(
                                icon: Icons.schedule,
                                label: card.isMastered
                                    ? '狀態 ${card.reviewState.label}'
                                    : card.hasCompletedReviewSchedule
                                    ? '狀態 已完成複習週期'
                                    : '下次複習 ${formatDate(card.nextReviewDate)}',
                              ),
                              _InfoChip(
                                icon: Icons.translate,
                                label:
                                    '${card.partOfSpeech.label} · $meaningText',
                              ),
                              if (card.isMastered)
                                _InfoChip(
                                  icon: Icons.school_outlined,
                                  label: card.masteredAt == null
                                      ? '已掌握'
                                      : '已掌握 ${formatDate(card.masteredAt!)}',
                                ),
                              if (!card.isMastered &&
                                  card.hasCompletedReviewSchedule)
                                const _InfoChip(
                                  icon: Icons.check_circle_outline,
                                  label: '已完成完整複習週期',
                                ),
                              if (card.needsCompletion)
                                _InfoChip(
                                  icon: Icons.edit_note,
                                  label:
                                      '待補：${card.missingFieldLabels.join('、')}',
                                ),
                            ],
                          ),
                          if (card.isMastered ||
                              !card.hasCompletedReviewSchedule) ...[
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    if (card.isMastered) {
                                      await notifier.resumeReview(card);
                                    } else {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('標記為已掌握'),
                                          content: Text(
                                            '「${card.word}」將提前結束複習，之後不再出現在今日複習。',
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
                                              child: const Text('確認'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) {
                                        return;
                                      }
                                      await notifier.markMastered(card);
                                    }
                                  } catch (error) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          card.isMastered
                                              ? '重新加入複習失敗，請稍後再試'
                                              : '標記已掌握失敗，請稍後再試',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  card.isMastered
                                      ? Icons.restart_alt
                                      : Icons.school_outlined,
                                ),
                                label: Text(
                                  card.isMastered ? '重新加入複習' : '標記已掌握',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (memoryHint.isNotEmpty) ...[
                    SectionCard(
                      title: '記憶聯想',
                      subtitle: '幫助你把單字和生活畫面連在一起',
                      child: Text(memoryHint),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SectionCard(
                    title: '標籤',
                    subtitle: '共 ${card.customTags.length} 個',
                    child: card.customTags.isEmpty
                        ? const Text('尚未設定標籤')
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: card.customTags
                                .map(
                                  (tag) => _InfoChip(
                                    icon: Icons.label_outline,
                                    label: tag,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '例句',
                    subtitle: '共 ${card.sentences.length} 句',
                    child: card.sentences.isEmpty
                        ? const Text('尚未填寫例句')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: card.sentences
                                .map(
                                  (sentence) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _SentenceRow(
                                      sentence: sentence,
                                      canSpeak: canSpeak,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: '複習紀錄',
                    subtitle: '完成 ${card.history.length} 次',
                    child: card.history.isEmpty
                        ? const Text('尚未完成任何複習')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: card.history
                                .map((date) => Text('• ${formatDate(date)}'))
                                .toList(),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 16, color: const Color(0xFF0B6E99)),
            ),
            const TextSpan(text: ' '),
            TextSpan(text: label),
          ],
        ),
        softWrap: true,
      ),
    );
  }
}

class _SentenceRow extends StatelessWidget {
  const _SentenceRow({required this.sentence, required this.canSpeak});

  final String sentence;
  final bool canSpeak;

  @override
  Widget build(BuildContext context) {
    final pronunciationService = context.read<PronunciationService>();
    final speakableText = pronunciationService.extractEnglishUtterance(
      sentence,
    );
    final canSpeakSentence = canSpeak && speakableText != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('• $sentence'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: canSpeakSentence
              ? () async {
                  final ok = await pronunciationService.speak(speakableText);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('例句發音失敗，請確認裝置語音可用')),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.volume_up_outlined),
          tooltip: canSpeakSentence ? '播放例句發音' : '此句目前沒有可朗讀的英文內容',
        ),
      ],
    );
  }
}
