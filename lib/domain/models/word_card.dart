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

enum MissingWordField { meaning, sentence }

extension MissingWordFieldLabel on MissingWordField {
  String get label {
    switch (this) {
      case MissingWordField.meaning:
        return '中文意義';
      case MissingWordField.sentence:
        return '例句';
    }
  }
}

enum WordCardStatus { complete, pending }

enum WordOrigin { unknown, manual, builtinWordBank }

enum WordReviewState { active, mastered }

enum ReviewRating { unrated, forgot, hard, good, easy }

extension ReviewRatingLabel on ReviewRating {
  String get label {
    switch (this) {
      case ReviewRating.unrated:
        return '未評級';
      case ReviewRating.forgot:
        return '忘記了';
      case ReviewRating.hard:
        return '有點困難';
      case ReviewRating.good:
        return '記得';
      case ReviewRating.easy:
        return '太簡單';
    }
  }

  bool get isStruggling =>
      this == ReviewRating.forgot || this == ReviewRating.hard;
  bool get isRemembered =>
      this == ReviewRating.good || this == ReviewRating.easy;
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

extension WordOriginLabel on WordOrigin {
  String get label {
    switch (this) {
      case WordOrigin.unknown:
        return '來源未知';
      case WordOrigin.manual:
        return '使用者新增';
      case WordOrigin.builtinWordBank:
        return '內建字庫';
    }
  }
}

extension WordReviewStateLabel on WordReviewState {
  String get label {
    switch (this) {
      case WordReviewState.active:
        return '複習中';
      case WordReviewState.mastered:
        return '已掌握';
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
    required this.origin,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewSchedule,
    required this.nextReviewIndex,
    required this.nextReviewDate,
    required this.history,
    required this.isDeleted,
    this.reviewRatings = const [],
    this.customTags = const [],
    this.imageCleared = false,
    this.reviewState = WordReviewState.active,
    this.masteredAt,
    this.memoryHint = '',
    this.imagePath,
    this.imageBytes,
  });

  final String id;
  final String word;
  final String meaning;
  final String memoryHint;
  final PartOfSpeech partOfSpeech;
  final List<String> sentences;
  final WordOrigin origin;
  final String? imagePath;
  final List<int>? imageBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<int> reviewSchedule;
  final int nextReviewIndex;
  final DateTime nextReviewDate;
  final List<DateTime> history;
  final List<ReviewRating> reviewRatings;
  final bool isDeleted;
  final List<String> customTags;
  final bool imageCleared;
  final WordReviewState reviewState;
  final DateTime? masteredAt;

  static List<String> normalizeCustomTags(Iterable<String> rawTags) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final rawTag in rawTags) {
      final collapsed = rawTag.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (collapsed.isEmpty) {
        continue;
      }

      final key = collapsed.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      normalized.add(collapsed);
    }

