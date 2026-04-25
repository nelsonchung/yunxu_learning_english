import 'package:flutter_test/flutter_test.dart';

import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';

void main() {
  group('WordContributionImportService', () {
    late ReviewScheduleService scheduleService;
    late WordContributionImportService service;

    setUp(() {
      scheduleService = ReviewScheduleService();
      service = WordContributionImportService(scheduleService: scheduleService);
    });

    test('imports valid words and skips duplicates or invalid entries', () {
      final importedAt = DateTime(2026, 3, 13, 9, 30);
      final result = service.parseJson(
        jsonText: '''
{
  "schemaVersion": 1,
  "words": [
    {
      "word": "Space",
      "meaning": "太空",
      "memoryHint": "想到抬頭看夜空，整片都是 space。",
      "partOfSpeech": "noun",
      "sentences": ["The space is vast."],
      "customTags": ["課本A 第3課", "期中考", "課本A 第3課"]
    },
    {
      "word": "space",
      "meaning": "空間",
      "partOfSpeech": "noun",
      "sentences": ["We need more space."]
    },
    {
      "word": ""
    },
    "invalid"
  ]
}
''',
        existingWords: {'apple'},
        importedAt: importedAt,
      );

      expect(result.totalEntries, 4);
      expect(result.importedCount, 1);
      expect(result.skippedDuplicateCount, 1);
      expect(result.invalidCount, 2);

      final card = result.importedWords.single;
      expect(card.word, 'Space');
      expect(card.meaning, '太空');
      expect(card.memoryHint, '想到抬頭看夜空，整片都是 space。');
      expect(card.partOfSpeech, PartOfSpeech.noun);
      expect(card.sentences, ['The space is vast.']);
      expect(card.customTags, ['課本A 第3課', '期中考']);
      expect(card.origin, WordOrigin.manual);
      expect(card.createdAt, importedAt);
      expect(card.updatedAt, importedAt);
      expect(card.nextReviewDate, scheduleService.initialNextDate(importedAt));
    });

    test('throws on unsupported schema version', () {
      expect(
        () => service.parseJson(
          jsonText: '{"schemaVersion":2,"words":[]}',
          existingWords: const <String>{},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when words array is missing', () {
      expect(
        () => service.parseJson(
          jsonText: '{"schemaVersion":1}',
          existingWords: const <String>{},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
