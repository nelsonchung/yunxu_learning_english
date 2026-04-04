import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/word_bank_search_service.dart';

void main() {
  const service = WordBankSearchService();

  test('prioritizes exact and prefix matches before contains matches', () {
    final entries = [
      _entry(word: 'commoney'),
      _entry(word: 'baldmoney'),
      _entry(word: 'moneybag'),
      _entry(word: 'money'),
    ];

    final results = service.search(entries: entries, query: 'money');

    expect(results.map((entry) => entry.word).toList(), [
      'money',
      'moneybag',
      'baldmoney',
      'commoney',
    ]);
  });

  test('places meaning matches after word matches', () {
    final entries = [
      _entry(word: 'cashbox'),
      _entry(word: 'wallet', meaning: 'money bag'),
      _entry(word: 'moneyless'),
    ];

    final results = service.search(entries: entries, query: 'money');

    expect(results.map((entry) => entry.word).toList(), [
      'moneyless',
      'wallet',
    ]);
  });

  test('matches Chinese query against meaning', () {
    final entries = [
      _entry(word: 'naan', meaning: '在泥爐中烘烤的圓形扁平麵包，在南亞和中亞美食中很受歡迎。'),
      _entry(word: 'neutral'),
    ];

    final results = service.search(entries: entries, query: '麵包');

    expect(results.map((entry) => entry.word).toList(), ['naan']);
  });

  test(
    'normalizes full-width whitespace and punctuation for meaning matches',
    () {
      final entries = [
        _entry(word: 'N', meaning: '中性（性別）的縮寫。'),
        _entry(word: 'nature'),
      ];

      final results = service.search(entries: entries, query: '  中性　性別  ');

      expect(results.map((entry) => entry.word).toList(), ['N']);
    },
  );

  test('keeps empty query limit behavior', () {
    final entries = [
      _entry(word: 'alpha'),
      _entry(word: 'beta'),
      _entry(word: 'gamma'),
    ];

    final results = service.search(
      entries: entries,
      query: '',
      emptyQueryLimit: 2,
    );

    expect(results.map((entry) => entry.word).toList(), ['alpha', 'beta']);
  });
}

BuiltinWordEntry _entry({required String word, String meaning = 'meaning'}) {
  return BuiltinWordEntry(
    word: word,
    meaning: meaning,
    partOfSpeech: PartOfSpeech.noun,
    sentences: const [],
    sourcePage: 0,
    schoolLevels: const [],
    examTags: const [],
    audienceTags: const [],
    sourceTags: const [],
  );
}
