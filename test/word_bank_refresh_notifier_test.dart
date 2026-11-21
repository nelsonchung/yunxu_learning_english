import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/cloud_sync_service.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_bank_refresh_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

import 'word_bank_refresh_service_test.dart' as fixtures;

void main() {
  late _Repository repository;
  late WordsNotifier notifier;
  late WordCard original;
  late WordBankComparison comparison;

  Future<void> initialize({CloudSyncService? cloud}) async {
    final schedule = ReviewScheduleService();
    notifier = WordsNotifier(
      repository: repository,
      scheduleService: schedule,
      sortService: SortService(),
      imageStorage: ImageStorage(),
      wordContributionImportService: WordContributionImportService(
        scheduleService: schedule,
      ),
      syncService: cloud,
    );
    await notifier.load();
  }

  setUp(() async {
    original = fixtures.card().copyWith(
      memoryHint: '自己的記憶方式',
      customTags: ['個人標籤'],
      imagePath: 'images/keep.png',
      imageBytes: [1, 2, 3],
      imageCleared: true,
      history: [
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 10),
      ],
      reviewRatings: [
        ReviewRating.forgot,
        ReviewRating.hard,
        ReviewRating.good,
      ],
    );
    repository = _Repository(original);
    comparison = await WordBankRefreshService(
      lookup: (_) async => [fixtures.entry('habit')],
    ).compare(original);
    await initialize();
  });

  tearDown(() => notifier.dispose());

  test(
    'selected content changes preserve every other persisted field',
    () async {
      final changed = await notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: comparison.entry!.meaning,
        sentences: comparison.entry!.sentences,
        partsOfSpeech: [PartOfSpeech.noun, PartOfSpeech.verb],
      );
      expect(changed, isTrue);
      final updated = notifier.findById(original.id)!;
      final expected = original.toMap();
      final actual = updated.toMap();
      for (final key in [
        'updatedAt',
        'meaning',
        'sentences',
        'partsOfSpeech',
        'partOfSpeech',
      ]) {
        expected.remove(key);
        actual.remove(key);
      }
      expect(actual, expected);
      expect(updated.meaning, comparison.entry!.meaning);
      expect(repository.updates, 1);
      expect(repository.card.id, original.id);
    },
  );

  test(
    'meaning-only edit retains all existing sentences and parts of speech',
    () async {
      await notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: '  自訂說明  ',
      );
      expect(repository.card.meaning, '自訂說明');
      expect(repository.card.sentences, original.sentences);
      expect(repository.card.partsOfSpeech, original.partsOfSpeech);
    },
  );

  test(
    'review completed after preview is retained when applying text',
    () async {
      await notifier.markReviewed(original, rating: ReviewRating.easy);
      final latest = notifier.findById(original.id)!;
      await notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: '新說明',
      );
      final actual = notifier.findById(original.id)!;
      expect(actual.history, latest.history);
      expect(actual.reviewRatings, latest.reviewRatings);
      expect(actual.nextReviewDate, latest.nextReviewDate);
      expect(actual.nextReviewIndex, latest.nextReviewIndex);
      expect(actual.reviewState, latest.reviewState);
    },
  );

  for (final mastered in [false, true]) {
    test(
      'refresh preserves completed schedule and mastered=$mastered',
      () async {
        notifier.dispose();
        original = original.copyWith(
          nextReviewIndex: original.reviewSchedule.length,
          reviewState: mastered
              ? WordReviewState.mastered
              : WordReviewState.active,
          masteredAt: mastered ? DateTime(2026, 11, 15) : null,
        );
        repository.card = original;
        await initialize();
        comparison = WordBankComparison(
          card: original,
          entry: fixtures.entry('habit'),
          status: WordBankMatchStatus.matched,
        );
        await notifier.applyWordBankRefresh(
          comparison: comparison,
          meaning: '新說明',
        );
        expect(repository.card.nextReviewIndex, original.nextReviewIndex);
        expect(repository.card.reviewState, original.reviewState);
        expect(repository.card.masteredAt, original.masteredAt);
      },
    );
  }

  test('stale text preview is rejected after another edit', () async {
    await notifier.updateWord(
      card: original,
      word: original.word,
      meaning: '手動修正',
      sentences: original.sentences,
      partsOfSpeech: original.partsOfSpeech,
    );
    await expectLater(
      notifier.applyWordBankRefresh(comparison: comparison, meaning: '舊預覽'),
      throwsStateError,
    );
    expect(repository.card.meaning, '手動修正');
    expect(repository.updates, 1);
  });

  test('deleted card cannot be resurrected by its open preview', () async {
    await notifier.deleteWord(original);
    await expectLater(
      notifier.applyWordBankRefresh(comparison: comparison, meaning: '新說明'),
      throwsStateError,
    );
    expect(repository.card.isDeleted, isTrue);
    expect(repository.updates, 1);
  });

  test(
    'ineligible, missing, ambiguous and mismatched previews never write',
    () async {
      for (final value in [
        WordBankComparison(
          card: original,
          status: WordBankMatchStatus.notFound,
        ),
        WordBankComparison(
          card: original,
          status: WordBankMatchStatus.ambiguous,
        ),
        WordBankComparison(
          card: original,
          status: WordBankMatchStatus.ineligible,
        ),
        WordBankComparison(
          card: original,
          entry: fixtures.entry('habits'),
          status: WordBankMatchStatus.matched,
        ),
      ]) {
        await expectLater(
          notifier.applyWordBankRefresh(comparison: value, meaning: '新說明'),
          throwsStateError,
        );
      }
      expect(repository.updates, 0);
    },
  );

  test('manual card is rejected even with a forged matched preview', () async {
    notifier.dispose();
    repository.card = original.copyWith(origin: WordOrigin.manual);
    await initialize();
    final forged = WordBankComparison(
      card: repository.card,
      entry: fixtures.entry('habit'),
      status: WordBankMatchStatus.matched,
    );
    await expectLater(
      notifier.applyWordBankRefresh(comparison: forged, meaning: '新說明'),
      throwsStateError,
    );
    expect(repository.updates, 0);
  });

  test(
    'retaining all fields or selecting identical contents is a no-op',
    () async {
      expect(
        await notifier.applyWordBankRefresh(comparison: comparison),
        isFalse,
      );
      expect(
        await notifier.applyWordBankRefresh(
          comparison: comparison,
          meaning: original.meaning,
          sentences: original.sentences,
          partsOfSpeech: original.partsOfSpeech,
        ),
        isFalse,
      );
      expect(repository.updates, 0);
      expect(repository.card.updatedAt, original.updatedAt);
    },
  );

  test(
    'blank edited meaning or sentence list cannot clear required content',
    () async {
      await expectLater(
        notifier.applyWordBankRefresh(comparison: comparison, meaning: '  '),
        throwsArgumentError,
      );
      await expectLater(
        notifier.applyWordBankRefresh(
          comparison: comparison,
          sentences: ['', ' '],
        ),
        throwsArgumentError,
      );
      expect(repository.updates, 0);
    },
  );

  test('disk failure retains card and allows retry', () async {
    repository.onUpdate = (_) async => throw StateError('disk full');
    await expectLater(
      notifier.applyWordBankRefresh(comparison: comparison, meaning: '新說明'),
      throwsStateError,
    );
    expect(notifier.findById(original.id)!.toMap(), original.toMap());
    expect(repository.card.toMap(), original.toMap());
    expect(notifier.isRefreshingWordBank, isFalse);
    repository.onUpdate = null;
    expect(
      await notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: '新說明',
      ),
      isTrue,
    );
  });

  for (final restoring in [false, true]) {
    test(
      'refresh rejects while ${restoring ? 'restore' : 'sync'} is in progress',
      () async {
        notifier.dispose();
        final cloud = _Cloud();
        await initialize(cloud: cloud);
        final operation = restoring
            ? notifier.restoreNow()
            : notifier.syncNow();
        await cloud.started.future;
        await expectLater(
          notifier.applyWordBankRefresh(comparison: comparison, meaning: '新說明'),
          throwsStateError,
        );
        expect(repository.updates, 0);
        cloud.gate.complete(true);
        await operation;
      },
    );
  }

  test(
    'sync is deferred and restore blocked until a refresh write completes',
    () async {
      notifier.dispose();
      final cloud = _Cloud();
      await initialize(cloud: cloud);
      final writeStarted = Completer<void>();
      final writeGate = Completer<void>();
      repository.onUpdate = (_) async {
        writeStarted.complete();
        await writeGate.future;
      };
      final update = notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: '新說明',
      );
      await writeStarted.future;
      expect(notifier.isRefreshingWordBank, isTrue);
      expect(await notifier.syncNow(), isFalse);
      expect(await notifier.restoreNow(), isFalse);
      expect(cloud.calls, 0);
      writeGate.complete();
      await update;
      await cloud.started.future;
      expect(repository.card.meaning, '新說明');
      expect(cloud.calls, 1);
      cloud.gate.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.isSyncing, isFalse);
    },
  );

  test(
    'one sync observes both refresh and a review queued behind it',
    () async {
      notifier.dispose();
      final cloud = _Cloud();
      await initialize(cloud: cloud);
      final writeStarted = Completer<void>();
      final writeGate = Completer<void>();
      repository.onUpdate = (_) async {
        if (repository.updates == 0) {
          writeStarted.complete();
          await writeGate.future;
        }
      };
      WordCard? syncedCard;
      cloud.onRun = () => syncedCard = repository.card;

      final update = notifier.applyWordBankRefresh(
        comparison: comparison,
        meaning: '更新後的意思',
      );
      await writeStarted.future;
      final review = notifier.markReviewed(original, rating: ReviewRating.hard);
      expect(await notifier.syncNow(), isFalse);
      expect(cloud.calls, 0);
      writeGate.complete();
      await update;
      await review;
      await cloud.started.future;

      expect(repository.updates, 2);
      expect(cloud.calls, 1);
      expect(syncedCard!.meaning, '更新後的意思');
      expect(syncedCard!.history, hasLength(original.history.length + 1));
      expect(syncedCard!.reviewRatings.last, ReviewRating.hard);
      expect(syncedCard!.history, repository.card.history);
      cloud.gate.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.isSyncing, isFalse);
      expect(cloud.calls, 1);
    },
  );

  test(
    'confirmed lists are copied before waiting for an earlier mutation',
    () async {
      final writeStarted = Completer<void>();
      final writeGate = Completer<void>();
      repository.onUpdate = (_) async {
        if (repository.updates == 0) {
          writeStarted.complete();
          await writeGate.future;
        }
      };
      final review = notifier.markReviewed(original);
      await writeStarted.future;
      final selectedSentences = ['The confirmed example.'];
      final selectedParts = [PartOfSpeech.noun, PartOfSpeech.verb];
      final update = notifier.applyWordBankRefresh(
        comparison: comparison,
        sentences: selectedSentences,
        partsOfSpeech: selectedParts,
      );
      selectedSentences[0] = 'A later unconfirmed edit.';
      selectedParts.clear();
      writeGate.complete();
      await review;
      await update;

      expect(repository.card.sentences, ['The confirmed example.']);
      expect(repository.card.partsOfSpeech, [
        PartOfSpeech.noun,
        PartOfSpeech.verb,
      ]);
      expect(repository.card.history, hasLength(original.history.length + 1));
    },
  );
}

class _Repository implements WordRepository {
  _Repository(this.card);
  WordCard card;
  int updates = 0;
  Future<void> Function(WordCard)? onUpdate;

  @override
  Future<void> update(WordCard value) async {
    await onUpdate?.call(value);
    updates++;
    card = value;
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async =>
      includeDeleted || !card.isDeleted ? [card] : [];
  @override
  Future<List<WordCard>> fetchDue(DateTime day) async => [];
  @override
  Future<void> add(WordCard value) async =>
      throw StateError('refresh must never add');
  @override
  Future<void> delete(String id) async =>
      throw StateError('refresh must never delete');
  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int>) saveBytes,
  }) async => 0;
}

class _Cloud implements CloudSyncService {
  final started = Completer<void>();
  final gate = Completer<bool>();
  int calls = 0;
  void Function()? onRun;
  Future<bool> _run() {
    calls++;
    onRun?.call();
    if (!started.isCompleted) started.complete();
    return gate.future;
  }

  @override
  Future<bool> sync() => _run();
  @override
  Future<bool> restoreNow() => _run();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
