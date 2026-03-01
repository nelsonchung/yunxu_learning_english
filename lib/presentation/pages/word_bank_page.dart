import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/builtin_word_entry.dart';
import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

class WordBankPage extends StatefulWidget {
  const WordBankPage({super.key});

  @override
  State<WordBankPage> createState() => _WordBankPageState();
}

class _WordBankPageState extends State<WordBankPage> {
  static const String _assetPath = 'assets/word_bank/pdf_word_bank.json';

  final _searchController = TextEditingController();
  final Set<String> _addingWords = <String>{};

  List<BuiltinWordEntry> _entries = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWordBank();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWordBank() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rawJson = await rootBundle.loadString(_assetPath);
      final parsed = jsonDecode(rawJson);
      if (parsed is! List) {
        throw const FormatException('字庫資料格式錯誤');
      }
      final loaded = parsed
          .whereType<Map>()
          .map(
            (item) => BuiltinWordEntry.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((entry) => entry.word.isNotEmpty && entry.meaning.isNotEmpty)
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _entries = loaded;
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

  List<BuiltinWordEntry> _filteredEntries(String query) {
    if (query.isEmpty) {
      return _entries.take(100).toList(growable: false);
    }

    return _entries
        .where(
          (entry) =>
              entry.word.toLowerCase().contains(query) ||
              entry.meaning.contains(query),
        )
        .take(200)
        .toList(growable: false);
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
        final normalizedQuery = _searchController.text.trim().toLowerCase();
        final filtered = _filteredEntries(normalizedQuery);
        final existingWords = notifier.words
            .map((item) => item.word.toLowerCase())
            .toSet();
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '字庫搜尋',
              subtitle: '內建 ${_entries.length} 筆單字資料，輸入部分字串即可過濾',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '例如：co、trans、ability',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    normalizedQuery.isEmpty
                        ? '目前顯示前 100 筆，輸入關鍵字可精準過濾'
                        : '符合 ${filtered.length} 筆（最多顯示 200 筆）',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const _EmptyWordBankResult()
            else
              ...filtered.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WordBankCard(
                    entry: entry,
                    isAdded: existingWords.contains(entry.word.toLowerCase()),
                    isAdding: _addingWords.contains(entry.word.toLowerCase()),
                    onAdd: () => _addEntry(entry),
                  ),
                ),
              ),
          ],
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
                  const SizedBox(height: 6),
                  Text(
                    '來源頁碼：${entry.sourcePage}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
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
          const Expanded(child: Text('查不到符合的單字，請換一個關鍵字試試看。')),
        ],
      ),
    );
  }
}
