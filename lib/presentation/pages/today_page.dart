import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const int _quickReviewCount = 3;
  static const int _reviewBatchSize = 5;
  static const int _comebackThreshold = 12;
  static const int _comebackDailyLimit = 8;

  int _reviewTarget = _quickReviewCount;
  DateTime? _sessionDay;
  List<String>? _difficultPracticeWordIds;
  final Set<String> _submittingWordIds = <String>{};

  void _resetSessionForNewDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_sessionDay == today) {
      return;
    }
    _sessionDay = today;
    _reviewTarget = _quickReviewCount;
    _difficultPracticeWordIds = null;
  }

  void _startDifficultPractice(List<WordCard> queue, int requestedCount) {
    setState(() {
      _difficultPracticeWordIds = queue
          .take(requestedCount)
          .map((card) => card.id)
          .toList(growable: false);
    });
  }

  void _finishDifficultPractice() {
    setState(() {
      _difficultPracticeWordIds = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final now = DateTime.now();
        _resetSessionForNewDay(now);
        final dueList = notifier.dueOnOrBefore(now);
        final reviewQueue = notifier.reviewQueueFor(now);
        final difficultPracticeQueue = notifier.difficultPracticeQueueFor(now);
        final difficultPracticeQueueIds = difficultPracticeQueue
            .map((card) => card.id)
            .toSet();
        final difficultPracticeWordIds = _difficultPracticeWordIds;
        final isDifficultPractice = difficultPracticeWordIds != null;
        final difficultPracticeReviews = isDifficultPractice
            ? difficultPracticeWordIds
                  .map(notifier.findById)
                  .whereType<WordCard>()
                  .where((card) => difficultPracticeQueueIds.contains(card.id))
                  .toList(growable: false)
            : const <WordCard>[];
        final handledToday = notifier.handledReviewCountOn(now);
        final availableToday = handledToday + reviewQueue.length;
        final isComebackMode = availableToday > _comebackThreshold;
        final dailyLimit = isComebackMode
            ? math.min(_comebackDailyLimit, availableToday)
            : availableToday;
        final effectiveTarget = math.min(_reviewTarget, availableToday);
        final visibleCount = math.max(0, effectiveTarget - handledToday);
        final visibleReviews = isDifficultPractice
            ? difficultPracticeReviews
            : reviewQueue.take(visibleCount).toList(growable: false);
        final quickGoal = math.min(_quickReviewCount, dailyLimit);
        final quickGoalComplete = quickGoal > 0 && handledToday >= quickGoal;
        final dailyGoalComplete = dailyLimit > 0 && handledToday >= dailyLimit;
        final canContinue =
            quickGoalComplete &&
            reviewQueue.isNotEmpty &&
            visibleReviews.isEmpty;
        final showImages = context.watch<SettingsNotifier>().showImages;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            _HeroHeader(
              total: isDifficultPractice
                  ? difficultPracticeReviews.length
                  : reviewQueue.length,
            ),
            const SizedBox(height: 16),
            if (isDifficultPractice) ...[
              _DifficultPracticeSessionCard(
                total: difficultPracticeWordIds.length,
                remaining: difficultPracticeReviews.length,
                onExit: _finishDifficultPractice,
              ),
              const SizedBox(height: 16),
            ] else ...[
              if (notifier.difficultWordsCount > 0) ...[
                _DifficultPracticeEntryCard(
                  total: notifier.difficultWordsCount,
                  availableToday: difficultPracticeQueue.length,
                  onQuickStart: difficultPracticeQueue.isEmpty
                      ? null
                      : () => _startDifficultPractice(
                          difficultPracticeQueue,
                          _quickReviewCount,
                        ),
                  onFiveStart: difficultPracticeQueue.isEmpty
                      ? null
                      : () => _startDifficultPractice(
                          difficultPracticeQueue,
                          _reviewBatchSize,
                        ),
                ),
                const SizedBox(height: 16),
              ],
              _DailyNewWordsSection(dueCount: reviewQueue.length),
              const SizedBox(height: 16),
            ],
            if (!isDifficultPractice && isComebackMode) ...[
              _ComebackNotice(total: availableToday, dailyLimit: dailyLimit),
              const SizedBox(height: 16),
            ],
            if (isDifficultPractice && visibleReviews.isEmpty)
              _DifficultPracticeCompleteCard(onDone: _finishDifficultPractice)
            else if (!isDifficultPractice && availableToday == 0)
              const _EmptyState()
            else ...[
              if (!isDifficultPractice && !quickGoalComplete) ...[
                _QuickStartNotice(count: math.max(0, quickGoal - handledToday)),
                const SizedBox(height: 16),
              ],
              if (!isDifficultPractice && quickGoalComplete) ...[
                _QuickGoalCompleteCard(
                  handledToday: handledToday,
                  remainingToday: math.max(0, dailyLimit - handledToday),
                  remainingBacklog: reviewQueue.length,
                  suggestedGoal: dailyLimit,
                  dailyGoalComplete: dailyGoalComplete,
                  isComebackMode: isComebackMode,
                  continueCount: math.min(_reviewBatchSize, reviewQueue.length),
                  onContinue: canContinue
                      ? () {
                          setState(() {
                            _reviewTarget = math.min(
                              availableToday,
                              math.max(_reviewTarget, handledToday) +
                                  _reviewBatchSize,
                            );
                          });
                        }
                      : null,
                ),
                if (visibleReviews.isNotEmpty) const SizedBox(height: 16),
              ],
              ...visibleReviews.map(
                (card) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ReviewCard(
                    card: card,
                    isSubmitting: _submittingWordIds.contains(card.id),
                    onReview: (rating) async {
                      if (_submittingWordIds.contains(card.id)) {
                        return;
                      }
                      setState(() {
                        _submittingWordIds.add(card.id);
                      });
                      try {
                        await notifier.markReviewed(card, rating: rating);
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
                      } finally {
                        if (mounted) {
                          setState(() {
                            _submittingWordIds.remove(card.id);
                          });
                        } else {
                          _submittingWordIds.remove(card.id);
                        }
                      }
                    },
                    onMarkMastered: () async {
                      if (_submittingWordIds.contains(card.id)) {
                        return;
                      }
                      setState(() {
                        _submittingWordIds.add(card.id);
                      });
                      try {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('標記為已掌握'),
                            content: Text('「${card.word}」將提前結束複習，之後不再出現在今日複習。'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('確認'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) {
                          return;
                        }
                        await notifier.markMastered(card);
                      } catch (error, stackTrace) {
                        debugPrint('markMastered failed: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('標記已掌握失敗，請稍後再試')),
                        );
                      } finally {
                        if (mounted) {
                          setState(() {
                            _submittingWordIds.remove(card.id);
                          });
                        } else {
                          _submittingWordIds.remove(card.id);
                        }
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
              if (!isDifficultPractice && dueList.isEmpty) const _EmptyState(),
            ],
          ],
        );
      },
    );
  }
}

class _DifficultPracticeEntryCard extends StatelessWidget {
  const _DifficultPracticeEntryCard({
    required this.total,
    required this.availableToday,
    this.onQuickStart,
    this.onFiveStart,
  });

  final int total;
  final int availableToday;
  final VoidCallback? onQuickStart;
  final VoidCallback? onFiveStart;

  @override
  Widget build(BuildContext context) {
    final subtitle = availableToday == 0
        ? '今天已練過需要加強的單字，明天再繼續'
        : '有 $total 個單字需要加強，先從最近卡住的開始';
    return SectionCard(
      title: '困難單字專項練習',
      subtitle: subtitle,
      trailing: const Icon(
        Icons.fitness_center_outlined,
        color: Color(0xFFB85C38),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onQuickStart,
              icon: const Icon(Icons.timer_outlined),
              label: Text(
                '2 分鐘（${math.min(_TodayPageState._quickReviewCount, availableToday)} 個）',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onFiveStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                '練 ${math.min(_TodayPageState._reviewBatchSize, availableToday)} 個',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DifficultPracticeSessionCard extends StatelessWidget {
  const _DifficultPracticeSessionCard({
    required this.total,
    required this.remaining,
    required this.onExit,
  });

  final int total;
  final int remaining;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final completed = total - remaining;
    return SectionCard(
      title: '正在加強困難單字',
      subtitle: '已完成 $completed／$total 個；答對後會依記憶狀態逐步退出困難清單',
      trailing: IconButton(
        tooltip: '結束專項練習',
        onPressed: onExit,
        icon: const Icon(Icons.close),
      ),
      child: LinearProgressIndicator(
        value: total == 0 ? 1 : completed / total,
        minHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _DifficultPracticeCompleteCard extends StatelessWidget {
  const _DifficultPracticeCompleteCard({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '專項練習完成',
      subtitle: '這一輪需要加強的單字都處理完了',
      trailing: const Icon(Icons.verified_outlined, color: Color(0xFF0B6E99)),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onDone,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('回到今日複習'),
        ),
      ),
    );
  }
}

class _QuickStartNotice extends StatelessWidget {
  const _QuickStartNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '先完成兩分鐘任務',
      subtitle: '今天只要先接觸幾個單字，就算成功開始',
      trailing: const Icon(Icons.timer_outlined, color: Color(0xFF0B6E99)),
      child: Text('再複習 $count 個，就完成今天的最低任務。'),
    );
  }
}

class _ComebackNotice extends StatelessWidget {
  const _ComebackNotice({required this.total, required this.dailyLimit});

  final int total;
  final int dailyLimit;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '歡迎回來',
      subtitle: '待複習內容較多，先從最需要加強的單字開始',
      trailing: const Icon(
        Icons.waving_hand_outlined,
        color: Color(0xFF0B6E99),
      ),
      child: Text('目前有 $total 個待處理項目，今天先安排 $dailyLimit 個。完成後可以放心休息，也可以選擇繼續學習。'),
    );
  }
}

class _QuickGoalCompleteCard extends StatelessWidget {
  const _QuickGoalCompleteCard({
    required this.handledToday,
    required this.remainingToday,
    required this.remainingBacklog,
    required this.suggestedGoal,
    required this.dailyGoalComplete,
    required this.isComebackMode,
    required this.continueCount,
    this.onContinue,
  });

  final int handledToday;
  final int remainingToday;
  final int remainingBacklog;
  final int suggestedGoal;
  final bool dailyGoalComplete;
  final bool isComebackMode;
  final int continueCount;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final reachedSuggestedStop =
        dailyGoalComplete && isComebackMode && remainingBacklog > 0;
    final title = reachedSuggestedStop
        ? '今天的建議任務完成了'
        : dailyGoalComplete
        ? '今天的任務完成了'
        : '兩分鐘任務完成';
    final message = dailyGoalComplete && isComebackMode && remainingBacklog > 0
        ? '今天建議的 $suggestedGoal 個已完成，目前累積完成 $handledToday 個。可以放心休息；如果還有時間，也可以繼續。'
        : dailyGoalComplete
        ? '今天已完成 $handledToday 個複習，做得很好！'
        : '最低任務已完成。還有 $remainingToday 個今天可以繼續處理。';

    return SectionCard(
      title: title,
      subtitle: message,
      trailing: const Icon(
        Icons.celebration_outlined,
        color: Color(0xFF0B6E99),
      ),
      child: onContinue == null
          ? const Text('休息也算完成；想多學一點時再回來。')
          : SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  reachedSuggestedStop
                      ? '我還有時間，再複習 $continueCount 個'
                      : '再複習 $continueCount 個',
                ),
              ),
            ),
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
            color: Colors.black.withValues(alpha: 0.08),
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
        color: Colors.white.withValues(alpha: 0.2),
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
            color: Colors.black.withValues(alpha: 0.05),
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
              color: const Color(0xFF0B6E99).withValues(alpha: 0.15),
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
  static const Duration _addFeedbackDuration = Duration(seconds: 2);
  static const Duration _dismissFeedbackDuration = Duration(seconds: 2);

  final Set<String> _addingWords = <String>{};
  final Set<String> _dismissedWords = <String>{};

  SettingsNotifier? _settingsNotifier;
  WordsNotifier? _wordsNotifier;
  List<BuiltinWordEntry> _entries = const [];
  List<BuiltinWordEntry> _recommendations = const [];
  String? _errorMessage;
  String? _loadedCandidateCacheKey;
  String? _recommendationCacheKey;
  int _recommendationBatchIndex = 0;
  int _loadRequestVersion = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSettingsNotifier = context.read<SettingsNotifier>();
    final nextWordsNotifier = context.read<WordsNotifier>();

    if (!identical(_settingsNotifier, nextSettingsNotifier)) {
      _settingsNotifier?.removeListener(_handleDependenciesChanged);
      _settingsNotifier = nextSettingsNotifier;
      _settingsNotifier?.addListener(_handleDependenciesChanged);
    }
    if (!identical(_wordsNotifier, nextWordsNotifier)) {
      _wordsNotifier?.removeListener(_handleDependenciesChanged);
      _wordsNotifier = nextWordsNotifier;
      _wordsNotifier?.addListener(_handleDependenciesChanged);
    }

    _handleDependenciesChanged();
  }

  @override
  void didUpdateWidget(covariant _DailyNewWordsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dueCount != widget.dueCount) {
      _handleDependenciesChanged();
    }
  }

  @override
  void dispose() {
    _settingsNotifier?.removeListener(_handleDependenciesChanged);
    _wordsNotifier?.removeListener(_handleDependenciesChanged);
    super.dispose();
  }

  void _handleDependenciesChanged() {
    final settingsNotifier = _settingsNotifier;
    final wordsNotifier = _wordsNotifier;
    if (settingsNotifier == null || wordsNotifier == null) {
      return;
    }

    if (!_shouldPrepareRecommendations(settingsNotifier)) {
      final requestVersion = ++_loadRequestVersion;
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _recommendations = const [];
        _recommendationCacheKey = null;
        _recommendationBatchIndex = 0;
      });
      if (requestVersion != _loadRequestVersion) {
        return;
      }
      return;
    }

    final candidateCacheKey = _buildCandidateCacheKey(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
    );
    if (_loadedCandidateCacheKey == candidateCacheKey) {
      _refreshRecommendations(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
      );
      return;
    }

    unawaited(
      _loadRecommendationCandidates(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
        candidateCacheKey: candidateCacheKey,
      ),
    );
  }

  bool _shouldPrepareRecommendations(SettingsNotifier settingsNotifier) {
    return settingsNotifier.dailyNewWordsEnabled &&
        widget.dueCount <= settingsNotifier.dailyNewWordsReviewThreshold;
  }

  Future<void> _loadRecommendationCandidates({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
    required String candidateCacheKey,
  }) async {
    final requestVersion = ++_loadRequestVersion;

    if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final entries = await context
          .read<BuiltinWordBankRepository>()
          .fetchRecommendationCandidates(
            existingWords: wordsNotifier.words,
            now: DateTime.now(),
            desiredCount: settingsNotifier.dailyNewWordsCount,
          );

      if (!mounted || requestVersion != _loadRequestVersion) {
        return;
      }

      final recommendations = _buildRecommendations(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
        entries: entries,
        batchIndex: 0,
      );
      setState(() {
        _entries = entries;
        _recommendations = recommendations;
        _loadedCandidateCacheKey = candidateCacheKey;
        _recommendationBatchIndex = 0;
        _recommendationCacheKey = _buildRecommendationCacheKey(
          settingsNotifier: settingsNotifier,
          wordsNotifier: wordsNotifier,
          batchIndex: 0,
        );
      });
    } catch (error) {
      if (!mounted || requestVersion != _loadRequestVersion) {
        return;
      }
      setState(() {
        _errorMessage = '無法載入推薦字庫：$error';
      });
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

  String _buildCandidateCacheKey({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
  }) {
    return [
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      settingsNotifier.dailyNewWordsCount,
      _hashWords(wordsNotifier.words),
    ].join(':');
  }

  String _buildRecommendationCacheKey({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
    int? batchIndex,
  }) {
    return [
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      widget.dueCount,
      settingsNotifier.dailyNewWordsEnabled,
      settingsNotifier.dailyNewWordsCount,
      settingsNotifier.dailyNewWordsReviewThreshold,
      _hashWords(wordsNotifier.words),
      _hashKeys(_dismissedWords),
      batchIndex ?? _recommendationBatchIndex,
    ].join(':');
  }

  int _hashWords(List<WordCard> words) {
    var hash = 0;
    for (final word in words) {
      hash = _combineHash(hash, _normalizeWord(word.word));
      hash = _combineHash(
        hash,
        word.createdAt.millisecondsSinceEpoch.toString(),
      );
    }
    return hash;
  }

  int _hashKeys(Iterable<String> keys) {
    final sortedKeys = keys.toList(growable: false)..sort();
    var hash = 0;
    for (final key in sortedKeys) {
      hash = _combineHash(hash, key);
    }
    return hash;
  }

  int _combineHash(int seed, String value) {
    var hash = seed;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  List<BuiltinWordEntry> _buildRecommendations({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
    List<BuiltinWordEntry>? entries,
    Set<String>? excludedWords,
    int? batchIndex,
  }) {
    return context.read<DailyWordRecommendationService>().recommend(
      entries: entries ?? _entries,
      existingWords: wordsNotifier.words,
      settings: settingsNotifier.settings,
      dueTodayCount: widget.dueCount,
      now: DateTime.now(),
      excludedWords: excludedWords ?? _dismissedWords,
      batchIndex: batchIndex ?? _recommendationBatchIndex,
    );
  }

  void _refreshRecommendations({
    required SettingsNotifier settingsNotifier,
    required WordsNotifier wordsNotifier,
  }) {
    final nextCacheKey = _buildRecommendationCacheKey(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
    );
    if (nextCacheKey == _recommendationCacheKey) {
      return;
    }

    final recommendations = _buildRecommendations(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _recommendations = recommendations;
      _recommendationCacheKey = nextCacheKey;
    });
  }

  void _restoreDismissedWords(Iterable<String> keys) {
    final settingsNotifier = _settingsNotifier;
    final wordsNotifier = _wordsNotifier;
    if (!mounted || settingsNotifier == null || wordsNotifier == null) {
      return;
    }

    final nextDismissed = <String>{..._dismissedWords}..removeAll(keys);
    final nextRecommendations = _buildRecommendations(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
      excludedWords: nextDismissed,
    );

    setState(() {
      _dismissedWords.removeAll(keys);
      _recommendations = nextRecommendations;
      _recommendationCacheKey = _buildRecommendationCacheKey(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
      );
    });
  }

  void _showDismissFeedback(SnackBar snackBar) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      snackBar,
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  }

  void _showAddFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: _addFeedbackDuration,
        persist: false,
        content: Text(message),
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
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

    final currentRecommendations = _recommendations;
    final nextDismissed = <String>{..._dismissedWords, key};
    final nextRecommendations = _buildRecommendations(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
      excludedWords: nextDismissed,
    );
    final hasReplacement =
        nextRecommendations.length >= currentRecommendations.length;

    setState(() {
      _dismissedWords.add(key);
      _recommendations = nextRecommendations;
      _recommendationCacheKey = _buildRecommendationCacheKey(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
      );
    });

    _showDismissFeedback(
      SnackBar(
        duration: _dismissFeedbackDuration,
        persist: false,
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
    final nextBatchIndex = _recommendationBatchIndex + 1;
    final nextRecommendations = _buildRecommendations(
      settingsNotifier: settingsNotifier,
      wordsNotifier: wordsNotifier,
      excludedWords: nextDismissed,
      batchIndex: nextBatchIndex,
    );

    setState(() {
      _dismissedWords.addAll(keys);
      _recommendationBatchIndex = nextBatchIndex;
      _recommendations = nextRecommendations;
      _recommendationCacheKey = _buildRecommendationCacheKey(
        settingsNotifier: settingsNotifier,
        wordsNotifier: wordsNotifier,
      );
    });

    _showDismissFeedback(
      SnackBar(
        duration: _dismissFeedbackDuration,
        persist: false,
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
        memoryHint: entry.memoryHint,
        partOfSpeech: entry.partOfSpeech,
        sentences: _sentencesForAdd(entry),
        origin: WordOrigin.builtinWordBank,
      );
      if (!mounted) {
        return;
      }
      _showAddFeedback('已加入「${entry.word}」到複習資料庫');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showAddFeedback('加入失敗：$error');
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

        final threshold = settingsNotifier.dailyNewWordsReviewThreshold;
        final desiredCount = settingsNotifier.dailyNewWordsCount;

        if (widget.dueCount > threshold) {
          return SectionCard(
            title: '今日補新字',
            subtitle: '今天待複習 ${widget.dueCount} 個，超過你設定的 $threshold 個',
            child: const Text('今天先專心複習，等待補量降下來後再補新字。'),
          );
        }

        final recommendations = _recommendations;

        if (_errorMessage != null && recommendations.isEmpty) {
          return SectionCard(
            title: '今日補新字',
            subtitle: '目前無法準備推薦清單',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_errorMessage!),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _handleDependenciesChanged,
                  child: const Text('重新載入'),
                ),
              ],
            ),
          );
        }

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
    required this.isSubmitting,
    required this.onReview,
    required this.onMarkMastered,
    required this.onTap,
    required this.showImage,
  });

  final WordCard card;
  final bool isSubmitting;
  final Future<void> Function(ReviewRating rating) onReview;
  final Future<void> Function() onMarkMastered;
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
            color: Colors.black.withValues(alpha: 0.06),
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
                    TextButton(
                      onPressed: isSubmitting
                          ? null
                          : () => unawaited(onMarkMastered()),
                      child: const Text('已掌握'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 8.0;
                    final buttonWidth = (constraints.maxWidth - spacing) / 2;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        _ReviewRatingButton(
                          width: buttonWidth,
                          rating: ReviewRating.forgot,
                          icon: Icons.replay_rounded,
                          onPressed: onReview,
                          enabled: !isSubmitting,
                        ),
                        _ReviewRatingButton(
                          width: buttonWidth,
                          rating: ReviewRating.hard,
                          icon: Icons.psychology_alt_outlined,
                          onPressed: onReview,
                          enabled: !isSubmitting,
                        ),
                        _ReviewRatingButton(
                          width: buttonWidth,
                          rating: ReviewRating.good,
                          icon: Icons.check_rounded,
                          onPressed: onReview,
                          emphasized: true,
                          enabled: !isSubmitting,
                        ),
                        _ReviewRatingButton(
                          width: buttonWidth,
                          rating: ReviewRating.easy,
                          icon: Icons.fast_forward_rounded,
                          onPressed: onReview,
                          enabled: !isSubmitting,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewRatingButton extends StatelessWidget {
  const _ReviewRatingButton({
    required this.width,
    required this.rating,
    required this.icon,
    required this.onPressed,
    required this.enabled,
    this.emphasized = false,
  });

  final double width;
  final ReviewRating rating;
  final IconData icon;
  final Future<void> Function(ReviewRating rating) onPressed;
  final bool enabled;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(rating.label)),
      ],
    );
    return SizedBox(
      width: width,
      child: emphasized
          ? FilledButton(
              onPressed: enabled ? () => unawaited(onPressed(rating)) : null,
              child: child,
            )
          : OutlinedButton(
              onPressed: enabled ? () => unawaited(onPressed(rating)) : null,
              child: child,
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
        color: const Color(0xFF0B6E99).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.book, color: Color(0xFF0B6E99)),
    );
  }
}
