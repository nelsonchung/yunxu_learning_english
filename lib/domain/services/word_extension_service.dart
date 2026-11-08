import '../models/builtin_word_entry.dart';
import '../models/word_card.dart';
import '../models/word_extension.dart';
import 'word_relation_data.dart';

/// Finds evidence-backed extensions for any word. Spelling resemblance and
/// shared audience tags alone are not evidence of a lexical relation. Compound
/// and affix clues must also be corroborated by dictionary meanings.
class WordExtensionService {
  WordExtensionService({
    required Future<List<BuiltinWordEntry>> Function() loadEntries,
    List<WordRelation> relations = WordRelationData.relations,
  }) : _loadEntries = loadEntries,
       _relations = relations;

  final Future<List<BuiltinWordEntry>> Function() _loadEntries;
  final List<WordRelation> _relations;
  Future<_ExtensionIndex>? _indexFuture;

  Future<_ExtensionIndex> _index() async {
    final pending = _indexFuture;
    if (pending != null) return pending;
    final loading = _loadEntries().then(_ExtensionIndex.build);
    _indexFuture = loading;
    try {
      return await loading;
    } catch (_) {
      _indexFuture = null;
      rethrow;
    }
  }

  Future<WordExtensionResult> recommend(WordCard card) async {
    final word = _key(card.word);
    if (word.isEmpty) return const WordExtensionResult();
    final index = await _index();
    final source = index.byWord[word];
    final meaning = card.meaning.trim().isEmpty
        ? source?.meaning ?? ''
        : card.meaning;
    final usages = <WordExtensionUsage>[];
    final adjective = card.partsOfSpeech.contains(PartOfSpeech.adjective);
    final curated = WordRelationData.usages[word];
    if (curated != null &&
        _sameSense(meaning, curated.sense, adjective: adjective)) {
      usages.add(curated);
    }
    final examples = card.sentences.where(_usableExample).toList();
    final fromCard = examples.isNotEmpty;
    if (!fromCard &&
        source != null &&
        _sameSense(meaning, source.meaning, adjective: adjective)) {
      examples.addAll(source.sentences.where(_usableExample));
    }
    for (final example in examples.toSet()) {
      if (usages.length >= 2) break;
      if (usages.any((usage) => usage.example == example)) continue;
      usages.add(
        WordExtensionUsage(
          description: '在句子中觀察「${card.word}」的用法',
          example: example,
          source: fromCard ? '目前單字例句' : '內建字庫例句',
        ),
      );
    }

    final candidates =
        <
          String,
          ({WordExtensionRecommendation item, int score, WordRelationKind kind})
        >{};
    void offer(
      BuiltinWordEntry? entry,
      String explanation,
      int score, {
      WordRelationKind kind = WordRelationKind.related,
      String comparisonExample = '',
      bool reviewed = false,
      bool commonForm = false,
      String preferredExample = '',
    }) {
      if (entry == null ||
          !_usableEntry(entry) ||
          !_suitableForLearning(entry)) {
        return;
      }
      if (!reviewed && !commonForm && !_hasCommonEvidence(entry)) return;
      if (preferredExample.isNotEmpty &&
          (!_usableExample(preferredExample) ||
              !entry.sentences.contains(preferredExample))) {
        return;
      }
      final target = _key(entry.word);
      if (target == word) return;
      final candidateKey = '${kind.name}:$target';
      final old = candidates[candidateKey];
      if (old != null && old.score >= score) return;
      candidates[candidateKey] = (
        item: WordExtensionRecommendation(
          entry: entry,
          examples: List.unmodifiable(
            preferredExample.isEmpty
                ? entry.sentences.where(_usableExample)
                : [preferredExample],
          ),
          explanation: explanation,
          comparisonExample: comparisonExample,
        ),
        score: score,
        kind: kind,
      );
    }

    for (final relation in _relations) {
      final forward = _key(relation.sourceWord) == word;
      final reverse = _key(relation.targetWord) == word;
      if (!forward && !reverse) continue;
      final sourceSense = forward ? relation.sourceSense : relation.targetSense;
      final targetSense = forward ? relation.targetSense : relation.sourceSense;
      if (!_sameSense(meaning, sourceSense, adjective: adjective)) continue;
      final sourceParts = forward
          ? relation.sourcePartsOfSpeech
          : relation.targetPartsOfSpeech;
      final targetParts = forward
          ? relation.targetPartsOfSpeech
          : relation.sourcePartsOfSpeech;
      if (sourceParts.isNotEmpty &&
          !card.partsOfSpeech.any(sourceParts.contains)) {
        continue;
      }
      final target = index
          .byWord[_key(forward ? relation.targetWord : relation.sourceWord)];
      if (target == null ||
          !_sameSense(
            target.meaning,
            targetSense,
            adjective: target.partsOfSpeech.contains(PartOfSpeech.adjective),
          )) {
        continue;
      }
      if (targetParts.isNotEmpty &&
          !target.partsOfSpeech.any(targetParts.contains)) {
        continue;
      }
      offer(
        target,
        '明確單字關係：${relation.explanation}',
        100,
        kind: relation.kind,
        comparisonExample: relation.comparisonExample,
        reviewed: true,
        preferredExample: forward
            ? relation.targetExample
            : relation.sourceExample,
      );
    }

    // Each form link carries its own grammatical role and definition clause.
    // Matching another sense of the same dictionary entry is insufficient.
    for (final form in index.forms[word] ?? const <_FormClue>[]) {
      if (card.partsOfSpeech.any(form.sourceParts.contains) &&
          _formSenseMatches(meaning, form)) {
        offer(form.entry, form.explanation, 80, commonForm: form.commonBase);
      }
    }
    final currentSenses = _senseKeys(meaning, adjective: adjective);
    if (adjective) {
      for (final clue in index.negations[word] ?? const <_NegationClue>[]) {
        if (currentSenses.contains(clue.sourceSense)) {
          offer(clue.entry, clue.explanation, 75);
        }
      }
    }
    // Closed compounds need two real words and independent meaning evidence.
    // This rejects accidental splits such as car + pet for carpet.
    if (card.partsOfSpeech.contains(PartOfSpeech.noun) &&
        RegExp(r'^[a-z]+$').hasMatch(word)) {
      for (var split = 3; split <= word.length - 3; split++) {
        final left = index.byWord[word.substring(0, split)];
        final right = index.byWord[word.substring(split)];
        if (left == null ||
            right == null ||
            !_usableEntry(left) ||
            !_usableEntry(right)) {
          continue;
        }
        for (final component in [left, right]) {
          if (!component.partsOfSpeech.contains(PartOfSpeech.noun)) continue;
          final matchesMeaning =
              _senseKeys(
                component.meaning,
                minimumLength: 1,
                examples: component.sentences,
              ).any(
                (componentSense) => currentSenses.any(
                  (sense) => componentSense.length >= 2
                      ? sense.contains(componentSense)
                      : sense.startsWith(componentSense) ||
                            sense.endsWith(componentSense),
                ),
              );
          if (matchesMeaning) {
            offer(
              component,
              '構詞線索：${left.word} + ${right.word}；「${component.word}」的字庫釋義與目前意思相符。這是組字線索，並非同義字。',
              65,
            );
          }
        }
      }
    }
    final senses = _senseKeys(meaning);
    for (final phrase in index.phrases[word] ?? const <BuiltinWordEntry>[]) {
      if (senses.any((sense) => phrase.meaning.contains(sense))) {
        offer(phrase, '字庫片語：含有完整單字「${card.word}」，且釋義與目前意思相符。', 70);
      }
    }
    for (final part in card.partsOfSpeech) {
      for (final sense in _senseKeys(
        meaning,
        adjective: part == PartOfSpeech.adjective,
      )) {
        for (final entry
            in index.bySense['${part.name}:$sense'] ??
                const <BuiltinWordEntry>[]) {
          offer(entry, '字庫釋義同為「$sense」，詞性相同；實際用法請參考例句。', 60);
        }
      }
    }

    final ranked = candidates.values.toList()
      ..sort((a, b) {
        final byEvidence = b.score.compareTo(a.score);
        if (byEvidence != 0) return byEvidence;
        final commonA = _hasCommonEvidence(a.item.entry);
        final commonB = _hasCommonEvidence(b.item.entry);
        if (commonA != commonB) return commonA ? -1 : 1;
        final level = source?.difficultyLevel;
        if (level != null) {
          final gapA = a.item.entry.difficultyLevel == null
              ? 10
              : (a.item.entry.difficultyLevel! - level).abs();
          final gapB = b.item.entry.difficultyLevel == null
              ? 10
              : (b.item.entry.difficultyLevel! - level).abs();
          final byLevel = gapA.compareTo(gapB);
          if (byLevel != 0) return byLevel;
        }
        return _key(a.item.entry.word).compareTo(_key(b.item.entry.word));
      });
    final confused = ranked
        .where((item) => item.kind == WordRelationKind.confused)
        .take(2)
        .map((item) => item.item)
        .toList(growable: false);
    final confusedKeys = confused.map((item) => _key(item.entry.word)).toSet();
    final related = ranked
        .where(
          (item) =>
              item.kind == WordRelationKind.related &&
              !confusedKeys.contains(_key(item.item.entry.word)),
        )
        .take(3)
        .map((item) => item.item)
        .toList(growable: false);
    return WordExtensionResult(
      usages: List.unmodifiable(usages),
      related: List.unmodifiable(related),
      confused: List.unmodifiable(confused),
    );
  }
}