    return List<String>.unmodifiable(normalized);
  }

  static List<ReviewRating> normalizeReviewRatings(
    int historyLength,
    Iterable<ReviewRating> rawRatings,
  ) {
    if (historyLength <= 0) {
      return const [];
    }
    final ratings = rawRatings.toList(growable: false);
    if (ratings.length >= historyLength) {
      return List<ReviewRating>.unmodifiable(ratings.take(historyLength));
    }
    return List<ReviewRating>.unmodifiable([
      ...ratings,
      ...List<ReviewRating>.filled(
        historyLength - ratings.length,
        ReviewRating.unrated,
      ),
    ]);
  }

  List<MissingWordField> get missingFields {
    final missing = <MissingWordField>[];
    if (meaning.trim().isEmpty) {
      missing.add(MissingWordField.meaning);
    }
    if (!sentences.any((sentence) => sentence.trim().isNotEmpty)) {
      missing.add(MissingWordField.sentence);
    }
    return missing;
  }

  List<String> get missingFieldLabels =>
      missingFields.map((field) => field.label).toList(growable: false);

  WordCardStatus get status =>
      missingFields.isEmpty ? WordCardStatus.complete : WordCardStatus.pending;

  bool get needsCompletion => status == WordCardStatus.pending;
  bool get isMastered => reviewState == WordReviewState.mastered;
  bool get hasCompletedReviewSchedule =>
      nextReviewIndex >= reviewSchedule.length;
  bool get isReviewFinished => isMastered || hasCompletedReviewSchedule;
  List<ReviewRating> get alignedReviewRatings =>
      normalizeReviewRatings(history.length, reviewRatings);

  bool get isDifficult {
    if (isReviewFinished) {
      return false;
    }
    final recentRatings = alignedReviewRatings
        .where((rating) => rating != ReviewRating.unrated)
        .toList(growable: false)
        .reversed
        .take(3);
    return recentRatings.where((rating) => rating.isStruggling).length >= 2;
  }

  WordCard copyWith({
    String? id,
    String? word,
    String? meaning,
    String? memoryHint,
    PartOfSpeech? partOfSpeech,
    List<String>? sentences,
    WordOrigin? origin,
    Object? imagePath = _unset,
    Object? imageBytes = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<int>? reviewSchedule,
    int? nextReviewIndex,
    DateTime? nextReviewDate,
    List<DateTime>? history,
    List<ReviewRating>? reviewRatings,
    bool? isDeleted,
    List<String>? customTags,
    bool? imageCleared,
    WordReviewState? reviewState,
    Object? masteredAt = _unset,
  }) {
    return WordCard(
      id: id ?? this.id,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      memoryHint: memoryHint ?? this.memoryHint,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      sentences: sentences ?? this.sentences,
      origin: origin ?? this.origin,
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
      reviewRatings: reviewRatings ?? this.reviewRatings,
      isDeleted: isDeleted ?? this.isDeleted,
      customTags: customTags ?? this.customTags,
      imageCleared: imageCleared ?? this.imageCleared,
      reviewState: reviewState ?? this.reviewState,
      masteredAt: identical(masteredAt, _unset)
          ? this.masteredAt
          : masteredAt as DateTime?,
    );
  }

  Map<String, Object?> toMap() {
    final normalizedSentences = sentences
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
    final normalizedImageBytes = imageBytes == null
        ? null
        : imageBytes is Uint8List
        ? imageBytes
        : Uint8List.fromList(imageBytes!);
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
      'memoryHint': memoryHint.trim(),
      'partOfSpeech': partOfSpeech.name,
      'sentences': normalizedSentences,
      'origin': origin.name,
      'imagePath': imagePath,
      'imageBytes': normalizedImageBytes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'reviewSchedule': reviewSchedule,
      'nextReviewIndex': nextReviewIndex,
      'nextReviewDate': nextReviewDate.millisecondsSinceEpoch,
      'history': history.map((item) => item.millisecondsSinceEpoch).toList(),
      'reviewRatings': alignedReviewRatings
          .map((rating) => rating.name)
          .toList(growable: false),
      'isDeleted': isDeleted,
      'customTags': normalizeCustomTags(customTags),
      'imageCleared': imageCleared,
      'reviewState': reviewState.name,
      'masteredAt': masteredAt?.millisecondsSinceEpoch,
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

    final originRaw = data['origin'];
    var parsedOrigin = WordOrigin.unknown;
    if (originRaw is String) {
      parsedOrigin = WordOrigin.values.firstWhere(
        (item) => item.name == originRaw,
        orElse: () => WordOrigin.unknown,
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
        ? sentencesRaw
              .whereType<String>()
              .map((sentence) => sentence.trim())
              .where((sentence) => sentence.isNotEmpty)
              .toList()
        : <String>[];

    final reviewRaw = data['reviewSchedule'];
    final parsedReviewSchedule = reviewRaw is List
        ? reviewRaw.whereType<int>().toList()
        : const <int>[];
    final reviewSchedule = parsedReviewSchedule.isEmpty
        ? const <int>[1, 2, 3, 5, 8, 13, 21, 39]
        : parsedReviewSchedule;

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
    final reviewRatingsRaw = data['reviewRatings'];
    final parsedReviewRatings = reviewRatingsRaw is List
        ? reviewRatingsRaw
              .whereType<String>()
              .map((raw) {
                return ReviewRating.values.firstWhere(
                  (rating) => rating.name == raw,
                  orElse: () => ReviewRating.unrated,
                );
              })
              .toList(growable: false)
        : const <ReviewRating>[];
    final reviewRatings = normalizeReviewRatings(
      history.length,
      parsedReviewRatings,
    );
    final customTagsRaw = data['customTags'];
    final customTags = customTagsRaw is List
        ? normalizeCustomTags(customTagsRaw.whereType<String>())
        : const <String>[];

    final isDeletedRaw = data['isDeleted'];
    final isDeleted = isDeletedRaw is bool ? isDeletedRaw : false;
    final imageClearedRaw = data['imageCleared'];
    final imageCleared = imageClearedRaw is bool ? imageClearedRaw : false;
    final reviewStateRaw = data['reviewState'];
    final reviewState = reviewStateRaw is String
        ? WordReviewState.values.firstWhere(
            (item) => item.name == reviewStateRaw,
            orElse: () => WordReviewState.active,
          )
        : WordReviewState.active;
    final masteredAtRaw = data['masteredAt'];
    final masteredAt = masteredAtRaw is int
        ? DateTime.fromMillisecondsSinceEpoch(masteredAtRaw)
        : null;

    return WordCard(
      id: (data['id'] as String?) ?? '',
      word: (data['word'] as String?) ?? '',
      meaning: (data['meaning'] as String?) ?? '',
      memoryHint: (data['memoryHint'] as String?)?.trim() ?? '',
      partOfSpeech: parsedPart,
      sentences: sentences,
      origin: parsedOrigin,
      imagePath: data['imagePath'] as String?,
      imageBytes: parsedBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewSchedule: reviewSchedule,
      nextReviewIndex: nextReviewIndex,
      nextReviewDate: nextReviewDate,
      history: history,
      reviewRatings: reviewRatings,
      isDeleted: isDeleted,
      customTags: customTags,
      imageCleared: imageCleared,
      reviewState: reviewState,
      masteredAt: masteredAt,
    );
  }
}
