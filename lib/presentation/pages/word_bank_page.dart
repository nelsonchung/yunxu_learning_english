import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/builtin_word_bank_repository.dart';
import '../../domain/models/builtin_word_entry.dart';
import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

extension _WordBankAudienceFilterLabel on BuiltinWordBankAudienceFilter {
  String get label {
    switch (this) {
      case BuiltinWordBankAudienceFilter.all:
        return '全部';
      case BuiltinWordBankAudienceFilter.general:
        return '一般';
      case BuiltinWordBankAudienceFilter.elementary:
        return '國小';
      case BuiltinWordBankAudienceFilter.juniorHigh:
        return '國中';
      case BuiltinWordBankAudienceFilter.seniorHigh:
        return '高中';
      case BuiltinWordBankAudienceFilter.college:
        return '大學';
      case BuiltinWordBankAudienceFilter.toeic:
        return 'TOEIC';
    }
  }
}

class WordBankPage extends StatefulWidget {
  const WordBankPage({super.key});

  @override
  State<WordBankPage> createState() => _WordBankPageState();
}

class _WordBankPageState extends State<WordBankPage> {
  static const Duration _addFeedbackDuration = Duration(seconds: 2);
  static const Duration _searchDebounceDuration = Duration(milliseconds: 250);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Set<String> _addingWords = <String>{};

