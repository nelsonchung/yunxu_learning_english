enum PartOfSpeech {
  noun,
  verb,
  adjective,
  adverb,
  preposition,
  pronoun,
  conjunction,
  interjection,
  phrase,
  other,
}

extension PartOfSpeechLabel on PartOfSpeech {
  String get label {
    switch (this) {
      case PartOfSpeech.noun:
        return '名詞';
      case PartOfSpeech.verb:
        return '動詞';
      case PartOfSpeech.adjective:
        return '形容詞';
      case PartOfSpeech.adverb:
        return '副詞';
      case PartOfSpeech.preposition:
        return '介系詞';
      case PartOfSpeech.pronoun:
        return '代名詞';
      case PartOfSpeech.conjunction:
        return '連接詞';
      case PartOfSpeech.interjection:
        return '感嘆詞';
      case PartOfSpeech.phrase:
        return '片語';
      case PartOfSpeech.other:
        return '其他';
    }
  }
}

class WordCard {
  WordCard({
    required this.id,
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
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
  final String meaning;
  final PartOfSpeech partOfSpeech;
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
    String? meaning,
    PartOfSpeech? partOfSpeech,
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
      meaning: meaning ?? this.meaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
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
      'meaning': meaning,
      'partOfSpeech': partOfSpeech.name,
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
    final partRaw = data['partOfSpeech'];
    var parsedPart = PartOfSpeech.noun;
    if (partRaw is String) {
      parsedPart = PartOfSpeech.values.firstWhere(
        (item) => item.name == partRaw,
        orElse: () => PartOfSpeech.noun,
      );
    }

    return WordCard(
      id: data['id'] as String,
      word: data['word'] as String,
      meaning: (data['meaning'] as String?) ?? '',
      partOfSpeech: parsedPart,
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
