import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/data/storage/learning_image_store.dart';
import 'package:yunxu_learning_english/domain/models/learning_image.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';

class MemoryCredentials implements LearningImageCredentials {
  String? key = 'test-key';
  @override
  Future<String?> load() async => key;
  @override
  Future<void> save(String value) async {
    key = value;
  }

  @override
  Future<void> delete() async {
    key = null;
  }
}

class MemoryStore implements LearningImageStore {
  final ledger = <String, LearningImageAttempt>{};
  final metadata = <String, LearningImageMetadata>{};
  LearningImageMode mode = LearningImageMode.precise;
  @override
  Future<List<LearningImageAttempt>> attempts() async => ledger.values.toList();
  @override
  Future<void> putAttempt(LearningImageAttempt attempt) async {
    ledger[attempt.id] = attempt;
  }

  @override
  Future<LearningImageMode> loadMode() async => mode;
  @override
  Future<void> saveMode(LearningImageMode value) async {
    mode = value;
  }

  @override
  Future<void> putMetadata(LearningImageMetadata value) async {
    metadata[value.wordId] = value;
  }

  @override
  Future<LearningImageMetadata?> metadataFor(String id) async => metadata[id];
}

WordCard word() => WordCard(
  id: 'w',
  word: 'chirp',
  meaning: '啾啾叫',
  sentences: ['Birds chirp.'],
  origin: WordOrigin.manual,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  reviewSchedule: [1],
  nextReviewIndex: 0,
  nextReviewDate: DateTime(2026),
  history: [],
  isDeleted: false,
);
const content = LearningImageContent(
  word: 'chirp',
  meaning: '啾啾叫',
  partsOfSpeech: 'verb',
  sentences: ['Birds chirp. 鳥兒啾啾叫。'],
  memoryHint: '小鳥',
  diagram: '聲音',
);
Map<String, Object?> researchResponse({String conflict = ''}) => {
  'usage': {
    'input_tokens': 100,
    'output_tokens': 100,
    'input_tokens_details': {'cached_tokens': 10},
  },
  'output': [
    {
      'type': 'web_search_call',
      'status': 'completed',
      'action': {'type': 'search'},
    },
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': jsonEncode({...content.toMap(), 'conflict': conflict}),
          'annotations': [
            {
              'type': 'url_citation',
              'title': 'Dictionary',
              'url': 'https://example.org/chirp',
            },
          ],
        },
      ],
    },
  ],
};
Map<String, Object?> imageResponse({String? encoded}) => {
  'usage': {
    'input_tokens': 100,
    'output_tokens': 200,
    'input_tokens_details': {'text_tokens': 100, 'image_tokens': 0},
  },
  'data': [
    {
      'b64_json': encoded ?? base64Encode([1, 2, 3]),
    },
  ],
};
http.Response response(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {
    'x-request-id': 'req-test',
    'content-type': 'application/json; charset=utf-8',
  },
);
void main() {
  test(
    'cost uses noncached input once and preserves historical fee snapshot',
    () {
      final cost = LearningImageCost.calculate('gpt-5.4-mini', {
        'input_tokens': 1000,
        'output_tokens': 100,
        'input_tokens_details': {'cached_tokens': 200},
      }, searches: 2);
      expect(cost.usd, closeTo(.021065, 1e-10));
      expect(cost.unknown, false);
      final attempt = LearningImageAttempt(
        id: 'a',
        model: 'gpt-5.4-mini',
        createdAt: DateTime(2026),
      );
      final restored = LearningImageAttempt.fromMap({
        ...attempt.toMap(),
        'usd': 42,
        'unknown': false,
        'rateDate': 'old',
      });
      expect(restored.cost.usd, 42);
      expect(restored.toMap()['rateDate'], 'old');
    },
  );
  test(
    'partial counts preserve known search/output; unknown rate stays unknown',
    () {
      expect(
        LearningImageCost.calculate('gpt-5.4-mini', null, searches: 2).usd,
        .02,
      );
      final partial = LearningImageCost.calculate('gpt-image-2.5-sunburst', {
        'output_tokens': 100,
        'input_tokens_details': 'invalid',
      });
      expect(partial.usd, .003);
      expect(partial.unknown, true);
      expect(
        LearningImageCost.calculate('unknown', {'output_tokens': 100}).unknown,
        true,
      );
    },
  );
  test('credentials save/delete and mode persistence', () async {
    final credentials = MemoryCredentials();
    final store = MemoryStore();
    final notifier = LearningImageNotifier(
      service: LearningImageService(
        client: MockClient((_) async => response({})),
      ),
      store: store,
      credentials: credentials,
    );
    await notifier.initialize();
    await notifier.deleteApiKey();
    expect(notifier.hasKey, false);
    await notifier.saveApiKey('new');
    expect(credentials.key, 'new');
    await notifier.setMode(LearningImageMode.fast);
    expect(store.mode, LearningImageMode.fast);
    notifier.dispose();
  });
  test(
    'generation records pending before dispatch and regenerate skips research',
    () async {
      final store = MemoryStore();
      var researchCalls = 0;
      var imageCalls = 0;
      final service = LearningImageService(
        client: MockClient((request) async {
          expect(store.ledger.values.last.status, 'pending');
          if (request.url.path.endsWith('responses')) {
            researchCalls++;
            return response(researchResponse());
          }
          imageCalls++;
          return response(imageResponse());
        }),
        validateImage: (Uint8List _) async {},
      );
      final notifier = LearningImageNotifier(
        service: service,
        store: store,
        credentials: MemoryCredentials(),
      );
      await notifier.start(word());
      expect(notifier.stage, LearningImageStage.ready);
      expect(notifier.sources.single.title, 'Dictionary');
      await notifier.regenerate();
      expect(researchCalls, 1);
      expect(imageCalls, 2);
      expect(store.ledger.length, 3);
      expect(notifier.hasUnknownCost, false);
      await notifier.saveMetadata(wordId: 'w', imageIdentity: 'image.png');
      expect((await notifier.metadataFor('w'))!.content.meaning, '啾啾叫');
      expect(
        jsonEncode(store.ledger.values.map((a) => a.toMap()).toList()),
        isNot(contains('test-key')),
      );
      notifier.dispose();
    },
  );
  test(
    'conflict waits for choice then existing meaning is preserved',
    () async {
      final service = LearningImageService(
        client: MockClient(
          (r) async => response(
            r.url.path.endsWith('responses')
                ? researchResponse(conflict: '詞義不同')
                : imageResponse(),
          ),
        ),
        validateImage: (_) async {},
      );
      final notifier = LearningImageNotifier(
        service: service,
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      await notifier.start(word());
      expect(notifier.stage, LearningImageStage.conflict);
      await notifier.resolveConflict(useExisting: true);
      expect(notifier.content!.meaning, word().meaning);
      expect(notifier.stage, LearningImageStage.ready);
      notifier.dispose();
    },
  );
  test('malformed image retains billed usage before decode failure', () async {
    final notifier = LearningImageNotifier(
      service: LearningImageService(
        client: MockClient(
          (r) async => response(
            r.url.path.endsWith('responses')
                ? researchResponse()
                : imageResponse(encoded: 'bad'),
          ),
        ),
      ),
      store: MemoryStore(),
      credentials: MemoryCredentials(),
    );
    await notifier.start(word());
    expect(notifier.stage, LearningImageStage.failed);
    expect(notifier.attempts.last.cost.usd, greaterThan(0));
    notifier.dispose();
  });
  test(
    'cancel prevents late result and duplicate dispatch while pending',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final notifier = LearningImageNotifier(
        service: LearningImageService(
          client: MockClient((_) {
            calls++;
            return pending.future;
          }),
        ),
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      final running = notifier.start(word());
      await Future<void>.delayed(Duration.zero);
      notifier.cancel();
      await notifier.start(word());
      expect(calls, 1);
      expect(notifier.isBusy, true);
      pending.complete(response(researchResponse()));
      await running;
      expect(notifier.stage, LearningImageStage.cancelled);
      expect(notifier.imageBytes, isNull);
      expect(notifier.attempts.single.cost.unknown, false);
      notifier.dispose();
    },
  );
  test(
    'timeout blocks another paid request until late result drains',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final notifier = LearningImageNotifier(
        service: LearningImageService(
          timeout: const Duration(milliseconds: 10),
          client: MockClient((_) {
            calls++;
            return pending.future;
          }),
        ),
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      await notifier.start(word());
      expect(notifier.stage, LearningImageStage.failed);
      expect(notifier.isBusy, true);
      expect(notifier.hasUnknownCost, true);
      await notifier.start(word());
      expect(calls, 1);
      pending.complete(response(researchResponse()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.isBusy, false);
      expect(notifier.imageBytes, isNull);
      notifier.dispose();
    },
  );
  test('apply lock preserves preview until image update completes', () async {
    final notifier = LearningImageNotifier(
      service: LearningImageService(
        client: MockClient(
          (r) async => response(
            r.url.path.endsWith('responses')
                ? researchResponse()
                : imageResponse(),
          ),
        ),
        validateImage: (_) async {},
      ),
      store: MemoryStore(),
      credentials: MemoryCredentials(),
    );
    await notifier.start(word());
    final bytes = notifier.imageBytes;
    expect(notifier.beginApply(), true);
    await notifier.start(word().copyWith(word: 'other'));
    await notifier.regenerate();
    notifier.discard();
    notifier.cancel();
    expect(notifier.imageBytes, same(bytes));
    expect(notifier.sourceWord!.word, 'chirp');
    expect(notifier.beginApply(), false);
    await notifier.saveMetadata(wordId: 'w', imageIdentity: 'applied.png');
    notifier.endApply();
    notifier.discard();
    expect(notifier.imageBytes, isNull);
    notifier.dispose();
  });
  test(
    'Hive local ledger upserts attempts and preserves source metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'learning-image-test',
      );
      Hive.init(directory.path);
      try {
        final store = HiveLearningImageStore();
        final first = LearningImageAttempt(
          id: 'a',
          model: 'gpt-5.4-mini',
          createdAt: DateTime(2026),
        );
        await store.putAttempt(first);
        await store.putAttempt(
          LearningImageAttempt(
            id: 'a',
            model: first.model,
            createdAt: first.createdAt,
            usage: {
              'input_tokens': 1,
              'output_tokens': 1,
              'input_tokens_details': {'cached_tokens': 0},
            },
            searches: 1,
            status: 'completed',
          ),
        );
        expect((await store.attempts()).length, 1);
        await store.putMetadata(
          LearningImageMetadata(
            wordId: 'w',
            imageIdentity: 'img',
            content: content,
            model: LearningImageMode.precise.model,
            createdAt: DateTime(2026),
          ),
        );
        expect((await store.metadataFor('w'))!.content.word, 'chirp');
        await store.saveMode(LearningImageMode.fast);
        expect(await store.loadMode(), LearningImageMode.fast);
      } finally {
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'malformed research with usage records counts and stops before image',
    () async {
      var calls = 0;
      final bad = researchResponse();
      (bad['output'] as List).last['content'][0]['text'] = 'not-json';
      final notifier = LearningImageNotifier(
        service: LearningImageService(
          client: MockClient((_) async {
            calls++;
            return response(bad);
          }),
        ),
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      await notifier.start(word());
      expect(notifier.stage, LearningImageStage.failed);
      expect(calls, 1);
      expect(notifier.hasUnknownCost, false);
      expect(notifier.knownCostUsd, greaterThan(.01));
      notifier.dispose();
    },
  );
  test('search accounting counts search but skips open and find', () async {
    final body = researchResponse();
    body['output'] = [
      ...body['output'] as List,
      {
        'type': 'web_search_call',
        'action': {'type': 'open_page'},
      },
      {
        'type': 'web_search_call',
        'action': {'type': 'find_in_page'},
      },
    ];
    int? searches;
    final service = LearningImageService(
      client: MockClient((_) async => response(body)),
    );
    await service.research(word(), 'key', (id, usage, count) async {
      searches = count;
    });
    expect(searches, 1);
    service.dispose();
  });
  for (final code in [401, 403, 429, 500]) {
    test('HTTP $code fails without retry or raw body leak', () async {
      var calls = 0;
      final notifier = LearningImageNotifier(
        service: LearningImageService(
          client: MockClient((_) async {
            calls++;
            return http.Response('{"error":{"message":"secret"}}', code);
          }),
        ),
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      await notifier.start(word());
      expect(notifier.stage, LearningImageStage.failed);
      expect(calls, 1);
      expect(notifier.error, isNot(contains('secret')));
      expect(notifier.hasUnknownCost, true);
      notifier.dispose();
    });
  }
}
