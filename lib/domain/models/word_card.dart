import 'dart:typed_data';

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
  static const Object _unset = Object();

  WordCard({
    required this.id,
    required this.word,
    required this.meaning,
    required this.partOfSpeech,
    required this.sentences,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewSchedule,
    required this.nextReviewIndex,
    required this.nextReviewDate,
    required this.history,
    required this.isDeleted,
    this.imagePath,
    this.imageBytes,
  });

  final String id;
  final String word;
  final String meaning;
  final PartOfSpeech partOfSpeech;
  final List<String> sentences;
  final String? imagePath;
  final List<int>? imageBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int> reviewSchedule;
  final int nextReviewIndex;
  final DateTime nextReviewDate;
  final List<DateTime> history;
  final bool isDeleted;

  WordCard copyWith({
    String? id,
    String? word,
    String? meaning,
    PartOfSpeech? partOfSpeech,
    List<String>? sentences,
    Object? imagePath = _unset,
    Object? imageBytes = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<int>? reviewSchedule,
    int? nextReviewIndex,
    DateTime? nextReviewDate,
    List<DateTime>? history,
    bool? isDeleted,
  }) {
    return WordCard(
      id: id ?? this.id,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      sentences: sentences ?? this.sentences,
      imagePath: identical(imagePath, _unset)
          ? this.imagePath
          : imagePath as String?,
      imageBytes: identical(imageBytes, _unset)
          ? this.imageBytes
          : imageBytes as List<int>?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewSchedule: reviewSchedule ?? this.reviewSchedule,
      nextReviewIndex: nextReviewIndex ?? this.nextReviewIndex,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
      history: history ?? this.history,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, Object?> toMap() {
    final normalizedImageBytes = imageBytes == null
        ? null
        : imageBytes is Uint8List
        ? imageBytes
        : Uint8List.fromList(imageBytes!);
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
      'partOfSpeech': partOfSpeech.name,
      'sentences': sentences,
      'imagePath': imagePath,
      'imageBytes': normalizedImageBytes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'reviewSchedule': reviewSchedule,
      'nextReviewIndex': nextReviewIndex,
      'nextReviewDate': nextReviewDate.millisecondsSinceEpoch,
      'history': history.map((item) => item.millisecondsSinceEpoch).toList(),
      'isDeleted': isDeleted,
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

    List<int>? parsedBytes;
    final bytesRaw = data['imageBytes'];
    if (bytesRaw is Uint8List) {
      parsedBytes = bytesRaw;
    } else if (bytesRaw is List) {
      try {
        parsedBytes = Uint8List.fromList(bytesRaw.cast<int>());
      } catch (_) {
        parsedBytes = null;
      }
    }

    final createdRaw = data['createdAt'];
    final createdAt = createdRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(createdRaw)
        : DateTime.now();
    final updatedRaw = data['updatedAt'];
    final updatedAt = updatedRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(updatedRaw)
        : createdAt;

    final sentencesRaw = data['sentences'];
    final sentences = sentencesRaw is List
        ? sentencesRaw.whereType<String>().toList()
        : <String>[];

    final reviewRaw = data['reviewSchedule'];
    final reviewSchedule = reviewRaw is List
        ? reviewRaw.whereType<int>().toList()
        : const <int>[1, 2, 3, 5, 8, 13, 21, 39];

    final nextReviewIndexRaw = data['nextReviewIndex'];
    final nextReviewIndex = nextReviewIndexRaw is int ? nextReviewIndexRaw : 0;

    final nextReviewRaw = data['nextReviewDate'];
    final nextReviewDate = nextReviewRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(nextReviewRaw)
        : createdAt;

    final historyRaw = data['history'];
    final history = historyRaw is List
        ? historyRaw
              .whereType<int>()
              .map((item) => DateTime.fromMillisecondsSinceEpoch(item))
              .toList()
        : <DateTime>[];

    final isDeletedRaw = data['isDeleted'];
    final isDeleted = isDeletedRaw is bool ? isDeletedRaw : false;

    return WordCard(
      id: (data['id'] as String?) ?? '',
      word: (data['word'] as String?) ?? '',
      meaning: (data['meaning'] as String?) ?? '',
      partOfSpeech: parsedPart,
      sentences: sentences,
      imagePath: data['imagePath'] as String?,
      imageBytes: parsedBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewSchedule: reviewSchedule,
      nextReviewIndex: nextReviewIndex,
      nextReviewDate: nextReviewDate,
      history: history,
      isDeleted: isDeleted,
    );
  }
}
