import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/builtin_word_bank_repository.dart';
import '../../domain/models/builtin_word_entry.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/word_bank_search_service.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

enum _WordBankAudienceFilter {
  all,
  general,
  elementary,
  juniorHigh,
  seniorHigh,
  college,
  toeic,
}

extension _WordBankAudienceFilterLabel on _WordBankAudienceFilter {
  String get label {
    switch (this) {
      case _WordBankAudienceFilter.all:
        return '全部';
      case _WordBankAudienceFilter.general:
        return '一般';
      case _WordBankAudienceFilter.elementary:
        return '國小';
      case _WordBankAudienceFilter.juniorHigh:
        return '國中';
      case _WordBankAudienceFilter.seniorHigh:
        return '高中';
      case _WordBankAudienceFilter.college:
        return '大學';
      case _WordBankAudienceFilter.toeic:
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
  static const Duration _searchDebounceDuration = Duration(milliseconds: 250);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Set<String> _addingWords = <String>{};
  final _searchService = WordBankSearchService();

  Timer? _searchDebounceTimer;
  List<BuiltinWordEntry> _entries = const [];
  List<BuiltinWordEntry> _visibleEntries = const [];
  Map<_WordBankAudienceFilter, int> _filterCounts = _createEmptyFilterCounts();
  _WordBankAudienceFilter _selectedFilter = _WordBankAudienceFilter.all;
  String _inputQuery = '';
  String _activeQuery = '';
  bool _isSearchPending = false;
  bool _isLoading = true;
  String? _errorMessage;

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
    _applySearch(
      query: '',
      inputQuery: '',
      filter: _selectedFilter,
      isSearchPending: false,
    );
  }

  Future<void> _loadWordBank() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loaded = await context.read<BuiltinWordBankRepository>().fetchAll();
      _searchService.prime(loaded);
      final counts = _buildFilterCounts(loaded);
      final visibleEntries = _filteredEntries(
        query: _activeQuery,
        filter: _selectedFilter,
        entries: loaded,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _entries = loaded;
        _visibleEntries = visibleEntries;
        _filterCounts = counts;
      });
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

  List<BuiltinWordEntry> _filteredEntries({
    required String query,
    required _WordBankAudienceFilter filter,
    Iterable<BuiltinWordEntry>? entries,
  }) {
    final sourceEntries = entries ?? _entries;
    final scopedEntries = sourceEntries.where(
      (entry) => _matchesFilter(entry, filter),
    );
    return _searchService.search(entries: scopedEntries, query: query);
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
      _applySearch(
        query: value,
        inputQuery: value,
        filter: _selectedFilter,
        isSearchPending: false,
      );
    });
  }

  void _applySearch({
    required String query,
    required String inputQuery,
    required _WordBankAudienceFilter filter,
    required bool isSearchPending,
  }) {
    final visibleEntries = _filteredEntries(query: query, filter: filter);

    setState(() {
      _activeQuery = query;
      _inputQuery = inputQuery;
      _selectedFilter = filter;
      _visibleEntries = visibleEntries;
      _isSearchPending = isSearchPending;
    });
  }

  int _countForFilter(_WordBankAudienceFilter filter) {
    return _filterCounts[filter] ?? 0;
  }

  bool _matchesFilter(BuiltinWordEntry entry, _WordBankAudienceFilter filter) {
    switch (filter) {
      case _WordBankAudienceFilter.all:
        return true;
      case _WordBankAudienceFilter.general:
        return entry.audienceTags.contains(BuiltinAudienceTag.general);
      case _WordBankAudienceFilter.elementary:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.elementary);
      case _WordBankAudienceFilter.juniorHigh:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.juniorHigh);
      case _WordBankAudienceFilter.seniorHigh:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.seniorHigh);
      case _WordBankAudienceFilter.college:
        return entry.schoolLevels.contains(BuiltinSchoolLevel.college);
      case _WordBankAudienceFilter.toeic:
        return entry.examTags.contains(BuiltinExamTag.toeic);
    }
  }

  Map<_WordBankAudienceFilter, int> _buildFilterCounts(
    List<BuiltinWordEntry> entries,
  ) {
    final counts = _createEmptyFilterCounts();

    for (final entry in entries) {
      counts[_WordBankAudienceFilter.all] =
          (counts[_WordBankAudienceFilter.all] ?? 0) + 1;

      for (final filter in _WordBankAudienceFilter.values) {
        if (filter == _WordBankAudienceFilter.all) {
          continue;
        }
        if (_matchesFilter(entry, filter)) {
          counts[filter] = (counts[filter] ?? 0) + 1;
        }
      }
    }

    return counts;
  }

  static Map<_WordBankAudienceFilter, int> _createEmptyFilterCounts() {
    return Map<_WordBankAudienceFilter, int>.fromEntries(
      _WordBankAudienceFilter.values.map(
        (filter) => MapEntry<_WordBankAudienceFilter, int>(filter, 0),
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

  Future<void> _addEntry(BuiltinWordEntry entry) async {
    final key = entry.word.toLowerCase();
    final notifier = context.read<WordsNotifier>();
    final exists = notifier.words.any((item) => item.word.toLowerCase() == key);

    if (exists) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('「${entry.word}」已在複習資料庫中')));
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

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SectionCard(
                title: '字庫搜尋',
                subtitle: '內建 ${_entries.length} 筆單字資料，可依程度與考試目標過濾',
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
                        children: _WordBankAudienceFilter.values
                            .map((filter) {
                              return ChoiceChip(
                                label: Text(
                                  '${filter.label} ${_countForFilter(filter)}',
                                ),
                                selected: _selectedFilter == filter,
                                onSelected: (selected) {
                                  if (!selected) {
                                    return;
                                  }
                                  _searchDebounceTimer?.cancel();
                                  _applySearch(
                                    query: _searchController.text,
                                    inputQuery: _searchController.text,
                                    filter: filter,
                                    isSearchPending: false,
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
