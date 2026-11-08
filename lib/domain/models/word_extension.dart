import 'builtin_word_entry.dart';
import 'word_card.dart';

enum WordRelationKind { related, confused }

/// Explicit links are scoped to the meanings on both ends, and may be traversed
/// in either direction. Explanations name the words rather than assuming order.
class WordRelation {
  const WordRelation({
    required this.sourceWord,
    required this.targetWord,
    required this.sourceSense,
    required this.targetSense,
    required this.kind,
    required this.explanation,
    this.comparisonExample = '',
    this.sourcePartsOfSpeech = const [],
    this.targetPartsOfSpeech = const [],
    this.sourceExample = '',
    this.targetExample = '',
  });

  final String sourceWord;
  final String targetWord;
  final String sourceSense;
  final String targetSense;
  final WordRelationKind kind;
  final String explanation;
  final String comparisonExample;
  final List<PartOfSpeech> sourcePartsOfSpeech;
  final List<PartOfSpeech> targetPartsOfSpeech;
  final String sourceExample;
  final String targetExample;
}

class WordExtensionUsage {
  const WordExtensionUsage({
    required this.description,
    required this.example,
    required this.source,
    this.sense = '',
  });

  final String description;
  final String example;
  final String source;
  final String sense;
}

class WordExtensionRecommendation {
  const WordExtensionRecommendation({
    required this.entry,
    required this.explanation,
    this.comparisonExample = '',
    required this.examples,
  });

  final List<String> examples;
  final BuiltinWordEntry entry;
  final String explanation;
  final String comparisonExample;
}

class WordExtensionResult {
  const WordExtensionResult({
    this.usages = const [],
    this.related = const [],
    this.confused = const [],
  });

  final List<WordExtensionUsage> usages;
  final List<WordExtensionRecommendation> related;
  final List<WordExtensionRecommendation> confused;

  bool get isEmpty => usages.isEmpty && related.isEmpty && confused.isEmpty;
}