class _ExtensionIndex {
  final byWord = <String, BuiltinWordEntry>{};
  final bySense = <String, List<BuiltinWordEntry>>{};
  final phrases = <String, List<BuiltinWordEntry>>{};
  final negations = <String, List<_NegationClue>>{};
  final forms = <String, List<_FormClue>>{};

  static Future<_ExtensionIndex> build(List<BuiltinWordEntry> entries) async {
    final index = _ExtensionIndex();
    var visited = 0;
    for (final entry in entries) {
      if (++visited % 2000 == 0) await Future<void>.delayed(Duration.zero);
      if (!_cleanText(entry.meaning) || entry.meaning.trim().isEmpty) continue;
      final word = _key(entry.word);
      if (word.isEmpty) continue;
      final previous = index.byWord[word];
      if (previous == null ||
          (!_usableEntry(previous) && _usableEntry(entry))) {
        index.byWord[word] = entry;
      }
    }
    for (final entry in index.byWord.values) {
      if (++visited % 2000 == 0) await Future<void>.delayed(Duration.zero);
      if (!_usableEntry(entry)) continue;
      for (final part in entry.partsOfSpeech) {
        for (final sense in _senseKeys(
          entry.meaning,
          adjective: part == PartOfSpeech.adjective,
          examples: entry.sentences,
        )) {
          (index.bySense['${part.name}:$sense'] ??= []).add(entry);
        }
      }
      if (entry.partsOfSpeech.contains(PartOfSpeech.adjective)) {
        final word = _key(entry.word);
        for (final prefix in _negativePrefixes) {
          if (!word.startsWith(prefix)) continue;
          final stem = word
              .substring(prefix.length)
              .replaceFirst(RegExp(r'^-'), '');
          if (stem.length < 3) continue;
          final base = index.byWord[stem];
          if (base == null ||
              !_usableEntry(base) ||
              !base.partsOfSpeech.contains(PartOfSpeech.adjective)) {
            continue;
          }
          for (final negativeSense in _senseKeys(
            entry.meaning,
            adjective: true,
            examples: entry.sentences,
          )) {
            for (final positiveSense in _senseKeys(
              base.meaning,
              adjective: true,
              examples: base.sentences,
            )) {
              if (!_negators.any(
                (negator) => negativeSense == '$negator$positiveSense',
              )) {
                continue;
              }
              final explanation =
                  '構詞線索：${entry.word} 的 $prefix- 為否定前綴；字庫釋義「$negativeSense」與 ${base.word} 的「$positiveSense」對應，使用時仍需留意語境。';
              (index.negations[word] ??= []).add((
                entry: base,
                sourceSense: negativeSense,
                explanation: explanation,
              ));
              (index.negations[stem] ??= []).add((
                entry: entry,
                sourceSense: positiveSense,
                explanation: explanation,
              ));
            }
          }
        }
      }
      final tokens = _key(entry.word).split(' ');
      if (tokens.length >= 2 &&
          tokens.length <= 6 &&
          tokens.every(
            (token) => RegExp(r"^[a-z]+(?:['-][a-z]+)*$").hasMatch(token),
          )) {
        for (final token in tokens.toSet()) {
          (index.phrases[token] ??= []).add(entry);
        }
      }
      for (final match in _formPattern.allMatches(entry.meaning)) {
        final base = index.byWord[_key(match.group(1)!)];
        if (base == null ||
            !_usableEntry(base) ||
            _key(base.word) == _key(entry.word)) {
          continue;
        }
        final requiredPart = match.group(2)!.startsWith('複數')
            ? PartOfSpeech.noun
            : PartOfSpeech.verb;
        if (!base.partsOfSpeech.contains(requiredPart)) continue;
        final formParts = <PartOfSpeech>{
          requiredPart,
          if (match.group(2)!.contains('分詞')) PartOfSpeech.adjective,
        };
        if (!entry.partsOfSpeech.any(formParts.contains)) continue;
        final clauseStart = entry.meaning.lastIndexOf(
          RegExp(r'[；;\n]'),
          match.start,
        );
        final clauseEnd = entry.meaning.indexOf(RegExp(r'[；;\n]'), match.end);
        final clause = entry.meaning.substring(
          clauseStart + 1,
          clauseEnd < 0 ? entry.meaning.length : clauseEnd,
        );
        final explanation =
            '字典明確標示：${entry.word} 是 ${base.word} 的${match.group(2)}。';
        (index.forms[_key(entry.word)] ??= []).add((
          entry: base,
          explanation: explanation,
          sourceParts: formParts,
          sourceDefinition: clause,
          baseMeaning: base.meaning,
          commonBase: _hasCommonEvidence(base),
        ));
        (index.forms[_key(base.word)] ??= []).add((
          entry: entry,
          explanation: explanation,
          sourceParts: {requiredPart},
          sourceDefinition: base.meaning,
          baseMeaning: base.meaning,
          commonBase: _hasCommonEvidence(base),
        ));
      }
    }
    return index;
  }
}

