import 'package:flutter/foundation.dart';

import '../models/builtin_word_entry.dart';
import '../models/word_card.dart';

enum WordBankMatchStatus { matched, notFound, ambiguous, ineligible }

class WordBankComparison {
  WordBankComparison({required WordCard card, required this.status, this.entry})
    : card = card.copyWith(sentences: List.unmodifiable(card.sentences));

  final WordCard card;
  final WordBankMatchStatus status;
  final BuiltinWordEntry? entry;

  bool get meaningChanged =>
      entry != null && card.meaning.trim() != entry!.meaning.trim();
  bool get sentencesChanged =>
      entry != null &&
      !listEquals(
        WordBankRefreshService.cleanSentences(card.sentences),
        WordBankRefreshService.cleanSentences(entry!.sentences),
      );
  bool get partsOfSpeechChanged =>
      entry != null && !listEquals(card.partsOfSpeech, entry!.partsOfSpeech);
  bool get hasChanges =>
      meaningChanged || sentencesChanged || partsOfSpeechChanged;

  bool matchesContent(WordCard current) =>
      current.id == card.id &&
      current.word == card.word &&
      current.origin == card.origin &&
      current.meaning == card.meaning &&
      listEquals(current.sentences, card.sentences) &&
      listEquals(current.partsOfSpeech, card.partsOfSpeech);
}

class WordBankRefreshService {
  const WordBankRefreshService({required this.lookup});

  final Future<List<BuiltinWordEntry>> Function(String word) lookup;

  static String wordKey(String word) => word.trim().toLowerCase();

  static List<String> cleanSentences(Iterable<String> sentences) => sentences
      .map((sentence) => sentence.trim())
      .where((sentence) => sentence.isNotEmpty)
      .toList(growable: false);

  Future<WordBankComparison> compare(WordCard card) async {
    if (card.isDeleted || card.origin != WordOrigin.builtinWordBank) {
      return WordBankComparison(
        card: card,
        status: WordBankMatchStatus.ineligible,
      );
    }
    final key = wordKey(card.word);
    final matches = (await lookup(
      card.word,
    )).where((entry) => wordKey(entry.word) == key).toList(growable: false);
    if (matches.length != 1) {
      return WordBankComparison(
        card: card,
        status: matches.isEmpty
            ? WordBankMatchStatus.notFound
            : WordBankMatchStatus.ambiguous,
      );
    }
    return WordBankComparison(
      card: card,
      entry: matches.single,
      status: WordBankMatchStatus.matched,
    );
  }
}
