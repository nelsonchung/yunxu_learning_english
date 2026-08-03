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

  test('summarizes recent ratings and difficult words', () {
    final now = DateTime(2026, 8, 2, 20);
    final summary = service.summarize([
      _card(
        id: 'difficult',
        history: [
          DateTime(2026, 7, 31, 8),
          DateTime(2026, 8, 1, 8),
          DateTime(2026, 8, 2, 8),
        ],
        reviewRatings: const [
          ReviewRating.forgot,
          ReviewRating.hard,
          ReviewRating.good,
        ],
      ),
      _card(
        id: 'steady',
        history: [DateTime(2026, 8, 2, 12)],
        reviewRatings: const [ReviewRating.easy],
      ),
    ], now: now);

    expect(summary.recentForgotReviews, 1);
    expect(summary.recentHardReviews, 1);
    expect(summary.recentGoodReviews, 1);
    expect(summary.recentEasyReviews, 1);
    expect(summary.recentRecallRate, 50);
    expect(summary.difficultWords.map((card) => card.word), ['difficult']);
  });

  test('legacy unrated history is excluded from recall rate', () {
    final now = DateTime(2026, 8, 2, 20);
    final summary = service.summarize([
      _card(id: 'legacy', history: [DateTime(2026, 8, 2, 8)]),
    ], now: now);

    expect(summary.recentRatedReviews, 0);
    expect(summary.recentRecallRate, isNull);
    expect(summary.difficultWords, isEmpty);
  });

  test('returns activity for an earlier seven-day range', () {
    final activities = service.activityForSevenDays([
      _card(
        id: 'earlier',
        history: [
          DateTime(2026, 7, 20, 8),
          DateTime(2026, 7, 20, 18),
          DateTime(2026, 7, 26, 9),
          DateTime(2026, 7, 27, 9),
        ],
      ),
    ], endDay: DateTime(2026, 7, 26));

    expect(activities.first.day, DateTime(2026, 7, 20));
    expect(activities.last.day, DateTime(2026, 7, 26));
    expect(activities.map((day) => day.count), [2, 0, 0, 0, 0, 0, 1]);
  });

  test('excludes future activity from the current seven-day range', () {
    final activities = service.activityForSevenDays(
      [
        _card(
          id: 'today',
          history: [DateTime(2026, 8, 2, 8), DateTime(2026, 8, 2, 21)],
        ),
      ],
      endDay: DateTime(2026, 8, 2),
      latestAllowedAt: DateTime(2026, 8, 2, 20),
    );

    expect(activities.last.count, 1);
  });
}

WordCard _card({
  required String id,
  List<DateTime> history = const [],
  List<ReviewRating> reviewRatings = const [],
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
    reviewRatings: reviewRatings,
    isDeleted: false,
    reviewState: reviewState,
    masteredAt: masteredAt,
  );
}