typedef _FormClue = ({
  BuiltinWordEntry entry,
  String explanation,
  Set<PartOfSpeech> sourceParts,
  String sourceDefinition,
  String baseMeaning,
  bool commonBase,
});

bool _formSenseMatches(String meaning, _FormClue clue) {
  String withoutNotes(String text) =>
      text.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  return meaning
          .split(RegExp(r'[；;\n]'))
          .any((clause) => _key(clause) == _key(clue.sourceDefinition)) ||
      _sameSense(meaning, clue.sourceDefinition) ||
      _sameSense(withoutNotes(meaning), withoutNotes(clue.sourceDefinition)) ||
      _sameSense(withoutNotes(meaning), clue.baseMeaning);
}

typedef _NegationClue = ({
  BuiltinWordEntry entry,
  String sourceSense,
  String explanation,
});

const _negativePrefixes = ['non', 'un', 'in', 'im', 'il', 'ir', 'dis'];
const _negators = ['不', '非', '無', '沒有', '不是'];

final _formPattern = RegExp(
  r"\b([a-z][a-z'-]*)\s*的\s*(複數(?:形式)?|過去式|過去分詞|現在分詞)",
  caseSensitive: false,
);
final _cjk = RegExp(r'[\u3400-\u9fff]');
final _english = RegExp(r'[a-zA-Z]');
final _pollution = RegExp(r'<[^>]*>|https?://|\[\[|\{\{');
const _genericSenses = {
  '人名',
  '地名',
  '姓氏',
  '男性名字',
  '女性名字',
  '一種植物',
  '一種動物',
  '某種事物',
  '其他',
  '未知',
  '待補充',
  '未提供',
};

