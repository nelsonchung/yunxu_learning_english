import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';

void main() {
  test('WordCard preserves origin through toMap/fromMap', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
    final card = WordCard(
      id: 'word-1',
      word: 'inspiration',
      meaning: '靈感',
      memoryHint: '想到一盞燈突然亮起，靈感就來了。',
      partOfSpeech: PartOfSpeech.noun,
      sentences: const ['This idea gave me inspiration.'],
      origin: WordOrigin.manual,
      createdAt: now,
      updatedAt: now,
      reviewSchedule: const [1, 2, 3],
      nextReviewIndex: 0,
      nextReviewDate: now,
      history: const [],
      isDeleted: false,
      customTags: const ['課本A 第3課', '期中考', '課本A 第3課'],
      reviewState: WordReviewState.mastered,
      masteredAt: now,
    );

    final restored = WordCard.fromMap(card.toMap());

    expect(restored.origin, WordOrigin.manual);
    expect(restored.word, 'inspiration');
    expect(restored.memoryHint, '想到一盞燈突然亮起，靈感就來了。');
    expect(restored.customTags, ['課本A 第3課', '期中考']);
    expect(restored.reviewState, WordReviewState.mastered);
    expect(restored.masteredAt, now);
  });

  test('WordCard defaults missing origin to unknown', () {
    final restored = WordCard.fromMap({
      'id': 'word-2',
      'word': 'archive',
      'meaning': '存檔',
      'partOfSpeech': 'verb',
      'sentences': ['Please archive the file.'],
      'createdAt': 1_700_000_000_000,
      'updatedAt': 1_700_000_000_000,
      'reviewSchedule': [1, 2, 3],
      'nextReviewIndex': 0,
      'nextReviewDate': 1_700_000_000_000,
      'history': const [],
      'isDeleted': false,
    });

    expect(restored.origin, WordOrigin.unknown);
    expect(restored.memoryHint, isEmpty);
    expect(restored.customTags, isEmpty);
    expect(restored.reviewState, WordReviewState.active);
    expect(restored.masteredAt, isNull);
  });
}
