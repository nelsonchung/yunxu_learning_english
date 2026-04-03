import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/word_card.dart';
import 'review_schedule_service.dart';

class WordContributionImportResult {
  const WordContributionImportResult({
    required this.importedWords,
    required this.totalEntries,
    required this.skippedDuplicateCount,
    required this.invalidCount,
  });

  final List<WordCard> importedWords;
  final int totalEntries;
  final int skippedDuplicateCount;
  final int invalidCount;

  int get importedCount => importedWords.length;
}

class WordContributionImportService {
  WordContributionImportService({
    required ReviewScheduleService scheduleService,
    Uuid? uuid,
  }) : _scheduleService = scheduleService,
       _uuid = uuid ?? const Uuid();

  static const int supportedSchemaVersion = 1;

  final ReviewScheduleService _scheduleService;
  final Uuid _uuid;

  WordContributionImportResult parseJson({
    required String jsonText,
    required Set<String> existingWords,
    DateTime? importedAt,
  }) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('匯入檔案格式錯誤，根節點必須是物件');
    }

    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final schemaVersion = payload['schemaVersion'];
    if (schemaVersion != null &&
        (schemaVersion is! int || schemaVersion != supportedSchemaVersion)) {
      throw FormatException('目前只支援 schemaVersion = $supportedSchemaVersion');
    }

    final wordsRaw = payload['words'];
    if (wordsRaw is! List) {
      throw const FormatException('匯入檔案缺少 words 陣列');
    }

    final normalizedWords = existingWords
        .map(_normalizeWordKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    final now = importedAt ?? DateTime.now();
    final importedWords = <WordCard>[];
    var skippedDuplicateCount = 0;
    var invalidCount = 0;

    for (final item in wordsRaw) {
      if (item is! Map) {
        invalidCount++;
        continue;
      }

      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final word = _readTrimmedString(map['word']);
      final normalizedWord = _normalizeWordKey(word);
      if (normalizedWord.isEmpty) {
        invalidCount++;
        continue;
      }
      if (normalizedWords.contains(normalizedWord)) {
        skippedDuplicateCount++;
        continue;
      }
      normalizedWords.add(normalizedWord);

      final card = WordCard(
        id: _uuid.v4(),
        word: word,
        meaning: _readTrimmedString(map['meaning']),
        partOfSpeech: _parsePartOfSpeech(map['partOfSpeech']),
        sentences: _readSentences(map['sentences']),
        origin: WordOrigin.manual,
        imageCleared: false,
        imagePath: null,
        imageBytes: null,
        createdAt: now,
        updatedAt: now,
        reviewSchedule: ReviewScheduleService.defaultSchedule,
        nextReviewIndex: 0,
        nextReviewDate: _scheduleService.initialNextDate(now),
        history: const [],
        isDeleted: false,
        customTags: _readCustomTags(map['customTags']),
      );
      importedWords.add(card);
    }

    return WordContributionImportResult(
      importedWords: List<WordCard>.unmodifiable(importedWords),
      totalEntries: wordsRaw.length,
      skippedDuplicateCount: skippedDuplicateCount,
      invalidCount: invalidCount,
    );
  }

  static String normalizeWordKey(String word) => _normalizeWordKey(word);

  static String _normalizeWordKey(String word) =>
      word.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _readTrimmedString(Object? value) {
    if (value is! String) {
      return '';
    }
    return value.trim();
  }

  List<String> _readSentences(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _readCustomTags(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return WordCard.normalizeCustomTags(value.whereType<String>());
  }

  PartOfSpeech _parsePartOfSpeech(Object? value) {
    if (value is! String) {
      return PartOfSpeech.other;
    }
    return PartOfSpeech.values.firstWhere(
      (item) => item.name == value,
      orElse: () => PartOfSpeech.other,
    );
  }
}