String _key(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
bool _cleanText(String text) => !_pollution.hasMatch(text);
bool _usableExample(String text) =>
    _cleanText(text) && _english.hasMatch(text) && _cjk.hasMatch(text);
bool _usableEntry(BuiltinWordEntry entry) =>
    entry.meaning.trim().isNotEmpty &&
    _cleanText(entry.meaning) &&
    !_unreliableMeaning.hasMatch(entry.meaning) &&
    entry.sentences.any(_usableExample);

// Commas can be either gloss lists or ordinary definition prose. A word
// merely mentioned inside a definition is not an independent sense.
final _unreliableMeaning = RegExp(r'疑似非標準|應再查證|需要查證|待補充|尚未提供');
final _definitionProse = RegExp(r'或|其中|包括|例如|以及|具有|中的|形式|狀態|地區');

Set<String> _senseKeys(
  String meaning, {
  int minimumLength = 2,
  bool adjective = false,
  List<String>? examples,
}) {
  if (_unreliableMeaning.hasMatch(meaning)) return {};
  final keys = <String>{};
  for (final clause in meaning.split(RegExp(r'[；;\n]'))) {
    final text = clause.trim().replaceAll(RegExp(r'[。.!！?？：:]+$'), '').trim();
    final pieces = text.split(RegExp(r'[，,、]'));
    final fromList = pieces.length > 1;
    if (fromList &&
        (text.length > 24 ||
            pieces.length > 4 ||
            _definitionProse.hasMatch(text) ||
            pieces.any(
              (piece) =>
                  !RegExp(r'^[\u3400-\u9fff]{1,12}$').hasMatch(piece.trim()),
            ))) {
      continue;
    }
    for (final piece in pieces) {
      var sense = piece.trim();
      if (adjective && sense.endsWith('的') && sense.length > 2) {
        sense = sense.substring(0, sense.length - 1);
      }
      if (sense.length < minimumLength ||
          sense.length > 12 ||
          !RegExp(r'^[\u3400-\u9fff]+$').hasMatch(sense) ||
          _genericSenses.contains(sense)) {
        continue;
      }
      if (fromList &&
          examples != null &&
          !examples.any(
            (example) => _usableExample(example) && example.contains(sense),
          )) {
        continue;
      }
      keys.add(sense);
    }
  }
  return keys;
}

bool _sameSense(String a, String b, {bool adjective = false}) {
  if (a.trim().isEmpty || b.trim().isEmpty) return false;
  if (_key(a) == _key(b)) return true;
  return _senseKeys(a, minimumLength: 1, adjective: adjective)
      .intersection(_senseKeys(b, minimumLength: 1, adjective: adjective))
      .isNotEmpty;
}

// These are curriculum signals, not a claim that the dictionary has frequency
// counts. Unrated words remain eligible through explicitly reviewed relations.
bool _hasCommonEvidence(BuiltinWordEntry entry) =>
    (entry.sourceTags.contains(BuiltinSourceTag.twCeec) ||
        entry.sourceTags.contains(BuiltinSourceTag.pdfExamBook)) &&
    (entry.schoolLevels.contains(BuiltinSchoolLevel.elementary) ||
        entry.schoolLevels.contains(BuiltinSchoolLevel.juniorHigh) ||
        (entry.difficultyLevel != null &&
            entry.difficultyLevel! >= 1 &&
            entry.difficultyLevel! <= 4));

final _unsuitableUsage = RegExp(
  r'古語|古體|古用|罕用|罕見用法|罕見詞|生僻|方言|已廢|廢語|過時用法|非標準|'
  r'西班牙語中|法語中|德語中|俄語中|日語中|義大利語中|拉丁語中',
);
final _learningLemma = RegExp(
  r"^[a-z]+(?:['-][a-z]+)*(?: [a-z]+(?:['-][a-z]+)*)*$",
  caseSensitive: false,
);
bool _suitableForLearning(BuiltinWordEntry entry) =>
    _learningLemma.hasMatch(_key(entry.word)) &&
    !_unsuitableUsage.hasMatch(entry.meaning);
