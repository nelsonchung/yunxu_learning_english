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

  test('WordCard preserves aligned review ratings through toMap/fromMap', () {
    final first = DateTime(2026, 8, 1, 10);
    final second = DateTime(2026, 8, 2, 10);
    final card = WordCard(
      id: 'rated-word',
      word: 'resilient',
      meaning: '有韌性的',
      partOfSpeech: PartOfSpeech.adjective,
      sentences: const ['She remained resilient.'],
      origin: WordOrigin.manual,
      createdAt: first,
      updatedAt: second,
      reviewSchedule: const [1, 2, 3],
      nextReviewIndex: 1,
      nextReviewDate: second,
      history: [first, second],
      reviewRatings: const [ReviewRating.hard, ReviewRating.good],
      isDeleted: false,
    );

    final restored = WordCard.fromMap(card.toMap());

    expect(restored.reviewRatings, [ReviewRating.hard, ReviewRating.good]);
    expect(restored.alignedReviewRatings, [
      ReviewRating.hard,
      ReviewRating.good,
    ]);
  });

  test('legacy and unknown review ratings become unrated', () {
    final restored = WordCard.fromMap({
      'id': 'legacy-word',
      'word': 'legacy',
      'history': [1_700_000_000_000, 1_700_086_400_000],
      'reviewRatings': ['unknown-value'],
      'reviewSchedule': const [],
    });

    expect(restored.alignedReviewRatings, [
      ReviewRating.unrated,
      ReviewRating.unrated,
    ]);
    expect(restored.reviewSchedule, [1, 2, 3, 5, 8, 13, 21, 39]);
  });

  test('older clients append unrated history after existing ratings', () {
    final restored = WordCard.fromMap({
      'id': 'mixed-version-word',
      'word': 'compatibility',
      'history': [1_700_000_000_000, 1_700_086_400_000, 1_700_172_800_000],
      'reviewRatings': ['good'],
      'reviewSchedule': [1, 2, 3],
    });

    expect(restored.alignedReviewRatings, [
      ReviewRating.good,
      ReviewRating.unrated,
      ReviewRating.unrated,
    ]);
  });

  test('mastered and completed cards are not marked difficult', () {
    final baseMap = <String, Object?>{
      'id': 'finished-word',
      'word': 'finished',
      'history': [1_700_000_000_000, 1_700_086_400_000],
      'reviewRatings': ['forgot', 'hard'],
      'reviewSchedule': [1, 2, 3],
      'nextReviewIndex': 0,
    };

    final mastered = WordCard.fromMap({
      ...baseMap,
      'reviewState': 'mastered',
      'masteredAt': 1_700_086_400_000,
    });
    final completed = WordCard.fromMap({...baseMap, 'nextReviewIndex': 3});

    expect(mastered.isDifficult, isFalse);
    expect(completed.isDifficult, isFalse);
  });

  test('困難單字連續記得兩次後會退出困難清單', () {
    final now = DateTime(2026, 8, 2);
    final card = WordCard.fromMap({
      'id': 'improving-word',
      'word': 'improving',
      'history': [
        now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ],
      'reviewRatings': ['forgot', 'hard', 'good', 'good'],
      'reviewSchedule': [1, 2, 3, 5, 8],
      'nextReviewIndex': 2,
      'nextReviewDate': now.millisecondsSinceEpoch,
    });

    expect(card.isDifficult, isFalse);
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
    expect(restored.reviewRatings, isEmpty);
  });
}
