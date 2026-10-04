import 'learning_image.dart';

/// Groups new requests by flow; legacy requests remain separate and unassigned.
class LearningImageHistoryEntry {
  LearningImageHistoryEntry(this.id, Iterable<LearningImageAttempt> attempts)
    : attempts = List.unmodifiable(
        attempts.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  final String id;
  final List<LearningImageAttempt> attempts;

  String? get word {
    for (final attempt in attempts) {
      final value = attempt.word;
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  DateTime get latestAt => attempts.last.createdAt;
  double get knownCostUsd => attempts.fold(0, (sum, a) => sum + a.cost.usd);
  int get unknownCount => attempts.where((a) => a.cost.unknown).length;
  int get imageCount => attempts.where(isImage).length;
  double get researchCostUsd =>
      attempts.where(isResearch).fold(0, (sum, a) => sum + a.cost.usd);
  double get imageCostUsd =>
      attempts.where(isImage).fold(0, (sum, a) => sum + a.cost.usd);

  double get otherCostUsd => attempts
      .where((a) => !isResearch(a) && !isImage(a))
      .fold(0, (sum, a) => sum + a.cost.usd);

  static bool isResearch(LearningImageAttempt attempt) =>
      attempt.model == 'gpt-5.4-mini';
  static bool isImage(LearningImageAttempt attempt) =>
      attempt.model.startsWith('gpt-image-');

  static List<LearningImageHistoryEntry> group(
    Iterable<LearningImageAttempt> attempts,
  ) {
    final groups = <String, List<LearningImageAttempt>>{};
    for (final attempt in attempts) {
      final flow = attempt.generationId;
      final key = flow == null || flow.isEmpty
          ? 'legacy:${attempt.id}'
          : 'flow:$flow';
      (groups[key] ??= []).add(attempt);
    }
    return groups.entries
        .map((e) => LearningImageHistoryEntry(e.key, e.value))
        .toList()
      ..sort((a, b) {
        final dateOrder = b.latestAt.compareTo(a.latestAt);
        return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
      });
  }
}
