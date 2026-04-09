import '../models/builtin_word_entry.dart';

class WordBankSearchService {
  const WordBankSearchService();

  static final RegExp _collapsedWhitespacePattern = RegExp(r'\s+');
  static final RegExp _meaningLooseMatchPattern = RegExp(
    r'[\s，。；：、（）()「」『』《》〈〉【】〔〕［］｛｝,.;:!?！？]',
  );
  static final Expando<String> _normalizedWordCache = Expando<String>(
    'normalizedWord',
  );
  static final Expando<String> _normalizedMeaningCache = Expando<String>(
    'normalizedMeaning',
  );
  static final Expando<String> _relaxedMeaningCache = Expando<String>(
    'relaxedMeaning',
  );

  void prime(Iterable<BuiltinWordEntry> entries) {
    for (final entry in entries) {
      _normalizedWordFor(entry);
      _normalizedMeaningFor(entry);
      _relaxedMeaningFor(entry);
    }
  }

  List<BuiltinWordEntry> search({
    required Iterable<BuiltinWordEntry> entries,
    required String query,
    int emptyQueryLimit = 100,
    int queryLimit = 200,
    int minContainsQueryLength = 2,
    int minMeaningQueryLength = 2,
  }) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return entries.take(emptyQueryLimit).toList(growable: false);
    }
    final queryLength = normalizedQuery.runes.length;
    final canUseContains = queryLength >= minContainsQueryLength;
    final canUseMeaning = queryLength >= minMeaningQueryLength;
    final relaxedMeaningQuery = canUseMeaning
        ? _normalizeMeaningText(query)
        : '';

    final exactMatches = <BuiltinWordEntry>[];
    final prefixMatches = <BuiltinWordEntry>[];
    final containsMatches = <BuiltinWordEntry>[];
    final meaningMatches = <BuiltinWordEntry>[];

    for (final entry in entries) {
      final normalizedWord = _normalizedWordFor(entry);

      if (normalizedWord == normalizedQuery) {
        exactMatches.add(entry);
        continue;
      }
      if (normalizedWord.startsWith(normalizedQuery)) {
        prefixMatches.add(entry);
        continue;
      }
      if (canUseContains && normalizedWord.contains(normalizedQuery)) {
        containsMatches.add(entry);
        continue;
      }
      if (canUseMeaning &&
          (_normalizedMeaningFor(entry).contains(normalizedQuery) ||
              (relaxedMeaningQuery.isNotEmpty &&
                  _relaxedMeaningFor(entry).contains(relaxedMeaningQuery)))) {
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
      (a, b) => _normalizedWordFor(a).compareTo(_normalizedWordFor(b)),
    );
  }

  String _normalizedWordFor(BuiltinWordEntry entry) {
    final cached = _normalizedWordCache[entry];
    if (cached != null) {
      return cached;
    }
    final normalized = _normalizeSearchText(entry.word);
    _normalizedWordCache[entry] = normalized;
    return normalized;
  }

  String _normalizedMeaningFor(BuiltinWordEntry entry) {
    final cached = _normalizedMeaningCache[entry];
    if (cached != null) {
      return cached;
    }
    final normalized = _normalizeSearchText(entry.meaning);
    _normalizedMeaningCache[entry] = normalized;
    return normalized;
  }

  String _relaxedMeaningFor(BuiltinWordEntry entry) {
    final cached = _relaxedMeaningCache[entry];
    if (cached != null) {
      return cached;
    }
    final normalized = _normalizeMeaningText(entry.meaning);
    _relaxedMeaningCache[entry] = normalized;
    return normalized;
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
