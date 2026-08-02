import '../models/word_card.dart';

class DailyLearningActivity {
  const DailyLearningActivity({required this.day, required this.count});

  final DateTime day;
  final int count;
}

class LearningProgressSummary {
  const LearningProgressSummary({
    required this.masteredWords,
    required this.totalReviews,
    required this.activeDaysThisWeek,
    required this.activeDaysLast30,
    required this.lastSevenDays,
    required this.recentForgotReviews,
    required this.recentHardReviews,
    required this.recentGoodReviews,
    required this.recentEasyReviews,
    required this.difficultWords,
    this.latestActivityAt,
  });

  final int masteredWords;
  final int totalReviews;
  final int activeDaysThisWeek;
  final int activeDaysLast30;
  final DateTime? latestActivityAt;
  final List<DailyLearningActivity> lastSevenDays;
  final int recentForgotReviews;
  final int recentHardReviews;
  final int recentGoodReviews;
  final int recentEasyReviews;
  final List<WordCard> difficultWords;

  int get recentRatedReviews =>
      recentForgotReviews +
      recentHardReviews +
      recentGoodReviews +
      recentEasyReviews;
  int? get recentRecallRate {
    if (recentRatedReviews == 0) {
      return null;
    }
    return ((recentGoodReviews + recentEasyReviews) / recentRatedReviews * 100)
        .round();
  }
}

class LearningProgressService {
  const LearningProgressService();

  LearningProgressSummary summarize(
    Iterable<WordCard> cards, {
    required DateTime now,
  }) {
    final activeCards = cards.where((card) => !card.isDeleted).toList();
    final localNow = now.toLocal();
    final today = _startOfDay(localNow);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final thirtyDayStart = today.subtract(const Duration(days: 29));
    final sevenDayStart = today.subtract(const Duration(days: 6));

    final activityTimes = <DateTime>[];
    var totalReviews = 0;
    var masteredWords = 0;
    var recentForgotReviews = 0;
    var recentHardReviews = 0;
    var recentGoodReviews = 0;
    var recentEasyReviews = 0;

    for (final card in activeCards) {
      totalReviews += card.history.length;
      activityTimes.addAll(card.history.map((item) => item.toLocal()));
      final ratings = card.alignedReviewRatings;
      for (var index = 0; index < card.history.length; index++) {
        final reviewedAt = card.history[index].toLocal();
        if (reviewedAt.isBefore(sevenDayStart) ||
            !reviewedAt.isBefore(tomorrow) ||
            reviewedAt.isAfter(localNow)) {
          continue;
        }
        switch (ratings[index]) {
          case ReviewRating.unrated:
            break;
          case ReviewRating.forgot:
            recentForgotReviews++;
          case ReviewRating.hard:
            recentHardReviews++;
          case ReviewRating.good:
            recentGoodReviews++;
          case ReviewRating.easy:
            recentEasyReviews++;
        }
      }
      if (card.isMastered) {
        masteredWords++;
        final masteredAt = card.masteredAt;
        if (masteredAt != null) {
          activityTimes.add(masteredAt.toLocal());
        }
      }
    }

    final validActivityTimes = activityTimes
        .where((item) => !item.isAfter(localNow))
        .toList(growable: false);
    final activeDays = validActivityTimes.map(_startOfDay).toSet();
    final latestActivityAt = validActivityTimes.isEmpty
        ? null
        : validActivityTimes.reduce((latest, item) {
            return item.isAfter(latest) ? item : latest;
          });

    final lastSevenDays = List<DailyLearningActivity>.generate(7, (index) {
      final day = sevenDayStart.add(Duration(days: index));
      final count = validActivityTimes.where((item) {
        return !item.isBefore(day) &&
            item.isBefore(day.add(const Duration(days: 1)));
      }).length;
      return DailyLearningActivity(day: day, count: count);
    }, growable: false);
    final difficultWords =
        activeCards.where((card) => card.isDifficult).toList(growable: false)
          ..sort((first, second) {
            final firstScore = _difficultyScore(first);
            final secondScore = _difficultyScore(second);
            final scoreCompare = secondScore.compareTo(firstScore);
            if (scoreCompare != 0) {
              return scoreCompare;
            }
            return first.word.toLowerCase().compareTo(
              second.word.toLowerCase(),
            );
          });

    return LearningProgressSummary(
      masteredWords: masteredWords,
      totalReviews: totalReviews,
      activeDaysThisWeek: activeDays
          .where((day) => !day.isBefore(weekStart) && day.isBefore(tomorrow))
          .length,
      activeDaysLast30: activeDays
          .where(
            (day) => !day.isBefore(thirtyDayStart) && day.isBefore(tomorrow),
          )
          .length,
      latestActivityAt: latestActivityAt,
      lastSevenDays: lastSevenDays,
      recentForgotReviews: recentForgotReviews,
      recentHardReviews: recentHardReviews,
      recentGoodReviews: recentGoodReviews,
      recentEasyReviews: recentEasyReviews,
      difficultWords: List<WordCard>.unmodifiable(difficultWords),
    );
  }

  int _difficultyScore(WordCard card) {
    return card.alignedReviewRatings
        .where((rating) => rating != ReviewRating.unrated)
        .toList(growable: false)
        .reversed
        .take(3)
        .fold(0, (score, rating) {
          return score +
              switch (rating) {
                ReviewRating.forgot => 2,
                ReviewRating.hard => 1,
                _ => 0,
              };
        });
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
