import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/word_bank_refresh_service.dart';

void main() {
  test(
    'matches only exact spelling after trimming and case normalization',
    () async {
      final service = WordBankRefreshService(
        lookup: (_) async => [entry('habits'), entry(' HABIT ')],
      );
      final result = await service.compare(card().copyWith(word: ' Habit '));
      expect(result.status, WordBankMatchStatus.matched);
      expect(result.entry!.word, ' HABIT ');
      expect(result.meaningChanged, isTrue);
      expect(result.sentencesChanged, isTrue);
      expect(result.partsOfSpeechChanged, isFalse);
    },
  );

  test(
    'rejects duplicate exact matches without choosing an arbitrary entry',
    () async {
      final service = WordBankRefreshService(
        lookup: (_) async => [entry('habit'), entry('HABIT')],
      );
      final result = await service.compare(card());
      expect(result.status, WordBankMatchStatus.ambiguous);
      expect(result.entry, isNull);
      expect(result.hasChanges, isFalse);
    },
  );

  test(
    'does not fall back to stems, similar spelling, or missing entries',
    () async {
      final service = WordBankRefreshService(
        lookup: (_) async => [entry('habits')],
      );
      expect(
        (await service.compare(card())).status,
        WordBankMatchStatus.notFound,
      );
    },
  );

  test(
    'manual, unknown and deleted cards never query the dictionary',
    () async {
      var calls = 0;
      final service = WordBankRefreshService(
        lookup: (_) async {
          calls++;
          return [entry('habit')];
        },
      );
      for (final value in [
        card().copyWith(origin: WordOrigin.manual),
        card().copyWith(origin: WordOrigin.unknown),
        card().copyWith(isDeleted: true),
      ]) {
        expect(
          (await service.compare(value)).status,
          WordBankMatchStatus.ineligible,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'comparison ignores surrounding whitespace but retains sentence order',
    () async {
      final service = WordBankRefreshService(
        lookup: (_) async => [entry('habit')],
      );
      final value = card().copyWith(
        meaning: ' 習慣；慣常的行為 ',
        sentences: [' I read every night. ', '', 'It is a good habit.'],
      );
      expect((await service.compare(value)).hasChanges, isFalse);
      final reordered = value.copyWith(
        sentences: value.sentences.reversed.toList(),
      );
      expect((await service.compare(reordered)).sentencesChanged, isTrue);
    },
  );

  test(
    'full dictionary sentence list is available, including new extra examples',
    () async {
      final service = WordBankRefreshService(
        lookup: (_) async => [entry('habit')],
      );
      final result = await service.compare(
        card().copyWith(
          meaning: '習慣；慣常的行為',
          sentences: ['I read every night.'],
        ),
      );
      expect(result.entry!.sentences, hasLength(2));
      expect(result.sentencesChanged, isTrue);
    },
  );

  test(
    'lookup failures remain retryable rather than looking like no changes',
    () async {
      var calls = 0;
      final service = WordBankRefreshService(
        lookup: (_) async {
          if (calls++ == 0) throw StateError('asset unavailable');
          return [entry('habit')];
        },
      );
      await expectLater(service.compare(card()), throwsStateError);
      expect(
        (await service.compare(card())).status,
        WordBankMatchStatus.matched,
      );
    },
  );
}

BuiltinWordEntry entry(String word) => BuiltinWordEntry(
  word: word,
  meaning: '習慣；慣常的行為',
  partsOfSpeech: const [PartOfSpeech.noun],
  sentences: const ['I read every night.', 'It is a good habit.'],
  sourcePage: 1,
  schoolLevels: const [],
  examTags: const [],
  audienceTags: const [],
  sourceTags: const [],
);

WordCard card() {
  final now = DateTime(2026, 11, 20);
  return WordCard(
    id: 'habit-card',
    word: 'habit',
    meaning: '習慣',
    partsOfSpeech: const [PartOfSpeech.noun],
    sentences: const ['Old example.'],
    origin: WordOrigin.builtinWordBank,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 3, 7],
    nextReviewIndex: 1,
    nextReviewDate: now,
    history: [now],
    reviewRatings: const [ReviewRating.hard],
    isDeleted: false,
  );
}
