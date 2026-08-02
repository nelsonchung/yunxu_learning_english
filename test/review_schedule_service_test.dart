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

  test('forgot resets progress and schedules tomorrow', () {
    final now = DateTime(2026, 4, 12, 10);
    final reviewed = service.recordReview(
      _card(
        nextReviewDate: now.subtract(const Duration(days: 5)),
        nextReviewIndex: 2,
      ),
      ReviewRating.forgot,
      now,
    );

    expect(reviewed.nextReviewIndex, 0);
    expect(reviewed.nextReviewDate, now.add(const Duration(days: 1)));
    expect(reviewed.history, [now]);
    expect(reviewed.reviewRatings, [ReviewRating.forgot]);
  });

  test('hard keeps the stage and shortens its interval', () {
    final now = DateTime(2026, 4, 12, 10);
    final reviewed = service.recordReview(
      _card(nextReviewDate: now, nextReviewIndex: 2),
      ReviewRating.hard,
      now,
    );

    expect(reviewed.nextReviewIndex, 2);
    expect(reviewed.nextReviewDate, now.add(const Duration(days: 1)));
    expect(reviewed.reviewRatings, [ReviewRating.hard]);
  });

  test('good advances one stage from the actual review time', () {
    final now = DateTime(2026, 4, 12, 10);
    final reviewed = service.recordReview(
      _card(nextReviewDate: now.subtract(const Duration(days: 20))),
      ReviewRating.good,
      now,
    );

    expect(reviewed.nextReviewIndex, 1);
    expect(reviewed.nextReviewDate, now.add(const Duration(days: 1)));
    expect(reviewed.reviewRatings, [ReviewRating.good]);
  });

  test('easy skips one stage without marking the card mastered', () {
    final now = DateTime(2026, 4, 12, 10);
    final reviewed = service.recordReview(
      _card(nextReviewDate: now),
      ReviewRating.easy,
      now,
    );

    expect(reviewed.nextReviewIndex, 2);
    expect(reviewed.nextReviewDate, now.add(const Duration(days: 2)));
    expect(reviewed.reviewRatings, [ReviewRating.easy]);
    expect(reviewed.isMastered, isFalse);
  });

  test('good at the last stage completes the schedule', () {
    final now = DateTime(2026, 4, 12, 10);
    final reviewed = service.recordReview(
      _card(nextReviewDate: now, nextReviewIndex: 2),
      ReviewRating.good,
      now,
    );

    expect(reviewed.nextReviewIndex, 3);
    expect(reviewed.hasCompletedReviewSchedule, isTrue);
    expect(reviewed.reviewRatings, [ReviewRating.good]);
  });
}

WordCard _card({
  required DateTime nextReviewDate,
  WordReviewState reviewState = WordReviewState.active,
  DateTime? masteredAt,
  int nextReviewIndex = 0,
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
    nextReviewIndex: nextReviewIndex,
    nextReviewDate: nextReviewDate,
    history: const [],
    isDeleted: false,
    reviewState: reviewState,
    masteredAt: masteredAt,
  );
}
