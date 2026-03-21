import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';

void main() {
  test('BuiltinWordEntry joins list-based meaning instead of throwing', () {
    final entry = BuiltinWordEntry.fromMap({
      'word': 'apophyge',
      'meaning': ['【建】（柱頂或柱腳處的）凹曲線'],
      'partOfSpeech': 'noun',
      'sentences': const [
        'The apophyge connects the shaft of the column to its base.',
        'Greek architecture features elegant apophyges in columns.',
      ],
      'audienceTags': const ['general'],
    });

    expect(entry.word, 'apophyge');
    expect(entry.meaning, '【建】（柱頂或柱腳處的）凹曲線');
    expect(entry.partOfSpeech, PartOfSpeech.noun);
    expect(entry.sentences, hasLength(2));
  });

  test('BuiltinWordEntry preserves string meaning', () {
    final entry = BuiltinWordEntry.fromMap({
      'word': 'ambulatory',
      'meaning': '流動的；步行的',
      'partOfSpeech': 'adjective',
      'sentences': const [
        'The report describes the result as ambulatory.',
        'The patient remained ambulatory after the treatment.',
      ],
    });

    expect(entry.meaning, '流動的；步行的');
    expect(entry.partOfSpeech, PartOfSpeech.adjective);
  });
}
