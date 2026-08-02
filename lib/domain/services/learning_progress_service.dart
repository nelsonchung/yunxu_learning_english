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
    this.latestActivityAt,
  });

  final int masteredWords;
  final int totalReviews;
  final int activeDaysThisWeek;
  final int activeDaysLast30;
  final DateTime? latestActivityAt;
  final List<DailyLearningActivity> lastSevenDays;
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

    for (final card in activeCards) {
      totalReviews += card.history.length;
      activityTimes.addAll(card.history.map((item) => item.toLocal()));
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
    );
  }

  DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
