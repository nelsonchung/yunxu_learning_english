import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../../domain/services/word_bank_refresh_service.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

enum _MeaningChoice { keep, replace, edit }

enum _SentenceChoice { keep, replace, append }

class WordBankRefreshPage extends StatefulWidget {
  const WordBankRefreshPage({super.key, required this.wordId});

  final String wordId;

  @override
  State<WordBankRefreshPage> createState() => _WordBankRefreshPageState();
}

class _WordBankRefreshPageState extends State<WordBankRefreshPage> {
  WordBankComparison? _comparison;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  _MeaningChoice _meaningChoice = _MeaningChoice.keep;
  _SentenceChoice _sentenceChoice = _SentenceChoice.keep;
  bool _replaceParts = false;
  final _meaningController = TextEditingController();
  final Set<String> _selectedSentences = {};
  List<String>? _editedSentences;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _meaningController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final card = context.read<WordsNotifier>().findById(widget.wordId);
      if (card == null || card.isDeleted) {
        throw StateError('找不到單字資料，可能已被刪除');
      }
      final comparison = await context.read<WordBankRefreshService>().compare(
        card,
      );
      if (!mounted) return;
      setState(() {
        _comparison = comparison;
        _meaningChoice = _MeaningChoice.keep;
        _sentenceChoice = _SentenceChoice.keep;
        _replaceParts = false;
        _selectedSentences.clear();
        _editedSentences = null;
        _meaningController.text = card.meaning;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _cleanSentences(Iterable<String> sentences) => sentences
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.isNotEmpty)
      .toSet()
      .toList();

  String? get _meaning => switch (_meaningChoice) {
    _MeaningChoice.keep => null,
    _MeaningChoice.replace => _comparison!.entry!.meaning.trim(),
    _MeaningChoice.edit => _meaningController.text.trim(),
  };

  List<String>? get _sentences {
    if (_sentenceChoice == _SentenceChoice.keep) return null;
    if (_editedSentences != null) return _editedSentences;
    final comparison = _comparison!;
    if (_sentenceChoice == _SentenceChoice.replace) {
      return _cleanSentences(comparison.entry!.sentences);
    }
    final existing = _cleanSentences(comparison.card.sentences).toSet();
    return [
      ...comparison.card.sentences,
      ..._selectedSentences.where((sentence) => !existing.contains(sentence)),
    ];
  }

  bool get _hasEdits {
    final comparison = _comparison!;
    return (_meaning != null && _meaning != comparison.card.meaning.trim()) ||
        (_sentences != null &&
            !listEquals(_sentences, comparison.card.sentences)) ||
        (_replaceParts && comparison.partsOfSpeechChanged);
  }

  Future<void> _editSentences() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _SentenceEditorDialog(sentences: _sentences!),
    );
    if (!mounted) return;
    if (result != null) setState(() => _editedSentences = result);
  }

  Future<void> _apply() async {
    if (_saving || !_hasEdits) return;
    final meaning = _meaning;
    final sentences = _sentences;
    if (meaning != null && meaning.isEmpty ||
        sentences != null && sentences.isEmpty) {
      setState(() => _error = '更新的中文意思與例句不可為空');
      return;
    }
    setState(() => _saving = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認更新內容'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('中文意思：${meaning ?? '保留目前內容'}'),
              const SizedBox(height: 12),
              Text(
                '例句：${sentences == null ? '保留目前例句' : '${sentences.length} 句'}',
              ),
              if (sentences != null)
                for (final sentence in sentences) Text('• $sentence'),
              const SizedBox(height: 12),
              Text('詞性：${_replaceParts ? '使用字庫內容' : '保留目前內容'}'),
              const SizedBox(height: 16),
              const Text('複習紀錄、下次複習日期、已掌握狀態與個人筆記、標籤、圖片全部保留。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('套用更新'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _saving = false);
      return;
    }
    try {
      final changed = await context.read<WordsNotifier>().applyWordBankRefresh(
        comparison: _comparison!,
        meaning: meaning,
        sentences: sentences,
        partsOfSpeech: _replaceParts ? _comparison!.entry!.partsOfSpeech : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changed ? '已更新單字內容，複習進度已保留' : '內容沒有變更')),
      );
      Navigator.pop(context, changed);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$error'),
            action: SnackBarAction(label: '重新比對', onPressed: _load),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choices<T>(
    List<(T, String)> choices,
    T selected,
    ValueChanged<T> onSelected,
  ) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final (value, label) in choices)
        ChoiceChip(
          label: Text(label),
          selected: selected == value,
          onSelected: _saving ? null : (_) => onSelected(value),
        ),
    ],
  );

  Widget _comparisonText(String current, String bank) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('目前卡片', style: TextStyle(fontWeight: FontWeight.bold)),
      SelectableText(current.isEmpty ? '未填寫' : current),
      const SizedBox(height: 12),
      const Text('目前字庫', style: TextStyle(fontWeight: FontWeight.bold)),
      SelectableText(bank.isEmpty ? '未填寫' : bank),
      const SizedBox(height: 16),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;
    final entry = comparison?.entry;
    final notifier = context.watch<WordsNotifier>();
    final busy =
        _saving ||
        notifier.isSyncing ||
        notifier.isRestoring ||
        notifier.isBackingUp ||
        notifier.isLoading ||
        notifier.isRefreshingWordBank;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('比對字庫內容')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    TextButton(
                      onPressed: busy ? null : _load,
                      child: const Text('重新比對'),
                    ),
                  ],
                  if (comparison != null && entry == null)
                    Text(switch (comparison.status) {
                      WordBankMatchStatus.ambiguous => '字庫有多個對應詞條，無法安全套用。',
                      WordBankMatchStatus.ineligible => '只有內建字庫來源的單字可以比對更新。',
                      _ => '目前字庫找不到對應單字，未變更任何內容。',
                    }),
                  if (comparison != null && entry != null) ...[
                    Text(
                      comparison.card.word,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      comparison.hasChanges
                          ? '內容與目前 App 字庫不同。請選擇要保留或更新的內容，複習進度會保留。'
                          : '已與目前字庫一致',
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: '中文意思',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _comparisonText(
                            comparison.card.meaning,
                            entry.meaning,
                          ),
                          _choices(
                            [
                              (_MeaningChoice.keep, '保留目前內容'),
                              if (entry.meaning.trim().isNotEmpty)
                                (_MeaningChoice.replace, '使用字庫內容'),
                              (_MeaningChoice.edit, '自行編輯'),
                            ],
                            _meaningChoice,
                            (choice) => setState(() => _meaningChoice = choice),
                          ),
                          if (_meaningChoice == _MeaningChoice.edit) ...[
                            TextField(
                              controller: _meaningController,
                              enabled: !_saving,
                              minLines: 1,
                              maxLines: 5,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: '編輯中文意思',
                              ),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() {
                                      _meaningController.text = entry.meaning;
                                    }),
                              child: const Text('帶入字庫內容'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: '例句',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _comparisonText(
                            comparison.card.sentences.join('\n'),
                            entry.sentences.join('\n'),
                          ),
                          _choices(
                            [
                              (_SentenceChoice.keep, '保留目前例句'),
                              if (_cleanSentences(entry.sentences).isNotEmpty)
                                (_SentenceChoice.replace, '用字庫例句全部取代'),
                              (_SentenceChoice.append, '保留並加入選取例句'),
                            ],
                            _sentenceChoice,
                            (choice) => setState(() {
                              _sentenceChoice = choice;
                              _editedSentences = null;
                            }),
                          ),
                          if (_sentenceChoice == _SentenceChoice.replace)
                            const Text('目前的例句（含自行新增或生成的句子）將被取代。'),
                          if (_sentenceChoice == _SentenceChoice.append) ...[
                            const Text('補充會保留原本例句；若舊例句有錯，請編輯移除或選擇全部取代。'),
                            for (final sentence in _cleanSentences(
                              entry.sentences,
                            ))
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(sentence),
                                subtitle:
                                    _cleanSentences(
                                      comparison.card.sentences,
                                    ).contains(sentence)
                                    ? const Text('已存在')
                                    : null,
                                value:
                                    _selectedSentences.contains(sentence) ||
                                    _cleanSentences(
                                      comparison.card.sentences,
                                    ).contains(sentence),
                                onChanged:
                                    _saving ||
                                        _cleanSentences(
                                          comparison.card.sentences,
                                        ).contains(sentence)
                                    ? null
                                    : (selected) => setState(() {
                                        if (selected == true) {
                                          _selectedSentences.add(sentence);
                                        } else {
                                          _selectedSentences.remove(sentence);
                                        }
                                        _editedSentences = null;
                                      }),
                              ),
                          ],
                          if (_sentences != null) ...[
                            const SizedBox(height: 12),
                            const Text(
                              '更新後的例句',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            for (final sentence in _sentences!)
                              Text('• $sentence'),
                            TextButton(
                              onPressed: _saving ? null : _editSentences,
                              child: const Text('編輯更新後的例句'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (comparison.partsOfSpeechChanged) ...[
                      const SizedBox(height: 16),
                      SectionCard(
                        title: '詞性',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _comparisonText(
                              comparison.card.partsOfSpeechLabel,
                              entry.partsOfSpeechLabel,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('更新為字庫詞性'),
                              value: _replaceParts,
                              onChanged: _saving
                                  ? null
                                  : (value) =>
                                        setState(() => _replaceParts = value),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (notifier.isSyncing || notifier.isRestoring)
                      const Text('同步或還原中，請稍後再套用。'),
                    FilledButton(
                      key: const Key('refresh-preview'),
                      onPressed: busy || !_hasEdits ? null : _apply,
                      child: Text(_saving ? '處理中…' : '更新內容並保留複習進度'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SentenceEditorDialog extends StatefulWidget {
  const _SentenceEditorDialog({required this.sentences});
  final List<String> sentences;

  @override
  State<_SentenceEditorDialog> createState() => _SentenceEditorDialogState();
}

class _SentenceEditorDialogState extends State<_SentenceEditorDialog> {
  late final _controller = TextEditingController(
    text: widget.sentences.join('\n'),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('編輯更新後的例句'),
    content: SizedBox(
      width: 560,
      child: TextField(
        controller: _controller,
        minLines: 4,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: '每行一個例句',
          helperText: '可修改文字或刪除不需要的例句',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _controller.text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toSet()
              .toList(),
        ),
        child: const Text('完成編輯'),
      ),
    ],
  );
}

class WordBankRefreshListPage extends StatefulWidget {
  const WordBankRefreshListPage({super.key});

  @override
  State<WordBankRefreshListPage> createState() =>
      _WordBankRefreshListPageState();
}

class _WordBankRefreshListPageState extends State<WordBankRefreshListPage> {
  final List<WordBankComparison> _differences = [];
  bool _loading = true;
  String? _error;
  int _unmatched = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _differences.clear();
      _unmatched = 0;
    });
    final cards = context
        .read<WordsNotifier>()
        .words
        .where((card) => card.origin == WordOrigin.builtinWordBank)
        .toList();
    final service = context.read<WordBankRefreshService>();
    try {
      for (final card in cards) {
        final comparison = await service.compare(card);
        if (!mounted) return;
        if (comparison.entry == null) {
          _unmatched++;
        } else if (comparison.hasChanges) {
          _differences.add(comparison);
        }
      }
    } catch (error) {
      if (mounted) _error = '檢查未完成：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('檢查字庫更新'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: '重新檢查',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('以下單字與目前 App 字庫不同。點選單字，分別決定要保留、取代或補充的內容。'),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                TextButton(onPressed: _load, child: const Text('重試檢查')),
              ],
              if (_unmatched > 0) Text('$_unmatched 個單字無唯一對應詞條，已略過。'),
              if (_differences.isEmpty && _error == null)
                const Text('沒有需要比對的內容差異'),
              for (final comparison in _differences)
                ListTile(
                  title: Text(comparison.card.word),
                  subtitle: Text(
                    [
                      if (comparison.meaningChanged) '中文意思',
                      if (comparison.sentencesChanged) '例句',
                      if (comparison.partsOfSpeechChanged) '詞性',
                    ].join('、'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            WordBankRefreshPage(wordId: comparison.card.id),
                      ),
                    );
                    if (mounted) await _load();
                  },
                ),
            ],
          ),
  );
}
