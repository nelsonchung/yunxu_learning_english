import '../models/builtin_word_entry.dart';

class WordBankSearchService {
  const WordBankSearchService();

  static final RegExp _collapsedWhitespacePattern = RegExp(r'\s+');
  static final RegExp _meaningLooseMatchPattern = RegExp(
    r'[\s，。；：、（）()「」『』《》〈〉【】〔〕［］｛｝,.;:!?！？]',
  );

  List<BuiltinWordEntry> search({
    required Iterable<BuiltinWordEntry> entries,
    required String query,
    int emptyQueryLimit = 100,
    int queryLimit = 200,
  }) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return entries.take(emptyQueryLimit).toList(growable: false);
    }
    final relaxedMeaningQuery = _normalizeMeaningText(query);

    final exactMatches = <BuiltinWordEntry>[];
    final prefixMatches = <BuiltinWordEntry>[];
    final containsMatches = <BuiltinWordEntry>[];
    final meaningMatches = <BuiltinWordEntry>[];

    for (final entry in entries) {
      final normalizedWord = _normalizeSearchText(entry.word);
      final normalizedMeaning = _normalizeSearchText(entry.meaning);

      if (normalizedWord == normalizedQuery) {
        exactMatches.add(entry);
        continue;
      }
      if (normalizedWord.startsWith(normalizedQuery)) {
        prefixMatches.add(entry);
        continue;
      }
      if (normalizedWord.contains(normalizedQuery)) {
        containsMatches.add(entry);
        continue;
      }
      if (normalizedMeaning.contains(normalizedQuery) ||
          (relaxedMeaningQuery.isNotEmpty &&
              _normalizeMeaningText(
                entry.meaning,
              ).contains(relaxedMeaningQuery))) {
        meaningMatches.add(entry);
      }
    }

    _sortAlphabetically(exactMatches);
    _sortAlphabetically(prefixMatches);
    _sortAlphabetically(containsMatches);
    _sortAlphabetically(meaningMatches);

    return <BuiltinWordEntry>[
      ...exactMatches,
      ...prefixMatches,
      ...containsMatches,
      ...meaningMatches,
    ].take(queryLimit).toList(growable: false);
  }

  void _sortAlphabetically(List<BuiltinWordEntry> entries) {
    entries.sort(
      (a, b) =>
          _normalizeSearchText(a.word).compareTo(_normalizeSearchText(b.word)),
    );
  }

  String _normalizeSearchText(String value) {
    final normalizedWhitespace = value.replaceAll('\u3000', ' ');
    return normalizedWhitespace
        .trim()
        .replaceAll(_collapsedWhitespacePattern, ' ')
        .toLowerCase();
  }

  String _normalizeMeaningText(String value) {
    return _normalizeSearchText(
      value,
    ).replaceAll(_meaningLooseMatchPattern, '');
  }
}
