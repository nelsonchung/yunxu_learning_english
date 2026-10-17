import 'dart:math' as math;

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
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.isActiveToday = false,
    this.todayActivityCount = 0,
    this.latestActivityAt,
  });

  final int masteredWords;
  final int totalReviews;
  final int activeDaysThisWeek;
  final int activeDaysLast30;
  final int currentStreak;
  final int longestStreak;
  final bool isActiveToday;
  final int todayActivityCount;
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

  List<DateTime> _collectActivityTimes(Iterable<WordCard> cards) {
    final activityTimes = <DateTime>[];
    for (final card in cards.where((card) => !card.isDeleted)) {
      if (card.createdAt.millisecondsSinceEpoch > 0) {
        activityTimes.add(card.createdAt.toLocal());
      }
      activityTimes.addAll(card.history.map((item) => item.toLocal()));
      if (card.isMastered && card.masteredAt != null) {
        activityTimes.add(card.masteredAt!.toLocal());
      }
    }
    return activityTimes;
  }

  List<DailyLearningActivity> activityForSevenDays(
    Iterable<WordCard> cards, {
    required DateTime endDay,
    DateTime? latestAllowedAt,
  }) {
    final localEndDay = _startOfDay(endDay.toLocal());
    final startDay = DateTime(
      localEndDay.year,
      localEndDay.month,
      localEndDay.day - 6,
    );
    final rangeEnd = DateTime(
      localEndDay.year,
      localEndDay.month,
      localEndDay.day + 1,
    );
    final localLatestAllowedAt = latestAllowedAt?.toLocal();
    final activityTimes = _collectActivityTimes(cards);

    final activitiesInRange = activityTimes
        .where((item) {
          return !item.isBefore(startDay) &&
              item.isBefore(rangeEnd) &&
              (localLatestAllowedAt == null ||
                  !item.isAfter(localLatestAllowedAt));
        })
        .toList(growable: false);

    return List<DailyLearningActivity>.generate(7, (index) {
      final day = DateTime(startDay.year, startDay.month, startDay.day + index);
      final nextDay = DateTime(
        startDay.year,
        startDay.month,
        startDay.day + index + 1,
      );
      final count = activitiesInRange.where((item) {
        return !item.isBefore(day) && item.isBefore(nextDay);
      }).length;
      return DailyLearningActivity(day: day, count: count);
    }, growable: false);
  }

  List<DailyLearningActivity> activityForMonth(
    Iterable<WordCard> cards, {
    required DateTime month,
    DateTime? latestAllowedAt,
  }) {
    final localMonth = month.toLocal();
    final startDay = DateTime(localMonth.year, localMonth.month, 1);
    final rangeEnd = DateTime(localMonth.year, localMonth.month + 1, 1);
    final daysInMonth = DateTime(localMonth.year, localMonth.month + 1, 0).day;
    final localLatestAllowedAt = latestAllowedAt?.toLocal();
    final activityTimes = _collectActivityTimes(cards);

    final activitiesInRange = activityTimes
        .where((item) {
          return !item.isBefore(startDay) &&
              item.isBefore(rangeEnd) &&
              (localLatestAllowedAt == null ||
                  !item.isAfter(localLatestAllowedAt));
        })
        .toList(growable: false);

    return List<DailyLearningActivity>.generate(daysInMonth, (index) {
      final day = DateTime(localMonth.year, localMonth.month, index + 1);
      final nextDay = DateTime(localMonth.year, localMonth.month, index + 2);
      final count = activitiesInRange.where((item) {
        return !item.isBefore(day) && item.isBefore(nextDay);
      }).length;
      return DailyLearningActivity(day: day, count: count);
    }, growable: false);
  }

  LearningProgressSummary summarize(
    Iterable<WordCard> cards, {
    required DateTime now,
  }) {
    final activeCards = cards.where((card) => !card.isDeleted).toList();
    final localNow = now.toLocal();
    final today = _startOfDay(localNow);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final thirtyDayStart = DateTime(today.year, today.month, today.day - 29);
    final sevenDayStart = DateTime(today.year, today.month, today.day - 6);

    final activityTimes = <DateTime>[];
    var totalReviews = 0;
    var masteredWords = 0;
    var recentForgotReviews = 0;
    var recentHardReviews = 0;
    var recentGoodReviews = 0;
    var recentEasyReviews = 0;

    for (final card in activeCards) {
      if (card.createdAt.millisecondsSinceEpoch > 0) {
        activityTimes.add(card.createdAt.toLocal());
      }
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
    final todayActivityCount = validActivityTimes
        .where((item) => !item.isBefore(today) && item.isBefore(tomorrow))
        .length;
    final isActiveToday = activeDays.contains(today);
    final currentStreak = _calculateCurrentStreak(activeDays, today);
    final longestStreak = _calculateLongestStreak(activeDays);
    final latestActivityAt = validActivityTimes.isEmpty
        ? null
        : validActivityTimes.reduce((latest, item) {
            return item.isAfter(latest) ? item : latest;
          });

    final lastSevenDays = activityForSevenDays(
      activeCards,
      endDay: today,
      latestAllowedAt: localNow,
    );
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
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      isActiveToday: isActiveToday,
      todayActivityCount: todayActivityCount,
      latestActivityAt: latestActivityAt,
      lastSevenDays: lastSevenDays,
      recentForgotReviews: recentForgotReviews,
      recentHardReviews: recentHardReviews,
      recentGoodReviews: recentGoodReviews,
      recentEasyReviews: recentEasyReviews,
      difficultWords: List<WordCard>.unmodifiable(difficultWords),
    );
  }

  int _calculateCurrentStreak(Set<DateTime> activeDays, DateTime today) {
    if (activeDays.isEmpty) {
      return 0;
    }
    final yesterday = _previousDay(today);
    DateTime? cursor;
    if (activeDays.contains(today)) {
      cursor = today;
    } else if (activeDays.contains(yesterday)) {
      cursor = yesterday;
    } else {
      return 0;
    }

    var streak = 0;
    while (cursor != null && activeDays.contains(cursor)) {
      streak++;
      cursor = _previousDay(cursor);
    }
    return streak;
  }

  int _calculateLongestStreak(Set<DateTime> activeDays) {
    if (activeDays.isEmpty) {
      return 0;
    }
    final sortedDays = activeDays.toList(growable: false)..sort();
    var longest = 0;
    var currentRun = 0;
    DateTime? previous;

    for (final day in sortedDays) {
      if (previous != null && _nextDay(previous) == day) {
        currentRun++;
      } else {
        currentRun = 1;
      }
      longest = math.max(longest, currentRun);
      previous = day;
    }
    return longest;
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

  DateTime _previousDay(DateTime day) {
    return DateTime(day.year, day.month, day.day - 1);
  }

  DateTime _nextDay(DateTime day) {
    return DateTime(day.year, day.month, day.day + 1);
  }
}
