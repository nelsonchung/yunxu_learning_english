import 'word_card.dart';

class BuiltinWordEntry {
  const BuiltinWordEntry({
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.sentences,
    required this.sourcePage,
  });

  final String word;
  final String meaning;
  final PartOfSpeech partOfSpeech;
  final List<String> sentences;
  final int sourcePage;

  factory BuiltinWordEntry.fromMap(Map<String, dynamic> map) {
    final parsedSentences = (map['sentences'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final rawSourcePage = map['sourcePage'];
    final parsedSourcePage = rawSourcePage is int ? rawSourcePage : 0;

    return BuiltinWordEntry(
      word: (map['word'] as String? ?? '').trim(),
      meaning: (map['meaning'] as String? ?? '').trim(),
      partOfSpeech: _parsePartOfSpeech((map['partOfSpeech'] as String?) ?? ''),
      sentences: parsedSentences,
      sourcePage: parsedSourcePage,
    );
  }

  static PartOfSpeech _parsePartOfSpeech(String raw) {
    final normalized = raw.trim();
    for (final value in PartOfSpeech.values) {
      if (value.name == normalized) {
        return value;
      }
    }
    return PartOfSpeech.other;
  }
}
