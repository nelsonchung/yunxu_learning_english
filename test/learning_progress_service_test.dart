import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/learning_progress_service.dart';

void main() {
  const service = LearningProgressService();

  test('summarizes mastery, reviews, and distinct active days', () {
    final now = DateTime(2026, 8, 2, 20);
    final summary = service.summarize([
      _card(
        id: 'one',
        history: [
          DateTime(2026, 8, 2, 9),
          DateTime(2026, 8, 2, 18),
          DateTime(2026, 7, 31, 8),
        ],
      ),
      _card(
        id: 'two',
        history: [DateTime(2026, 7, 10, 8)],
        reviewState: WordReviewState.mastered,
        masteredAt: DateTime(2026, 8, 1, 12),
      ),
    ], now: now);

    expect(summary.masteredWords, 1);
    expect(summary.totalReviews, 4);
    expect(summary.activeDaysThisWeek, 3);
    expect(summary.activeDaysLast30, 4);
    expect(summary.latestActivityAt, DateTime(2026, 8, 2, 18));
    expect(summary.lastSevenDays.map((day) => day.count), [
      0,
      0,
      0,
      0,
      1,
      1,
      2,
    ]);
  });

  test('future and inactive mastery timestamps do not become activity', () {
    final now = DateTime(2026, 8, 2, 20);
    final summary = service.summarize([
      _card(
        id: 'future',
        history: [DateTime(2026, 8, 3, 8)],
        masteredAt: DateTime(2026, 8, 1, 12),
      ),
    ], now: now);

    expect(summary.masteredWords, 0);
    expect(summary.totalReviews, 1);
    expect(summary.activeDaysThisWeek, 0);
    expect(summary.latestActivityAt, isNull);
  });
}

WordCard _card({
  required String id,
  List<DateTime> history = const [],
  WordReviewState reviewState = WordReviewState.active,
  DateTime? masteredAt,
}) {
  final createdAt = DateTime(2026, 1, 1);
  return WordCard(
    id: id,
    word: id,
    meaning: id,
    partOfSpeech: PartOfSpeech.noun,
    sentences: const ['Example sentence.'],
    origin: WordOrigin.manual,
    createdAt: createdAt,
    updatedAt: createdAt,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: createdAt,
    history: history,
    isDeleted: false,
    reviewState: reviewState,
    masteredAt: masteredAt,
  );
}
