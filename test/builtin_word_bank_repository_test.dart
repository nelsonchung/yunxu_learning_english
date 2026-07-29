import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';

void main() {
  test(
    'empty query only loads enough shards to satisfy the first page',
    () async {
      final bundle = _TrackingWordBankAssetBundle({
        'assets/word_bank/word_bank_main-a.json': [
          _entryMap(word: 'alpha', meaning: '阿爾法'),
          _entryMap(word: 'amber', meaning: '琥珀'),
        ],
        'assets/word_bank/word_bank_main-b.json': [
          _entryMap(word: 'banana', meaning: '香蕉'),
        ],
      });
      final repository = BuiltinWordBankRepository(assetBundle: bundle);

      final result = await repository.search(
        query: '',
        filter: BuiltinWordBankAudienceFilter.all,
        emptyQueryLimit: 1,
      );

      expect(result.entries.map((entry) => entry.word).toList(), ['alpha']);
      expect(bundle.loadedKeys, ['assets/word_bank/word_bank_main-a.json']);
    },
  );

  test(
    'single-character english query only loads the matching shard',
    () async {
      final bundle = _TrackingWordBankAssetBundle({
        'assets/word_bank/word_bank_main-c.json': [
          _entryMap(word: 'cat', meaning: '貓'),
          _entryMap(word: 'cow', meaning: '牛'),
        ],
        'assets/word_bank/word_bank_main-d.json': [
          _entryMap(word: 'dog', meaning: '狗'),
        ],
      });
      final repository = BuiltinWordBankRepository(assetBundle: bundle);

      final result = await repository.search(
        query: 'c',
        filter: BuiltinWordBankAudienceFilter.all,
      );

      expect(result.entries.map((entry) => entry.word).toList(), [
        'cat',
        'cow',
      ]);
      expect(bundle.loadedKeys, ['assets/word_bank/word_bank_main-c.json']);
    },
  );

  test('filter counts are cached after the first load', () async {
    final bundle = _TrackingWordBankAssetBundle({
      'assets/word_bank/word_bank_main-a.json': [
        _entryMap(word: 'apple', meaning: '蘋果', schoolLevels: ['elementary']),
      ],
      'assets/word_bank/word_bank_main-b.json': [
        _entryMap(
          word: 'budget',
          meaning: '預算',
          audienceTags: ['general'],
          examTags: ['toeic'],
        ),
      ],
    });
    final repository = BuiltinWordBankRepository(assetBundle: bundle);

    final first = await repository.fetchFilterCounts();
    final loadedAfterFirstFetch = bundle.loadCount;
    final second = await repository.fetchFilterCounts();

    expect(first[BuiltinWordBankAudienceFilter.all], 2);
    expect(first[BuiltinWordBankAudienceFilter.elementary], 1);
    expect(first[BuiltinWordBankAudienceFilter.general], 1);
    expect(first[BuiltinWordBankAudienceFilter.toeic], 1);
    expect(second, first);
    expect(bundle.loadCount, loadedAfterFirstFetch);
  });

  test(
    'recommendation candidates are balanced across shuffled shards',
    () async {
      final entriesByKey = <String, List<Map<String, Object?>>>{};
      for (var letterCode = 97; letterCode <= 122; letterCode += 1) {
        final letter = String.fromCharCode(letterCode);
        entriesByKey['assets/word_bank/word_bank_main-$letter.json'] = [
          for (var index = 0; index < 5; index += 1)
            _entryMap(
              word: '$letter${_alphaSuffix(index)}',
              meaning: '$letter recommendation $index',
            ),
        ];
      }
      final bundle = _TrackingWordBankAssetBundle(entriesByKey);
      final repository = BuiltinWordBankRepository(assetBundle: bundle);

      final candidates = await repository.fetchRecommendationCandidates(
        existingWords: const [],
        now: DateTime(2026, 7, 29),
        desiredCount: 3,
        minimumShardCount: 3,
        candidateLimit: 9,
      );

      final countsByInitial = <String, int>{};
      for (final entry in candidates) {
        final initial = entry.word[0];
        countsByInitial[initial] = (countsByInitial[initial] ?? 0) + 1;
      }

      expect(candidates, hasLength(9));
      expect(countsByInitial, hasLength(3));
      expect(countsByInitial.values, everyElement(3));
      expect(bundle.loadedKeys, hasLength(3));
      expect(bundle.loadedKeys, [
        'assets/word_bank/word_bank_main-g.json',
        'assets/word_bank/word_bank_main-y.json',
        'assets/word_bank/word_bank_main-a.json',
      ]);
    },
  );
}

String _alphaSuffix(int index) {
  return String.fromCharCodes([97 + (index ~/ 26), 97 + (index % 26), 97]);
}

class _TrackingWordBankAssetBundle extends CachingAssetBundle {
  _TrackingWordBankAssetBundle(this._entriesByKey);

  final Map<String, List<Map<String, Object?>>> _entriesByKey;
  final List<String> loadedKeys = <String>[];
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    loadCount += 1;
    final payload = jsonEncode(_entriesByKey[key] ?? const <Object?>[]);
    final bytes = Uint8List.fromList(utf8.encode(payload));
    return ByteData.view(bytes.buffer);
  }
}

Map<String, Object?> _entryMap({
  required String word,
  required String meaning,
  List<String> schoolLevels = const ['seniorHigh'],
  List<String> examTags = const [],
  List<String> audienceTags = const [],
}) {
  return {
    'word': word,
    'meaning': meaning,
    'partOfSpeech': 'noun',
    'sentences': [
      'This is a sample sentence for $word.',
      'We use $word again in a second sentence.',
    ],
    'sourcePage': 1,
    'schoolLevels': schoolLevels,
    'examTags': examTags,
    'audienceTags': audienceTags,
    'sourceTags': ['twCeec'],
    'difficultyLevel': 1,
  };
}
