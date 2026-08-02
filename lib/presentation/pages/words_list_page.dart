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

enum _WordListFilter { all, pending, difficult }

class WordsListPage extends StatefulWidget {
  const WordsListPage({super.key});

  @override
  State<WordsListPage> createState() => _WordsListPageState();
}

class _WordsListPageState extends State<WordsListPage> {
  static const String _untaggedFilterValue = '__untagged__';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  _WordListFilter _listFilter = _WordListFilter.all;
  String? _selectedTagFilter;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _meaningAndPartText(WordCard card) {
    final meaning = card.meaning.trim();
    if (meaning.isEmpty) {
      return '未填中文意義 · ${card.partOfSpeech.label}';
    }
    return '$meaning · ${card.partOfSpeech.label}';
  }

  bool _matchesSelectedTag(WordCard card) {
    final selectedTagFilter = _selectedTagFilter;
    if (selectedTagFilter == null) {
      return true;
    }
    if (selectedTagFilter == _untaggedFilterValue) {
      return card.customTags.isEmpty;
    }
    return card.customTags.contains(selectedTagFilter);
  }

  bool _matchesSearchQuery(WordCard card) {
    final query = _normalizeSearchText(_searchQuery);
    if (query.isEmpty) {
      return true;
    }

    return _normalizeSearchText(card.word).contains(query) ||
        _normalizeSearchText(card.meaning).contains(query);
  }

  bool _matchesListFilter(WordCard card) {
    return switch (_listFilter) {
      _WordListFilter.all => true,
      _WordListFilter.pending => card.needsCompletion,
      _WordListFilter.difficult => card.isDifficult,
    };
  }

  String _normalizeSearchText(String value) {
    return value.trim().toLowerCase();
  }

  void _clearSearchQuery() {
    _searchController.clear();
    _searchFocusNode.requestFocus();
    setState(() {
      _searchQuery = '';
    });
  }

  Future<void> _confirmRemoveCustomTag(
    BuildContext context,
    WordsNotifier notifier, {
    required String tag,
    required int count,
  }) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除標籤'),
          content: Text('要刪除「$tag」嗎？這會從 $count 個單字移除此標籤，不會刪除單字。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('刪除標籤'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true) {
      return;
    }

    final removedCount = await notifier.removeCustomTag(tag);
    if (!context.mounted) {
      return;
    }

