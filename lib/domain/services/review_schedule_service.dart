import '../models/word_card.dart';

class ReviewScheduleService {
  static const List<int> defaultSchedule = [1, 2, 3, 5, 7, 12, 19, 31];

  DateTime initialNextDate(DateTime createdAt) {
    return createdAt.add(Duration(days: defaultSchedule.first));
  }

  WordCard advanceReview(WordCard card, DateTime now) {
    final updatedHistory = List<DateTime>.from(card.history)..add(now);
    final nextIndex = card.nextReviewIndex + 1;

    if (nextIndex >= card.reviewSchedule.length) {
      return card.copyWith(
        nextReviewIndex: nextIndex,
        history: updatedHistory,
      );
    }

    final daysToAdd = card.reviewSchedule[nextIndex];
    final nextDate = card.createdAt.add(Duration(days: daysToAdd));

    return card.copyWith(
      nextReviewIndex: nextIndex,
      nextReviewDate: nextDate,
      history: updatedHistory,
    );
  }

  bool isDueOnOrBefore(WordCard card, DateTime day) {
    if (card.nextReviewIndex >= card.reviewSchedule.length) {
      return false;
    }
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
    return card.nextReviewDate.isBefore(endOfDay) ||
        card.nextReviewDate.isAtSameMomentAs(endOfDay);
  }
}
