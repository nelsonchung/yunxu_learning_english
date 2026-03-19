import 'package:flutter_test/flutter_test.dart';

import 'package:yunxu_learning_english/domain/models/app_settings.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/daily_word_recommendation_service.dart';

void main() {
  group('DailyWordRecommendationService', () {
    late DailyWordRecommendationService service;
    late AppSettings settings;
    late DateTime now;

    setUp(() {
      service = DailyWordRecommendationService();
      settings = AppSettings.defaults();
      now = DateTime(2026, 3, 19, 9);
    });

    test('returns empty when due count is above the configured threshold', () {
      final recommendations = service.recommend(
        entries: [
          _entry(
            word: 'apple',
            difficultyLevel: 2,
            partOfSpeech: PartOfSpeech.noun,
          ),
        ],
        existingWords: const [],
        settings: settings,
        dueTodayCount: 11,
        now: now,
      );

      expect(recommendations, isEmpty);
    });

    test('skips learned words and close variants', () {
      final entries = [
        _entry(
          word: 'work',
          difficultyLevel: 2,
          partOfSpeech: PartOfSpeech.verb,
        ),
        _entry(
          word: 'worked',
          difficultyLevel: 2,
          partOfSpeech: PartOfSpeech.verb,
        ),
        _entry(
          word: 'travel',
          difficultyLevel: 2,
          partOfSpeech: PartOfSpeech.verb,
        ),
        _entry(
          word: 'bright',
          difficultyLevel: 2,
          partOfSpeech: PartOfSpeech.adjective,
        ),
        _entry(
          word: 'apple',
          difficultyLevel: 2,
          partOfSpeech: PartOfSpeech.noun,
        ),
      ];
      final existingWords = [
        _card(word: 'work', partOfSpeech: PartOfSpeech.verb, createdAt: now),
      ];

      final recommendations = service.recommend(
        entries: entries,
        existingWords: existingWords,
        settings: settings,
        dueTodayCount: 3,
        now: now,
      );
      final recommendedWords = recommendations
          .map((entry) => entry.word)
          .toList();

      expect(recommendedWords, isNot(contains('work')));
      expect(recommendedWords, isNot(contains('worked')));
      expect(recommendedWords, containsAll(['travel', 'bright', 'apple']));
    });

    test(
      'prefers words close to the learner difficulty and mixes parts of speech',
      () {
        final entries = [
          _entry(
            word: 'calm',
            difficultyLevel: 3,
            partOfSpeech: PartOfSpeech.adjective,
          ),
          _entry(
            word: 'balance',
            difficultyLevel: 3,
            partOfSpeech: PartOfSpeech.noun,
          ),
          _entry(
            word: 'observe',
            difficultyLevel: 3,
            partOfSpeech: PartOfSpeech.verb,
          ),
          _entry(
            word: 'meticulous',
            difficultyLevel: 6,
            partOfSpeech: PartOfSpeech.adjective,
          ),
        ];
        final existingWords = [
          _card(
            word: 'steady',
            partOfSpeech: PartOfSpeech.adjective,
            createdAt: now,
          ),
          _card(
            word: 'journey',
            partOfSpeech: PartOfSpeech.noun,
            createdAt: now.subtract(const Duration(days: 1)),
          ),
        ];
        final entriesWithHistory = [
          ...entries,
          _entry(
            word: 'steady',
            difficultyLevel: 3,
            partOfSpeech: PartOfSpeech.adjective,
          ),
          _entry(
            word: 'journey',
            difficultyLevel: 3,
            partOfSpeech: PartOfSpeech.noun,
          ),
        ];

        final recommendations = service.recommend(
          entries: entriesWithHistory,
          existingWords: existingWords,
          settings: settings,
          dueTodayCount: 2,
          now: now,
        );

        expect(
          recommendations.map((entry) => entry.word),
          isNot(contains('meticulous')),
        );
        expect(
          recommendations.map((entry) => entry.partOfSpeech).toSet().length,
          3,
        );
      },
    );
  });
}

BuiltinWordEntry _entry({
  required String word,
  required int difficultyLevel,
  required PartOfSpeech partOfSpeech,
}) {
  return BuiltinWordEntry(
    word: word,
    meaning: '$word 的意思',
    partOfSpeech: partOfSpeech,
    sentences: [
      'We used $word in class today.',
      'I want to remember $word this week.',
    ],
    sourcePage: 1,
    schoolLevels: const [BuiltinSchoolLevel.seniorHigh],
    examTags: const [],
    audienceTags: const [BuiltinAudienceTag.general],
    sourceTags: const [BuiltinSourceTag.twCeec],
    difficultyLevel: difficultyLevel,
  );
}

WordCard _card({
  required String word,
  required PartOfSpeech partOfSpeech,
  required DateTime createdAt,
}) {
  return WordCard(
    id: word,
    word: word,
    meaning: '$word 的意思',
    partOfSpeech: partOfSpeech,
    sentences: const ['sample sentence'],
    origin: WordOrigin.builtinWordBank,
    createdAt: createdAt,
    updatedAt: createdAt,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: createdAt,
    history: const [],
    isDeleted: false,
  );
}