    if (_selectedTagFilter == tag) {
      setState(() {
        _selectedTagFilter = null;
      });
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已從 $removedCount 個單字移除「$tag」標籤')));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final words = notifier.words;
        final tagCounts = notifier.customTagCounts;
        final untaggedCount = words
            .where((card) => card.customTags.isEmpty)
            .length;
        final pendingWordsCount = notifier.pendingWordsCount;
        final difficultWordsCount = words
            .where((card) => card.isDifficult)
            .length;
        final visibleWords = words
            .where(_matchesListFilter)
            .where(_matchesSelectedTag)
            .where(_matchesSearchQuery)
            .toList(growable: false);
        final canSync = notifier.canSync;
        final isSyncing = notifier.isSyncing;
        final showImages = context.watch<SettingsNotifier>().showImages;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;
        final hasTagFilters = tagCounts.isNotEmpty || untaggedCount > 0;
        final hasSearchQuery = _searchQuery.trim().isNotEmpty;
        final hasActiveTagFilter = _selectedTagFilter != null;
        final hasAnyFilter =
            _listFilter != _WordListFilter.all ||
            hasActiveTagFilter ||
            hasSearchQuery;
        final hasFilterWithoutSearch =
            _listFilter != _WordListFilter.all || hasActiveTagFilter;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: '搜尋英文單字或中文意思',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: hasSearchQuery
                          ? IconButton(
                              tooltip: '清除搜尋',
                              onPressed: _clearSearchQuery,
                              icon: const Icon(Icons.close),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('全部 ${words.length}'),
                        selected: _listFilter == _WordListFilter.all,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _listFilter = _WordListFilter.all;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text('只看待補 $pendingWordsCount'),
                        selected: _listFilter == _WordListFilter.pending,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _listFilter = _WordListFilter.pending;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text('困難單字 $difficultWordsCount'),
                        selected: _listFilter == _WordListFilter.difficult,
                        onSelected: (selected) {
                          if (!selected) {
                            return;
                          }
                          setState(() {
                            _listFilter = _WordListFilter.difficult;
                          });
                        },
                      ),
                    ],
                  ),
                  if (hasTagFilters) ...[
                    const SizedBox(height: 12),
                    Text(
                      '標籤篩選',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('全部標籤 ${words.length}'),
                            selected: _selectedTagFilter == null,
                            onSelected: (selected) {
                              if (!selected) {
                                return;
                              }
                              setState(() {
                                _selectedTagFilter = null;
                              });
                            },
                          ),
                          if (untaggedCount > 0)
                            ChoiceChip(
                              label: Text('未標籤 $untaggedCount'),
                              selected:
                                  _selectedTagFilter == _untaggedFilterValue,
                              onSelected: (selected) {
                                if (!selected) {
                                  return;
                                }
                                setState(() {
                                  _selectedTagFilter = _untaggedFilterValue;
                                });
                              },
                            ),
                          ...tagCounts.entries.map(
                            (entry) => InputChip(
                              label: Text('${entry.key} ${entry.value}'),
                              selected: _selectedTagFilter == entry.key,
                              onSelected: (selected) {
                                if (!selected) {
                                  return;
                                }
                                setState(() {
                                  _selectedTagFilter = entry.key;
                                });
                              },
                              deleteIcon: const Icon(Icons.close),
                              deleteButtonTooltipMessage: '刪除標籤 ${entry.key}',
                              onDeleted: () => _confirmRemoveCustomTag(
                                context,
                                notifier,
                                tag: entry.key,
                                count: entry.value,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (visibleWords.isEmpty && words.isEmpty)
              const _EmptyList()
            else if (visibleWords.isEmpty)
              _EmptyFilteredList(
                message: hasSearchQuery && hasFilterWithoutSearch
                    ? '目前篩選條件下找不到符合搜尋的單字'
                    : hasSearchQuery
                    ? '找不到符合搜尋的單字'
                    : _listFilter == _WordListFilter.pending &&
                          hasActiveTagFilter
                    ? '這個標籤目前沒有待補資料的單字'
                    : _listFilter == _WordListFilter.pending
                    ? '目前沒有待補資料的單字'
                    : _listFilter == _WordListFilter.difficult
                    ? '目前沒有需要加強的困難單字'
                    : '這個標籤目前沒有單字',
                actionLabel: hasSearchQuery && hasFilterWithoutSearch
                    ? '清除搜尋與篩選'
                    : hasSearchQuery
                    ? '清除搜尋'
                    : hasAnyFilter
                    ? '清除篩選'
                    : '查看全部單字',
                onReset: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _listFilter = _WordListFilter.all;
                    _selectedTagFilter = null;
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
                          color: Colors.black.withValues(alpha: 0.05),
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
                                    if (card.customTags.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          ...card.customTags
                                              .take(3)
                                              .map(
                                                (tag) =>
                                                    _WordTagChip(label: tag),
                                              ),
                                          if (card.customTags.length > 3)
                                            _WordTagChip(
                                              label:
                                                  '+${card.customTags.length - 3}',
                                            ),
                                        ],
                                      ),
                                    ],
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
                                          ).withValues(alpha: 0.18),
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
                                    if (card.isDifficult) ...[
                                      const SizedBox(height: 8),
                                      const _DifficultWordBadge(),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      card.isMastered
                                          ? '建立：${formatDate(card.createdAt)}  ·  狀態：已掌握'
                                          : card.hasCompletedReviewSchedule
                                          ? '建立：${formatDate(card.createdAt)}  ·  狀態：已完成複習週期'
                                          : '建立：${formatDate(card.createdAt)}  ·  下次：${formatDate(card.nextReviewDate)}',
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

class _EmptyFilteredList extends StatelessWidget {
  const _EmptyFilteredList({
    required this.message,
    required this.actionLabel,
    required this.onReset,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onReset;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 8),
          TextButton(onPressed: onReset, child: Text(actionLabel)),
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
            color: Colors.black.withValues(alpha: 0.05),
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
              color: const Color(0xFFF2A65A).withValues(alpha: 0.2),
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
        color: const Color(0xFF0B6E99).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.book, color: Color(0xFF0B6E99)),
    );
  }
}

class _WordTagChip extends StatelessWidget {
  const _WordTagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF0B6E99),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DifficultWordBadge extends StatelessWidget {
  const _DifficultWordBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2A65A).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '需要加強',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF8C4A06),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
