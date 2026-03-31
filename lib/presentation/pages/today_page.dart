import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/builtin_word_bank_repository.dart';
import '../../domain/models/builtin_word_entry.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/daily_word_recommendation_service.dart';
import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/date_utils.dart';
import '../widgets/section_card.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final dueList = notifier.dueToday();
        final showImages = context.watch<SettingsNotifier>().showImages;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            _HeroHeader(total: dueList.length),
            const SizedBox(height: 16),
            _DailyNewWordsSection(dueCount: dueList.length),
            const SizedBox(height: 16),
            if (dueList.isEmpty)
              const _EmptyState()
            else
              ...dueList.map(
                (card) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ReviewCard(
                    card: card,
                    onReview: () async {
                      try {
                        await notifier.markReviewed(card);
                        imageCache.clear();
                        imageCache.clearLiveImages();
                      } catch (error, stackTrace) {
                        debugPrint('markReviewed failed: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('完成複習失敗，請稍後再試')),
                        );
                      }
                    },
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/detail',
                      arguments: card.id,
                    ),
                    showImage: showImages,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B6E99), Color(0xFF1CA7A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日複習',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  total.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '依照遺忘曲線安排的複習卡片',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: const [
                    _Pill(text: '1'),
                    _Pill(text: '2'),
                    _Pill(text: '3'),
                    _Pill(text: '5'),
                    _Pill(text: '8'),
                    _Pill(text: '13'),
                    _Pill(text: '21'),
                    _Pill(text: '39'),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.auto_graph, color: Colors.white70, size: 42),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0B6E99).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF0B6E99)),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('今天沒有需要複習的單字，做得很好！')),
        ],
      ),
    );
  }
}

class _DailyNewWordsSection extends StatefulWidget {
  const _DailyNewWordsSection({required this.dueCount});

  final int dueCount;

  @override
  State<_DailyNewWordsSection> createState() => _DailyNewWordsSectionState();
}

class _DailyNewWordsSectionState extends State<_DailyNewWordsSection> {
  final Set<String> _addingWords = <String>{};
  final Set<String> _dismissedWords = <String>{};

