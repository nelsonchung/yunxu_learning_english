import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/data/storage/learning_image_store.dart';
import 'package:yunxu_learning_english/domain/models/learning_image.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';
import 'learning_image_test.dart' as fixtures;

class BrokenCredentials extends fixtures.MemoryCredentials {
  @override
  Future<String?> load() async => throw StateError('locked');
}

class RetryStore extends fixtures.MemoryStore {
  bool fail = true;
  @override
  Future<List<LearningImageAttempt>> attempts() async {
    if (fail) throw StateError('disk');
    return super.attempts();
  }
}

class CancelBeforeDispatchStore extends fixtures.MemoryStore {
  void Function()? onPending;
  @override
  Future<void> putAttempt(LearningImageAttempt attempt) async {
    await super.putAttempt(attempt);
    if (attempt.status == 'pending') onPending?.call();
  }
}

class DelayedPendingStore extends fixtures.MemoryStore {
  final inserted = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> putAttempt(LearningImageAttempt attempt) async {
    await super.putAttempt(attempt);
    if (attempt.status == 'pending' && !inserted.isCompleted) {
      inserted.complete();
      await release.future;
    }
  }
}

LearningImageNotifier createNotifier({
  fixtures.MemoryStore? store,
  LearningImageCredentials? credentials,
  Duration timeout = const Duration(minutes: 5),
  required Future<http.Response> Function(http.Request) respond,
}) => LearningImageNotifier(
  service: LearningImageService(
    client: MockClient(respond),
    timeout: timeout,
    validateImage: (_) async {},
  ),
  store: store ?? fixtures.MemoryStore(),
  credentials: credentials ?? fixtures.MemoryCredentials(),
);
void main() {
  test(
    'legacy ledger has no fabricated association and outcome retains fee snapshot',
    () {
      final restored = LearningImageAttempt.fromMap({
        'id': 'old',
        'model': 'unknown',
        'createdAt': 0,
        'status': 'completed',
        'usd': 9.25,
        'unknown': false,
        'rateDate': 'historic',
      });
      expect(restored.word, isNull);
      expect(restored.generationId, isNull);
      expect(restored.outcome, isNull);
      final updated = restored.withOutcome('failed');
      expect(updated.cost.usd, 9.25);
      expect(updated.cost.unknown, false);
      expect(updated.rateDate, 'historic');
    },
  );
  test(
    'research and regenerations share flow while new start gets new flow',
    () async {
      final store = fixtures.MemoryStore();
      final notifier = createNotifier(
        store: store,
        respond: (r) async {
          final pending = store.ledger.values.last;
          expect(pending.wordId, 'w');
          expect(pending.word, 'chirp');
          expect(pending.outcome, 'inProgress');
          expect(pending.generationId, isNotNull);
          return fixtures.response(
            r.url.path.endsWith('responses')
                ? fixtures.researchResponse()
                : fixtures.imageResponse(),
          );
        },
      );
      await notifier.start(fixtures.word());
      await notifier.regenerate();
      expect(notifier.attempts.map((a) => a.generationId).toSet().length, 1);
      expect(notifier.attempts.every((a) => a.outcome == 'succeeded'), true);
      final first = notifier.attempts.first.generationId;
      await notifier.start(fixtures.word());
      expect(notifier.attempts.last.generationId, isNot(first));
      expect(notifier.attempts.length, 5);
      notifier.dispose();
    },
  );
  test('billed malformed research is failed rather than succeeded', () async {
    final bad = fixtures.researchResponse();
    (bad['output'] as List).last['content'][0]['text'] = 'invalid-json';
    final notifier = createNotifier(
      respond: (_) async => fixtures.response(bad),
    );
    await notifier.start(fixtures.word());
    expect(notifier.attempts.single.outcome, 'failed');
    expect(notifier.attempts.single.status, 'completed');
    expect(notifier.attempts.single.cost.usd, greaterThan(0));
    notifier.dispose();
  });
  for (final terminal in ['cancelled', 'timedOut']) {
    test(
      'late usage refines fee without replacing $terminal outcome',
      () async {
        final pending = Completer<http.Response>();
        final store = fixtures.MemoryStore();
        final notifier = createNotifier(
          store: store,
          timeout: terminal == 'timedOut'
              ? const Duration(milliseconds: 10)
              : const Duration(minutes: 5),
          respond: (_) => pending.future,
        );
        final running = notifier.start(fixtures.word());
        if (terminal == 'cancelled') {
          await Future<void>.delayed(Duration.zero);
          notifier.cancel();
        } else {
          await running;
        }
        expect(notifier.attempts.single.outcome, terminal);
        pending.complete(fixtures.response(fixtures.researchResponse()));
        await running;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(notifier.attempts.single.outcome, terminal);
        expect(store.ledger.values.single.outcome, terminal);
        expect(notifier.attempts.single.cost.unknown, false);
        expect(notifier.imageBytes, isNull);
        notifier.dispose();
      },
    );
  }
  test(
    'history loads despite unavailable secure credentials and retries storage',
    () async {
      final store = RetryStore();
      store.ledger['legacy'] = LearningImageAttempt(
        id: 'legacy',
        model: 'old',
        createdAt: DateTime(2026),
      );
      final notifier = createNotifier(
        store: store,
        credentials: BrokenCredentials(),
        respond: (_) async => throw StateError('must not call API'),
      );
      await notifier.initialize();
      expect(notifier.historyReady, true);
      expect(notifier.historyError, isNotNull);
      store.fail = false;
      await notifier.refreshHistory();
      expect(notifier.historyError, isNull);
      expect(notifier.attempts.single.id, 'legacy');
      notifier.dispose();
    },
  );
  test(
    'cancel before dispatch persists notSent with associations and zero fee',
    () async {
      final store = CancelBeforeDispatchStore();
      var calls = 0;
      final notifier = createNotifier(
        store: store,
        respond: (_) async {
          calls++;
          return fixtures.response(fixtures.researchResponse());
        },
      );
      store.onPending = notifier.cancel;
      await notifier.start(fixtures.word());
      final saved = store.ledger.values.single;
      expect(calls, 0);
      expect(saved.outcome, 'notSent');
      expect(saved.wordId, 'w');
      expect(saved.word, 'chirp');
      expect(saved.generationId, isNotNull);
      expect(saved.cost.unknown, false);
      expect(saved.cost.usd, 0);
      notifier.dispose();
    },
  );
  test(
    'refresh during pending persistence upserts once without double charge',
    () async {
      final store = DelayedPendingStore();
      final notifier = createNotifier(
        store: store,
        respond: (_) async =>
            fixtures.response(fixtures.researchResponse(conflict: 'review')),
      );
      final running = notifier.start(fixtures.word());
      await store.inserted.future;
      await notifier.refreshHistory();
      expect(notifier.attempts.length, 1);
      store.release.complete();
      await running;
      expect(notifier.attempts.length, 1);
      expect(notifier.attempts.single.outcome, 'succeeded');
      expect(notifier.knownCostUsd, store.ledger.values.single.cost.usd);
      expect(notifier.currentCostUsd, notifier.knownCostUsd);
      notifier.dispose();
    },
  );
  test(
    'cancel after refresh marks active pending id not unrelated last record',
    () async {
      final store = DelayedPendingStore();
      var calls = 0;
      final notifier = createNotifier(
        store: store,
        respond: (_) async {
          calls++;
          return fixtures.response(fixtures.researchResponse());
        },
      );
      final running = notifier.start(fixtures.word());
      await store.inserted.future;
      final activeId = store.ledger.keys.single;
      final unrelated = LearningImageAttempt(
        id: 'unrelated',
        model: 'old',
        createdAt: DateTime(2020),
        savedCost: const LearningImageCost(usd: 4, unknown: false),
      );
      store.ledger[unrelated.id] = unrelated;
      await notifier.refreshHistory();
      notifier.cancel();
      store.release.complete();
      await running;
      expect(calls, 0);
      expect(notifier.attempts.length, 2);
      final skipped = notifier.attempts.firstWhere((a) => a.id == activeId);
      expect(skipped.outcome, 'notSent');
      expect(skipped.wordId, 'w');
      expect(skipped.cost.usd, 0);
      expect(
        notifier.attempts.firstWhere((a) => a.id == unrelated.id).cost.usd,
        4,
      );
      expect(store.ledger[unrelated.id]!.outcome, isNull);
      notifier.dispose();
    },
  );
  test(
    'Hive close and reopen retains association and historical fee',
    () async {
      final dir = await Directory.systemTemp.createTemp('history-ledger-');
      Hive.init(dir.path);
      try {
        final store = HiveLearningImageStore();
        await store.putAttempt(
          LearningImageAttempt(
            id: 'new',
            model: 'old',
            createdAt: DateTime(2026),
            wordId: 'w',
            word: 'chirp',
            generationId: 'g',
            outcome: 'failed',
            savedCost: const LearningImageCost(usd: 7.5, unknown: false),
            rateDate: 'old-rate',
          ),
        );
        await Hive.close();
        final loaded = (await store.attempts()).single;
        expect(loaded.wordId, 'w');
        expect(loaded.word, 'chirp');
        expect(loaded.generationId, 'g');
        expect(loaded.outcome, 'failed');
        expect(loaded.cost.usd, 7.5);
        expect(loaded.rateDate, 'old-rate');
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
