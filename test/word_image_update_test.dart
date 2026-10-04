import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  late Directory directory;
  late _Storage storage;
  late _Repository repository;
  late WordsNotifier notifier;
  late WordCard original;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('word_image_test');
    storage = _Storage(directory);
    final now = DateTime(2026, 10, 4);
    original = WordCard(
      id: 'chirp',
      word: 'chirp',
      meaning: '啾啾叫',
      sentences: ['Birds chirp.'],
      partsOfSpeech: const [PartOfSpeech.verb],
      memoryHint: '小鳥叫聲',
      customTags: const ['動物'],
      origin: WordOrigin.manual,
      createdAt: now,
      updatedAt: now,
      reviewSchedule: const [1, 3, 7],
      nextReviewIndex: 0,
      nextReviewDate: now,
      history: const [],
      isDeleted: false,
      imagePath: '${directory.path}/old.png',
    );
    await File(original.imagePath!).writeAsBytes([1, 2, 3]);
    repository = _Repository(original);
    final schedule = ReviewScheduleService();
    notifier = WordsNotifier(
      repository: repository,
      scheduleService: schedule,
      sortService: SortService(),
      imageStorage: storage,
      wordContributionImportService: WordContributionImportService(
        scheduleService: schedule,
      ),
    );
    await notifier.load();
  });

  tearDown(() async {
    notifier.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'image-only commit preserves latest review state and deletes old image after commit',
    () async {
      await notifier.markReviewed(original);
      final before = notifier.findById(original.id)!;
      repository.onUpdate = (_) async {
        expect(await File(original.imagePath!).exists(), isTrue);
      };
      await notifier.updateWordImage(original.id, [
        4,
        5,
      ], expectedCard: original);
      final updated = notifier.findById(original.id)!;
      expect(updated.history, before.history);
      expect(updated.nextReviewIndex, before.nextReviewIndex);
      expect(updated.meaning, original.meaning);
      expect(updated.customTags, original.customTags);
      expect(updated.imagePath, endsWith('.png'));
      expect(updated.imageCleared, isFalse);
      expect(await File(original.imagePath!).exists(), isFalse);
    },
  );

  test(
    'repository failure retains old image and removes uncommitted file',
    () async {
      repository.onUpdate = (_) async => throw StateError('disk full');
      await expectLater(
        notifier.updateWordImage(original.id, [4, 5]),
        throwsStateError,
      );
      expect(notifier.findById(original.id)!.imagePath, original.imagePath);
      expect(await File(original.imagePath!).exists(), isTrue);
      expect(await directory.list().length, 1);
    },
  );

  test(
    'text edits during generation reject stale image even after replacement confirmation',
    () async {
      await notifier.updateWord(
        card: original,
        word: original.word,
        meaning: '新的意思',
        sentences: original.sentences,
        partsOfSpeech: original.partsOfSpeech,
      );
      await expectLater(
        notifier.updateWordImage(
          original.id,
          [4, 5],
          expectedCard: original,
          allowImageReplacement: true,
        ),
        throwsStateError,
      );
      expect(notifier.findById(original.id)!.meaning, '新的意思');
      expect(await directory.list().length, 1);
    },
  );

  test('changed image requires explicit replacement confirmation', () async {
    await notifier.updateWordImage(original.id, [4, 5]);
    await expectLater(
      notifier.updateWordImage(original.id, [6], expectedCard: original),
      throwsStateError,
    );
    await notifier.updateWordImage(
      original.id,
      [6],
      expectedCard: original,
      allowImageReplacement: true,
    );
    expect(
      await File(notifier.findById(original.id)!.imagePath!).readAsBytes(),
      [6],
    );
  });

  test('deleted words cannot receive generated images', () async {
    await notifier.deleteWord(original);
    await expectLater(
      notifier.updateWordImage(original.id, [4, 5]),
      throwsStateError,
    );
    expect(notifier.findById(original.id), isNull);
  });

  test(
    'queued text edit retains newly committed image and latest review data',
    () async {
      storage.saveGate = Completer<void>();
      final imageUpdate = notifier.updateWordImage(original.id, [4, 5]);
      await storage.started.future;
      final textUpdate = notifier.updateWord(
        card: original,
        word: original.word,
        meaning: '改寫意思',
        sentences: original.sentences,
        partsOfSpeech: original.partsOfSpeech,
      );
      storage.saveGate!.complete();
      await imageUpdate;
      final imagePath = notifier.findById(original.id)!.imagePath;
      await textUpdate;
      expect(notifier.findById(original.id)!.imagePath, imagePath);
      expect(notifier.findById(original.id)!.meaning, '改寫意思');
      expect(await File(imagePath!).exists(), isTrue);
    },
  );

  test(
    'old-file cleanup failure does not turn successful commit into failure',
    () async {
      storage.failOldDelete = original.imagePath;
      await notifier.updateWordImage(original.id, [4, 5]);
      expect(
        notifier.findById(original.id)!.imagePath,
        isNot(original.imagePath),
      );
    },
  );
}

class _Storage extends ImageStorage {
  _Storage(this.directory);
  final Directory directory;
  final started = Completer<void>();
  Completer<void>? saveGate;
  String? failOldDelete;
  int serial = 0;

  @override
  Future<String> saveBytes(List<int> bytes, {String extension = '.jpg'}) async {
    if (!started.isCompleted) started.complete();
    if (saveGate != null) await saveGate!.future;
    final file = File('${directory.path}/new${serial++}$extension');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> deleteImage(String pathValue) async {
    if (pathValue == failOldDelete) throw FileSystemException('cleanup failed');
    await super.deleteImage(pathValue);
  }
}

class _Repository implements WordRepository {
  _Repository(this.card);
  WordCard card;
  Future<void> Function(WordCard)? onUpdate;
  @override
  Future<void> update(WordCard value) async {
    await onUpdate?.call(value);
    card = value;
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async => [
    card,
  ];
  @override
  Future<List<WordCard>> fetchDue(DateTime day) async => [];
  @override
  Future<void> add(WordCard value) async => card = value;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int>) saveBytes,
  }) async => 0;
}
