import '../models/builtin_word_entry.dart';

class WordBankSearchService {
  const WordBankSearchService();

  List<BuiltinWordEntry> search({
    required Iterable<BuiltinWordEntry> entries,
    required String query,
    int emptyQueryLimit = 100,
    int queryLimit = 200,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return entries.take(emptyQueryLimit).toList(growable: false);
    }

    final exactMatches = <BuiltinWordEntry>[];
    final prefixMatches = <BuiltinWordEntry>[];
    final containsMatches = <BuiltinWordEntry>[];
    final meaningMatches = <BuiltinWordEntry>[];

    for (final entry in entries) {
      final normalizedWord = entry.word.toLowerCase();
      final normalizedMeaning = entry.meaning.toLowerCase();

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
      if (normalizedMeaning.contains(normalizedQuery)) {
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
      (a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()),
    );
  }
}
