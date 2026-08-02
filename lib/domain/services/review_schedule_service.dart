import '../models/word_card.dart';

class ReviewScheduleService {
  static const List<int> defaultSchedule = [1, 2, 3, 5, 8, 13, 21, 39];

  DateTime initialNextDate(DateTime createdAt) {
    return createdAt.add(Duration(days: defaultSchedule.first));
  }

  WordCard advanceReview(WordCard card, DateTime now) {
    return recordReview(card, ReviewRating.good, now);
  }

  WordCard recordReview(WordCard card, ReviewRating rating, DateTime now) {
    final updatedHistory = List<DateTime>.from(card.history)..add(now);
    final updatedRatings = List<ReviewRating>.from(card.alignedReviewRatings)
      ..add(rating);
    final schedule = card.reviewSchedule.isEmpty
        ? defaultSchedule
        : card.reviewSchedule;
    final currentIndex = card.nextReviewIndex
        .clamp(0, schedule.length - 1)
        .toInt();

    late final int nextIndex;
    late final int daysToAdd;
    switch (rating) {
      case ReviewRating.unrated:
      case ReviewRating.good:
        nextIndex = currentIndex + 1;
        daysToAdd = _daysBetweenStages(schedule, currentIndex, nextIndex);
      case ReviewRating.forgot:
        nextIndex = 0;
        daysToAdd = 1;
      case ReviewRating.hard:
        nextIndex = currentIndex;
        final nearbyInterval = currentIndex + 1 < schedule.length
            ? schedule[currentIndex + 1] - schedule[currentIndex]
            : currentIndex > 0
            ? schedule[currentIndex] - schedule[currentIndex - 1]
            : schedule[currentIndex];
        daysToAdd = (nearbyInterval / 2).ceil().clamp(1, 3650).toInt();
      case ReviewRating.easy:
        nextIndex = currentIndex + 2;
        daysToAdd = _daysBetweenStages(schedule, currentIndex, nextIndex);
    }

    if (nextIndex >= schedule.length) {
      return card.copyWith(
        reviewSchedule: schedule,
        nextReviewIndex: nextIndex,
        history: updatedHistory,
        reviewRatings: updatedRatings,
        reviewState: WordReviewState.active,
        masteredAt: null,
      );
    }

    final nextDate = now.add(Duration(days: daysToAdd));

    return card.copyWith(
      reviewSchedule: schedule,
      nextReviewIndex: nextIndex,
      nextReviewDate: nextDate,
      history: updatedHistory,
      reviewRatings: updatedRatings,
      reviewState: WordReviewState.active,
      masteredAt: null,
    );
  }

  int _daysBetweenStages(
    List<int> schedule,
    int currentIndex,
    int targetIndex,
  ) {
    if (targetIndex >= schedule.length) {
      return 0;
    }
    return (schedule[targetIndex] - schedule[currentIndex])
        .clamp(1, 3650)
        .toInt();
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