  Timer? _searchDebounceTimer;
  List<BuiltinWordEntry> _visibleEntries = const [];
  Map<BuiltinWordBankAudienceFilter, int> _filterCounts =
      _createEmptyFilterCounts();
  BuiltinWordBankAudienceFilter _selectedFilter =
      BuiltinWordBankAudienceFilter.all;
  String _inputQuery = '';
  String _activeQuery = '';
  bool _isSearchPending = false;
  bool _hasFilterCounts = false;
  bool _isLoading = true;
  String? _errorMessage;
  int _searchRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadWordBank();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearchQuery() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.requestFocus();
    unawaited(
      _runSearch(
        query: '',
        inputQuery: '',
        filter: _selectedFilter,
        markPending: false,
      ),
    );
  }

  Future<void> _loadWordBank() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      unawaited(_loadFilterCounts());
      await _runSearch(
        query: _activeQuery,
        inputQuery: _inputQuery,
        filter: _selectedFilter,
        markPending: false,
      );

      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '無法讀取字庫：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFilterCounts() async {
    try {
      final counts = await context
          .read<BuiltinWordBankRepository>()
          .fetchFilterCounts();
      if (!mounted) {
        return;
      }
      setState(() {
        _filterCounts = counts;
        _hasFilterCounts = true;
      });
    } catch (error) {
      debugPrint('WordBankPage fetchFilterCounts failed: $error');
    }
  }

  Future<void> _runSearch({
    required String query,
    required String inputQuery,
    required BuiltinWordBankAudienceFilter filter,
    required bool markPending,
  }) async {
    final requestVersion = ++_searchRequestVersion;

    if (mounted) {
      setState(() {
        _selectedFilter = filter;
        _inputQuery = inputQuery;
        _isSearchPending = markPending;
        _errorMessage = null;
      });
    }

    try {
      final result = await context.read<BuiltinWordBankRepository>().search(
        query: query,
        filter: filter,
      );

      if (!mounted || requestVersion != _searchRequestVersion) {
        return;
      }

      setState(() {
        _activeQuery = query;
        _inputQuery = inputQuery;
        _selectedFilter = filter;
        _visibleEntries = result.entries;
        _isSearchPending = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _searchRequestVersion) {
        return;
      }
      setState(() {
        _isSearchPending = false;
        _errorMessage = '無法讀取字庫：$error';
      });
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounceTimer?.cancel();

    final shouldDeferSearch = value != _activeQuery;
    setState(() {
      _inputQuery = value;
      _isSearchPending = shouldDeferSearch;
    });

    if (!shouldDeferSearch) {
      return;
    }

    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      if (!mounted) {
        return;
      }
      unawaited(
        _runSearch(
          query: value,
          inputQuery: value,
          filter: _selectedFilter,
          markPending: false,
        ),
      );
    });
  }

  int _countForFilter(BuiltinWordBankAudienceFilter filter) {
    return _filterCounts[filter] ?? 0;
  }

  static Map<BuiltinWordBankAudienceFilter, int> _createEmptyFilterCounts() {
    return Map<BuiltinWordBankAudienceFilter, int>.fromEntries(
      BuiltinWordBankAudienceFilter.values.map(
        (filter) => MapEntry<BuiltinWordBankAudienceFilter, int>(filter, 0),
      ),
    );
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

  Future<void> _addEntry(BuiltinWordEntry entry) async {
    final key = entry.word.toLowerCase();
    final notifier = context.read<WordsNotifier>();
    final exists = notifier.words.any((item) => item.word.toLowerCase() == key);

    if (exists) {
      _showAddFeedback('「${entry.word}」已在複習資料庫中');
      return;
    }

    if (_addingWords.contains(key)) {
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _loadWordBank,
                child: const Text('重新讀取'),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        final hasQuery = _inputQuery.trim().isNotEmpty;
        final hasActiveQuery = _activeQuery.trim().isNotEmpty;
        final filtered = _visibleEntries;
        final existingWords = notifier.words
            .map((item) => item.word.toLowerCase())
            .toSet();
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120;
        final resultCount = filtered.length;
        final hasResults = filtered.isNotEmpty;
        final itemCount = 2 + (hasResults ? resultCount : 1);
        final totalCountLabel = _hasFilterCounts
            ? '內建 ${_countForFilter(BuiltinWordBankAudienceFilter.all)} 筆單字資料，可依程度與考試目標過濾'
            : '內建字庫資料，可依程度與考試目標過濾';

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SectionCard(
                title: '字庫搜尋',
                subtitle: totalCountLabel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: _handleSearchChanged,
                      decoration: InputDecoration(
                        hintText: '例如：co、trans、ability、麵包、補償',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: hasQuery
                            ? IconButton(
                                tooltip: '清除搜尋',
                                onPressed: _clearSearchQuery,
                                icon: const Icon(Icons.close),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '可搜尋英文單字或中文意思',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: BuiltinWordBankAudienceFilter.values
                            .map((filter) {
                              final chipLabel = _hasFilterCounts
                                  ? '${filter.label} ${_countForFilter(filter)}'
                                  : filter.label;
                              return ChoiceChip(
                                label: Text(chipLabel),
                                selected: _selectedFilter == filter,
                                onSelected: (selected) {
                                  if (!selected) {
                                    return;
                                  }
                                  _searchDebounceTimer?.cancel();
                                  unawaited(
                                    _runSearch(
                                      query: _searchController.text,
                                      inputQuery: _searchController.text,
                                      filter: filter,
                                      markPending: true,
                                    ),
                                  );
                                },
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isSearchPending
                          ? '正在更新搜尋結果...'
                          : !hasActiveQuery
                          ? '目前顯示「${_selectedFilter.label}」前 100 筆，輸入英文或中文關鍵字可精準過濾'
                          : '「${_selectedFilter.label}」符合 $resultCount 筆（最多顯示 200 筆）',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              );
            }

            if (index == 1) {
              return const SizedBox(height: 16);
            }

            if (!hasResults) {
              return const _EmptyWordBankResult();
            }

            final entry = filtered[index - 2];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _WordBankCard(
                entry: entry,
                isAdded: existingWords.contains(entry.word.toLowerCase()),
                isAdding: _addingWords.contains(entry.word.toLowerCase()),
                onAdd: () => _addEntry(entry),
              ),
            );
          },
        );
      },
    );
  }
}

class _WordBankCard extends StatelessWidget {
  const _WordBankCard({
    required this.entry,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
  });

  final BuiltinWordEntry entry;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final partLabel = entry.partOfSpeech.label;
    final badges = entry.audienceLabels;
    final previewSentences = entry.sentences
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList(growable: false);

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
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
                    '${entry.meaning} · $partLabel',
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
                                ).withValues(alpha: 0.10),
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
                  if (previewSentences.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '例句',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    ...previewSentences.map(
                      (sentence) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          sentence,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.black87),
                        ),
                      ),
                    ),
                  ],
                  if (entry.sourcePage > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '來源頁碼：${entry.sourcePage}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
                  if (entry.difficultyLevel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '難度級數：${entry.difficultyLevel}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    ),
                  ],
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
      ),
    );
  }
}

class _EmptyWordBankResult extends StatelessWidget {
  const _EmptyWordBankResult();

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
              color: const Color(0xFF0B6E99).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.search_off, color: Color(0xFF0B6E99)),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('查不到符合的英文單字或中文意思，請換個關鍵字試試看。')),
        ],
      ),
    );
  }
}
