import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/models/word_extension.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';
import 'package:yunxu_learning_english/domain/services/common_word_relations.dart';

// The sample is declared before inspecting outputs. Empty results are recorded,
// not removed or treated as successful relationship recommendations.
const samples = <String, List<String>>{
  '日常名詞': [
    'dog',
    'cat',
    'house',
    'garden',
    'book',
    'water',
    'music',
    'apple',
    'table',
    'river',
    'city',
    'food',
    'school',
    'train',
    'friend',
    'family',
    'money',
    'time',
    'idea',
    'road',
  ],
  '形容詞': [
    'beautiful',
    'tiny',
    'large',
    'clever',
    'smart',
    'silent',
    'quiet',
    'ordinary',
    'rare',
    'careful',
    'careless',
    'quick',
  ],
  '複合字': [
    'snowman',
    'bookcase',
    'raincoat',
    'bookshelf',
    'teapot',
    'toothbrush',
    'football',
    'sunflower',
    'bedroom',
    'keyboard',
    'railway',
    'moonlight',
    'schoolbag',
    'waterfall',
    'sunrise',
    'sunset',
    'seashore',
    'homework',
    'snowball',
  ],
  '前綴字': [
    'unhappy',
    'unfair',
    'unhealthy',
    'unclear',
    'uncertain',
    'unable',
    'impossible',
    'irregular',
    'illegal',
    'dishonest',
    'nonverbal',
    'harmless',
  ],
  '變化形': [
    'children',
    'mice',
    'went',
    'gone',
    'took',
    'taken',
    'gave',
    'given',
    'seen',
    'saw',
    'wrote',
    'written',
    'feet',
    'teeth',
    'men',
    'women',
    'ran',
    'kept',
    'ate',
    'eaten',
    'slept',
    'spoke',
    'spoken',
    'sung',
  ],
  '多義字': [
    'bank',
    'spring',
    'bat',
    'light',
    'kind',
    'right',
    'match',
    'present',
    'lead',
    'wind',
    'read',
    'milk',
  ],
  '副詞': ['quickly', 'slowly', 'happily', 'easily'],
  '拼字陷阱': [
    'carpet',
    'butterfly',
    'pineapple',
    'hamburger',
    'understand',
    'uncle',
    'inflammable',
    'invaluable',
    'nonplus',
    'union',
  ],
  '多字詞條': ['in front of', 'look after', 'give up', 'take care of'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, BuiltinWordEntry> byWord;
  late WordExtensionService service;
  final results = <Map<String, Object?>>[];
  var loads = 0;

  setUpAll(() async {
    final entries = await BuiltinWordBankRepository().fetchAll();
    byWord = {};
    for (final entry in entries) {
      byWord.putIfAbsent(entry.word.trim().toLowerCase(), () => entry);
    }
    service = WordExtensionService(
      loadEntries: () async {
        loads++;
        return entries;
      },
    );
  });

  tearDownAll(() async {
    expect(loads, 1, reason: 'All samples share one dictionary index');
    const path = String.fromEnvironment('WORD_EXTENSION_AUDIT_PATH');
    if (path.isNotEmpty) {
      await File(path).writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert({'dictionaryWords': byWord.length, 'results': results}),
      );
    }
  });

  for (final category in samples.entries) {
    test('實際字庫抽樣：${category.key}', () async {
      for (final word in category.value) {
        final entry = byWord[word];
        if (entry == null) {
          results.add({
            'category': category.key,
            'word': word,
            'status': 'missing',
          });
          continue;
        }
        final result = await service.recommend(_card(entry));
        _checkResult(word, result, byWord);
        results.add({
          'category': category.key,
          'word': word,
          'meaning': entry.meaning,
          'parts': entry.partsOfSpeech.map((part) => part.name).toList(),
          'status': result.related.isNotEmpty || result.confused.isNotEmpty
              ? 'relationships'
              : result.usages.isNotEmpty
              ? 'examples_only'
              : 'empty',
          'usageCount': result.usages.length,
          'related': result.related.map(_describe).toList(),
          'confused': result.confused.map(_describe).toList(),
        });
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('新增常用字關係的兩端都與實際字庫相符，且正反向可找到', () async {
    for (final relation in commonWordRelations) {
      expect(relation.sourcePartsOfSpeech, isNotEmpty);
      expect(relation.targetPartsOfSpeech, isNotEmpty);
      expect(relation.sourceExample, isNotEmpty);
      expect(relation.targetExample, isNotEmpty);
      for (final pair in [
        (relation.sourceWord, relation.targetWord),
        (relation.targetWord, relation.sourceWord),
      ]) {
        final entry = byWord[pair.$1];
        expect(entry, isNotNull, reason: pair.$1);
        final result = await service.recommend(_card(entry!));
        _checkResult(pair.$1, result, byWord);
        final group = relation.kind == WordRelationKind.confused
            ? result.confused
            : result.related;
        expect(
          group.map((item) => item.entry.word.toLowerCase()),
          contains(pair.$2),
          reason: '${pair.$1} → ${pair.$2}',
        );
        final selected = group.singleWhere(
          (item) => item.entry.word.toLowerCase() == pair.$2,
        );
        expect(selected.examples, [
          pair.$1 == relation.sourceWord
              ? relation.targetExample
              : relation.sourceExample,
        ]);
      }
    }
  });

  test('實際字庫的生僻或未核實字不因相同釋義就推薦', () async {
    for (final pair in [
      ('beautiful', 'lindo'),
      ('quick', 'rapic'),
      ('food', 'victuals'),
      ('time', 'openning time'),
      ('bank', 'obey bank balance'),
      ('apple', 'protogyny'),
    ]) {
      final result = await service.recommend(_card(byWord[pair.$1]!));
      expect(
        [
          ...result.related,
          ...result.confused,
        ].map((item) => item.entry.word.toLowerCase()),
        isNot(contains(pair.$2)),
        reason: '${pair.$1} → ${pair.$2}',
      );
    }
  });

  test('跨類型的新字應有指定的實際字庫證據，不只檢查非空', () async {
    for (final pair in [
      ('bookcase', 'book'),
      ('raincoat', 'rain'),
      ('teapot', 'tea'),
      ('unfair', 'fair'),
      ('unhealthy', 'healthy'),
      ('impossible', 'possible'),
      ('went', 'go'),
      ('gave', 'give'),
      ('written', 'write'),
    ]) {
      final entry = byWord[pair.$1];
      expect(entry, isNotNull, reason: pair.$1);
      final result = await service.recommend(_card(entry!));
      expect(
        result.related.map((item) => item.entry.word.toLowerCase()),
        contains(pair.$2),
        reason: '${pair.$1} → ${pair.$2}',
      );
    }
  });

  test('實際字庫不應將不可成立的拼字拆解標為關係', () async {
    for (final pair in [
      ('carpet', 'car'),
      ('carpet', 'pet'),
      ('butterfly', 'butter'),
      ('pineapple', 'pine'),
      ('uncle', 'cle'),
    ]) {
      final result = await service.recommend(_card(byWord[pair.$1]!));
      expect(
        [
          ...result.related,
          ...result.confused,
        ].map((item) => item.entry.word.toLowerCase()),
        isNot(contains(pair.$2)),
        reason: '${pair.$1} must not imply ${pair.$2}',
      );
    }
    final inflammable = await service.recommend(_card(byWord['inflammable']!));
    expect(
      inflammable.related
          .where((item) => item.entry.word.toLowerCase() == 'flammable')
          .any((item) => item.explanation.contains('否定前綴')),
      isFalse,
    );
  });

  test('自訂字可用本身釋義找字庫，無依據時保留空結果', () async {
    final custom = _card(byWord['clever']!).copyWith(word: 'my-custom-term');
    final result = await service.recommend(custom);
    _checkResult(custom.word, result, byWord);
    expect(result.related, isNotEmpty);
    final absent = await service.recommend(
      custom.copyWith(
        word: 'zz-no-dictionary-evidence',
        meaning: '未收錄的私人代號',
        sentences: const [],
      ),
    );
    expect(absent.isEmpty, isTrue);
  });
}

Map<String, Object?> _describe(WordExtensionRecommendation item) => {
  'word': item.entry.word,
  'meaning': item.entry.meaning,
  'parts': item.entry.partsOfSpeech.map((part) => part.name).toList(),
  'reason': item.explanation,
};

void _checkResult(
  String word,
  WordExtensionResult result,
  Map<String, BuiltinWordEntry> byWord,
) {
  expect(result.usages.length, lessThanOrEqualTo(2), reason: word);
  expect(result.related.length, lessThanOrEqualTo(3), reason: word);
  expect(result.confused.length, lessThanOrEqualTo(2), reason: word);
  final targets = <String>{};
  for (final item in [...result.related, ...result.confused]) {
    final key = item.entry.word.trim().toLowerCase();
    expect(key, isNot(word.trim().toLowerCase()), reason: word);
    expect(byWord.containsKey(key), isTrue, reason: '$word → $key');
    expect(targets.add(key), isTrue, reason: 'duplicate $word → $key');
    expect(item.explanation.trim(), isNotEmpty, reason: '$word → $key');
    expect(item.examples, isNotEmpty, reason: '$word → $key');
    for (final example in item.examples) {
      expect(example, matches(RegExp(r'[a-zA-Z]')), reason: '$word → $key');
      expect(
        example,
        matches(RegExp(r'[\u3400-\u9fff]')),
        reason: '$word → $key',
      );
      expect(
        item.entry.sentences,
        contains(example),
        reason: 'not a fabricated example',
      );
    }
  }
}

WordCard _card(BuiltinWordEntry entry) {
  final now = DateTime(2026);
  return WordCard(
    id: entry.word,
    word: entry.word,
    meaning: entry.meaning,
    partsOfSpeech: entry.partsOfSpeech,
    sentences: const [],
    origin: WordOrigin.builtinWordBank,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now,
    history: const [],
    isDeleted: false,
  );
}