  List<BuiltinWordEntry> _entries = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = await context
          .read<BuiltinWordBankRepository>()
          .fetchAll();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '無法載入推薦字庫：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> _sentencesForAdd(BuiltinWordEntry entry) {
    final cleaned = entry.sentences
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList(growable: true);
    if (cleaned.length < 2) {
      cleaned.add('I added "${entry.word}" to my review list today.');
    }
    if (cleaned.length < 2) {
      cleaned.add('I will review "${entry.word}" again tonight.');
    }
    return cleaned;
  }

  String _normalizeWord(String word) {
    return word.trim().toLowerCase();
  }

  List<BuiltinWordEntry> _recommendationsFor({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
    Set<String>? excludedWords,
  }) {
    return context.read<DailyWordRecommendationService>().recommend(
      entries: _entries,
      existingWords: wordsNotifier.words,
      settings: settingsNotifier.settings,
      dueTodayCount: widget.dueCount,
      now: DateTime.now(),
      excludedWords: excludedWords ?? _dismissedWords,
    );
  }

  void _restoreDismissedWords(Iterable<String> keys) {
    if (!mounted) {
      return;
    }
    setState(() {
      _dismissedWords.removeAll(keys);
    });
  }

  void _dismissEntry(
    BuiltinWordEntry entry, {
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
  }) {
    final key = _normalizeWord(entry.word);
    if (_dismissedWords.contains(key) || _addingWords.contains(key)) {
      return;
    }

    final currentRecommendations = _recommendationsFor(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
    );
    final nextDismissed = <String>{..._dismissedWords, key};
    final nextRecommendations = _recommendationsFor(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
      excludedWords: nextDismissed,
    );
    final hasReplacement =
        nextRecommendations.length >= currentRecommendations.length;

    setState(() {
      _dismissedWords.add(key);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasReplacement
              ? '已略過「${entry.word}」，幫你換一個'
              : '已略過「${entry.word}」，目前沒有更多推薦字',
        ),
        action: SnackBarAction(
          label: '復原',
          onPressed: () => _restoreDismissedWords([key]),
        ),
      ),
    );
  }

  void _dismissBatch(
    List<BuiltinWordEntry> recommendations, {
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
  }) {
    final keys = recommendations
        .map((entry) => _normalizeWord(entry.word))
        .where((key) => !_dismissedWords.contains(key))
        .toList(growable: false);
    if (keys.isEmpty) {
      return;
    }

    final nextDismissed = <String>{..._dismissedWords, ...keys};
    final nextRecommendations = _recommendationsFor(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
      excludedWords: nextDismissed,
    );

    setState(() {
      _dismissedWords.addAll(keys);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextRecommendations.isNotEmpty ? '已換一批推薦字' : '這批先略過了，目前沒有更多推薦字',
        ),
        action: SnackBarAction(
          label: '復原',
          onPressed: () => _restoreDismissedWords(keys),
        ),
      ),
    );
  }

  Future<void> _addEntry(BuiltinWordEntry entry) async {
    final key = _normalizeWord(entry.word);
    final notifier = context.read<WordsNotifier>();
    final exists = notifier.words.any((item) => item.word.toLowerCase() == key);
    if (exists || _addingWords.contains(key)) {
      return;
    }

    setState(() {
      _addingWords.add(key);
    });

    try {
      await notifier.addWord(
        word: entry.word,
        meaning: entry.meaning,
        partOfSpeech: entry.partOfSpeech,
        sentences: _sentencesForAdd(entry),
        origin: WordOrigin.builtinWordBank,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已加入「${entry.word}」到複習資料庫')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入失敗：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _addingWords.remove(key);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsNotifier, WordsNotifier>(
      builder: (context, settingsNotifier, wordsNotifier, _) {
        if (!settingsNotifier.dailyNewWordsEnabled) {
          return const SizedBox.shrink();
        }

        if (_isLoading) {
          return const SectionCard(
            title: '今日補新字',
            subtitle: '正在整理今天適合加入複習的新字',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (_errorMessage != null) {
          return SectionCard(
            title: '今日補新字',
            subtitle: '目前無法準備推薦清單',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_errorMessage!),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _loadEntries,
                  child: const Text('重新載入'),
                ),
              ],
            ),
          );
        }

        final threshold = settingsNotifier.dailyNewWordsReviewThreshold;
        final desiredCount = settingsNotifier.dailyNewWordsCount;

        if (widget.dueCount > threshold) {
          return SectionCard(
            title: '今日補新字',
            subtitle: '今天待複習 ${widget.dueCount} 個，超過你設定的 $threshold 個',
            child: const Text('今天先專心複習，等待補量降下來後再補新字。'),
          );
        }

        final recommendations = _recommendationsFor(
          settingsNotifier: settingsNotifier,
          wordsNotifier: wordsNotifier,
        );
        if (recommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        final existingWords = wordsNotifier.words
            .map((item) => item.word.toLowerCase())
            .toSet();

        return SectionCard(
          title: '今日補新字',
          subtitle:
              '今天待複習 ${widget.dueCount} 個，幫你挑了 ${recommendations.length}/$desiredCount 個適合的新字',
          trailing: TextButton.icon(
            onPressed: recommendations.isEmpty
                ? null
                : () => _dismissBatch(
                    recommendations,
                    settingsNotifier: settingsNotifier,
                    wordsNotifier: wordsNotifier,
                  ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('換一批'),
          ),
          child: Column(
            children: recommendations
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RecommendedWordTile(
                      entry: entry,
                      isAdded: existingWords.contains(entry.word.toLowerCase()),
                      isAdding: _addingWords.contains(entry.word.toLowerCase()),
                      onDismiss: () => _dismissEntry(
                        entry,
                        settingsNotifier: settingsNotifier,
                        wordsNotifier: wordsNotifier,
                      ),
                      onAdd: () => _addEntry(entry),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }
}

class _RecommendedWordTile extends StatelessWidget {
  const _RecommendedWordTile({
    required this.entry,
    required this.isAdded,
    required this.isAdding,
    required this.onDismiss,
    required this.onAdd,
  });

  final BuiltinWordEntry entry;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onDismiss;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      ...entry.audienceLabels.take(2),
      if (entry.difficultyLevel != null) '難度 ${entry.difficultyLevel}',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E8ED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.word,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${entry.meaning} · ${entry.partOfSpeech.label}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.black87),
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: badges
                        .map(
                          (badge) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0B6E99,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF0B6E99),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  entry.sentences.first.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.black87),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: (isAdded || isAdding) ? null : onDismiss,
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('換一個'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: isAdded ? '已在複習庫' : '加入複習庫',
            onPressed: (isAdded || isAdding) ? null : onAdd,
            icon: isAdding
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isAdded ? Icons.check_circle : Icons.add_circle_outline,
                    color: isAdded
                        ? const Color(0xFF1CA7A6)
                        : const Color(0xFF0B6E99),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.card,
    required this.onReview,
    required this.onTap,
    required this.showImage,
  });

  final WordCard card;
  final Future<void> Function() onReview;
  final VoidCallback onTap;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final firstSentence = card.sentences.firstWhere(
      (sentence) => sentence.trim().isNotEmpty,
      orElse: () => '',
    );
    final meaning = card.meaning.trim();
    final meaningText = meaning.isEmpty ? '未填中文意義' : meaning;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showImage) ...[
                      _Thumb(card: card),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.word,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            firstSentence.isNotEmpty ? firstSentence : '尚未填寫例句',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$meaningText · ${card.partOfSpeech.label}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                          if (card.needsCompletion) ...[
                            const SizedBox(height: 6),
                            Text(
                              '待補：${card.missingFieldLabels.join('、')}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF8C4A06)),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 16),
                              const SizedBox(width: 4),
                              Text('下次：${formatDate(card.nextReviewDate)}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(onPressed: onTap, child: const Text('查看詳情')),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => unawaited(onReview()),
                      child: const Text('完成複習'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheExtent = (70 * dpr).round();

    if (card.imageBytes != null && card.imageBytes!.isNotEmpty) {
      final bytes = card.imageBytes!;
      final typedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          typedBytes,
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          cacheWidth: cacheExtent,
          cacheHeight: cacheExtent,
        ),
      );
    }

    if (card.imagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(card.imagePath!),
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          cacheWidth: cacheExtent,
          cacheHeight: cacheExtent,
        ),
      );
    }

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.book, color: Color(0xFF0B6E99)),
    );
  }
}
