import '../models/word_card.dart';

class ReviewScheduleService {
  static const List<int> defaultSchedule = [1, 2, 3, 5, 8, 13, 21, 39];

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
        reviewState: WordReviewState.active,
        masteredAt: null,
      );
    }

    final daysToAdd = card.reviewSchedule[nextIndex];
    final nextDate = card.createdAt.add(Duration(days: daysToAdd));

    return card.copyWith(
      nextReviewIndex: nextIndex,
      nextReviewDate: nextDate,
      history: updatedHistory,
      reviewState: WordReviewState.active,
      masteredAt: null,
    );
  }

  WordCard markMastered(WordCard card, DateTime now) {
    return card.copyWith(
      reviewState: WordReviewState.mastered,
      masteredAt: now,
    );
  }

  WordCard resumeReview(WordCard card) {
    return card.copyWith(reviewState: WordReviewState.active, masteredAt: null);
  }

  bool isDueOnOrBefore(WordCard card, DateTime day) {
    if (card.isDeleted) {
      return false;
    }
    if (card.isReviewFinished) {
      return false;
    }
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
    return card.nextReviewDate.isBefore(endOfDay) ||
        card.nextReviewDate.isAtSameMomentAs(endOfDay);
  }
}
