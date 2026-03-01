import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/date_utils.dart';
import '../widgets/section_card.dart';
import '../widgets/sort_selector.dart';

class WordsListPage extends StatefulWidget {
  const WordsListPage({super.key});

  @override
  State<WordsListPage> createState() => _WordsListPageState();
}

class _WordsListPageState extends State<WordsListPage> {
  bool _showOnlyPending = false;

  String _meaningAndPartText(WordCard card) {
    final meaning = card.meaning.trim();
    if (meaning.isEmpty) {
      return '未填中文意義 · ${card.partOfSpeech.label}';
    }
    return '$meaning · ${card.partOfSpeech.label}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final words = notifier.words;
        final pendingWordsCount = notifier.pendingWordsCount;
        final visibleWords = _showOnlyPending
            ? words
                  .where((card) => card.needsCompletion)
                  .toList(growable: false)
            : words;
        final canSync = notifier.canSync;
        final isSyncing = notifier.isSyncing;
        final showImages = context.watch<SettingsNotifier>().showImages;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '單字列表',
              subtitle: '已建立 ${words.length} 個單字 · 待補 $pendingWordsCount 個',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canSync)
                    IconButton(
                      tooltip: isSyncing ? '同步中...' : '手動同步',
                      visualDensity: VisualDensity.compact,
                      onPressed: isSyncing
                          ? null
                          : () async {
                              final ok = await notifier.syncNow();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok ? '同步完成' : '同步失敗，請稍後重試'),
                                  ),
                                );
                              }
                            },
                      icon: isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync, color: Color(0xFF0B6E99)),
                    ),
                  const Icon(Icons.sort, color: Color(0xFF0B6E99)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SortSelector(
                      mode: notifier.sortMode,
                      onChanged: notifier.setSortMode,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('全部 ${words.length}'),
                        selected: !_showOnlyPending,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _showOnlyPending = false;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text('只看待補 $pendingWordsCount'),
                        selected: _showOnlyPending,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _showOnlyPending = true;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (visibleWords.isEmpty && words.isEmpty)
              const _EmptyList()
            else if (visibleWords.isEmpty)
              _EmptyPendingList(
                onShowAll: () {
                  setState(() {
                    _showOnlyPending = false;
                  });
                },
              )
            else
              ...visibleWords.map(
                (card) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/detail',
                          arguments: card.id,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              if (showImages) ...[
                                _Thumb(card: card),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      card.word,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      card.sentences.isNotEmpty
                                          ? card.sentences.first
                                          : '尚未填寫例句',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _meaningAndPartText(card),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.black54),
                                    ),
                                    if (card.needsCompletion) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFF2A65A,
                                          ).withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '待補：${card.missingFieldLabels.join('、')}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF8C4A06),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      '建立：${formatDate(card.createdAt)}  ·  下次：${formatDate(card.nextReviewDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyPendingList extends StatelessWidget {
  const _EmptyPendingList({required this.onShowAll});

  final VoidCallback onShowAll;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('目前沒有待補資料的單字'),
          const SizedBox(height: 8),
          TextButton(onPressed: onShowAll, child: const Text('查看全部單字')),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

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
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF2A65A).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit_note, color: Color(0xFFF2A65A)),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('還沒有單字，先新增第一個吧。')),
        ],
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
    final cacheExtent = (56 * dpr).round();

    if (card.imageBytes != null && card.imageBytes!.isNotEmpty) {
      final bytes = card.imageBytes!;
      final typedBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          typedBytes,
          width: 56,
          height: 56,
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
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          cacheWidth: cacheExtent,
          cacheHeight: cacheExtent,
        ),
      );
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.book, color: Color(0xFF0B6E99)),
    );
  }
}
