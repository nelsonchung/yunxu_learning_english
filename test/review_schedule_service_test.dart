import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';

void main() {
  final service = ReviewScheduleService();

  test('marked mastered cards are excluded from due review', () {
    final now = DateTime(2026, 4, 12, 10);
    final card = _card(nextReviewDate: now.subtract(const Duration(days: 1)));

    final mastered = service.markMastered(card, now);

    expect(mastered.isMastered, isTrue);
    expect(service.isDueOnOrBefore(mastered, now), isFalse);
  });

  test('resumeReview re-enables due review using existing schedule state', () {
    final now = DateTime(2026, 4, 12, 10);
    final card = _card(
      nextReviewDate: now.subtract(const Duration(days: 1)),
      reviewState: WordReviewState.mastered,
      masteredAt: now.subtract(const Duration(hours: 1)),
    );

    final resumed = service.resumeReview(card);

    expect(resumed.isMastered, isFalse);
    expect(resumed.masteredAt, isNull);
    expect(service.isDueOnOrBefore(resumed, now), isTrue);
  });
}

WordCard _card({
  required DateTime nextReviewDate,
  WordReviewState reviewState = WordReviewState.active,
  DateTime? masteredAt,
}) {
  final createdAt = DateTime(2026, 4, 1);
  return WordCard(
    id: 'word-1',
    word: 'steady',
    meaning: '穩定的',
    partOfSpeech: PartOfSpeech.adjective,
    sentences: const ['steady progress'],
    origin: WordOrigin.manual,
    createdAt: createdAt,
    updatedAt: createdAt,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: nextReviewDate,
    history: const [],
    isDeleted: false,
    reviewState: reviewState,
    masteredAt: masteredAt,
  );
}
