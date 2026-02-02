class WordCard {
  WordCard({
    required this.id,
    required this.word,
    required this.sentences,
    required this.createdAt,
    required this.reviewSchedule,
    required this.nextReviewIndex,
    required this.nextReviewDate,
    required this.history,
    this.imagePath,
  });

  final String id;
  final String word;
  final List<String> sentences;
  final String? imagePath;
  final DateTime createdAt;
  final List<int> reviewSchedule;
  final int nextReviewIndex;
  final DateTime nextReviewDate;
  final List<DateTime> history;

  WordCard copyWith({
    String? id,
    String? word,
    List<String>? sentences,
    String? imagePath,
    DateTime? createdAt,
    List<int>? reviewSchedule,
    int? nextReviewIndex,
    DateTime? nextReviewDate,
    List<DateTime>? history,
  }) {
    return WordCard(
      id: id ?? this.id,
      word: word ?? this.word,
      sentences: sentences ?? this.sentences,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      reviewSchedule: reviewSchedule ?? this.reviewSchedule,
      nextReviewIndex: nextReviewIndex ?? this.nextReviewIndex,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      history: history ?? this.history,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'word': word,
      'sentences': sentences,
      'imagePath': imagePath,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'reviewSchedule': reviewSchedule,
      'nextReviewIndex': nextReviewIndex,
      'nextReviewDate': nextReviewDate.millisecondsSinceEpoch,
      'history': history.map((item) => item.millisecondsSinceEpoch).toList(),
    };
  }

  static WordCard fromMap(Map data) {
    return WordCard(
      id: data['id'] as String,
      word: data['word'] as String,
      sentences: List<String>.from(data['sentences'] as List),
      imagePath: data['imagePath'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
      reviewSchedule: List<int>.from(data['reviewSchedule'] as List),
      nextReviewIndex: data['nextReviewIndex'] as int,
      nextReviewDate:
          DateTime.fromMillisecondsSinceEpoch(data['nextReviewDate'] as int),
      history: (data['history'] as List)
          .map((item) => DateTime.fromMillisecondsSinceEpoch(item as int))
          .toList(),
    );
  }
}
