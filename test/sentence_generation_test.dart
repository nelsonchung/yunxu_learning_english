import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/domain/models/sentence_level.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';

import 'learning_image_test.dart' show MemoryCredentials, MemoryStore, word;

Map<String, Object?> response({bool malformed = false}) => {
  'status': 'completed',
  'usage': {
    'input_tokens': 100,
    'output_tokens': 100,
    'input_tokens_details': {'cached_tokens': 0},
  },
  'output': [
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': jsonEncode({
            'sentences': List.generate(
              3,
              (i) => {
                'english': malformed ? '' : 'Birds chirp $i.',
                'translation': '鳥兒啾啾叫 $i。',
              },
            ),
          }),
        },
      ],
    },
  ],
};

void main() {
  for (final level in SentenceLevel.values) {
    test(
      '${level.label} passes level guidance and preserves sense; accounts without searches',
      () async {
        final service = LearningImageService(
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            expect(body['instructions'], contains(level.guidance));
            final input = jsonDecode(body['input']) as Map;
            expect(input['meaning'], word().meaning);
            expect(input['existingSentences'], word().sentences);
            expect(body.containsKey('tools'), isFalse);
            expect(body['text']['format']['strict'], isTrue);
            return http.Response(
              jsonEncode(response()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(service.dispose);
        var recorded = false;
        final sentences = await service.generateSentences(
          word(),
          level,
          'key',
          (id, usage, searches) async {
            recorded = true;
            expect(searches, 0);
            expect(usage?['input_tokens'], 100);
          },
        );
        expect(sentences, hasLength(3));
        expect(sentences.first, 'Birds chirp 0.\n鳥兒啾啾叫 0。');
        expect(recorded, isTrue);
      },
    );
  }

  test(
    'malformed sentences are rejected and failed request is recorded',
    () async {
      final store = MemoryStore();
      final ai = LearningImageNotifier(
        service: LearningImageService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(response(malformed: true)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
        store: store,
        credentials: MemoryCredentials(),
      );
      addTearDown(ai.dispose);
      final stage = ai.stage;
      expect(
        await ai.generateSentences(word(), SentenceLevel.elementary),
        isNull,
      );
      expect(ai.error, contains('例句回應不完整'));
      expect(ai.stage, stage);
      expect(store.ledger.values.single.outcome, 'failed');
    },
  );

  test('missing key dispatches no request', () async {
    var calls = 0;
    final ai = LearningImageNotifier(
      service: LearningImageService(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      ),
      store: MemoryStore(),
      credentials: MemoryCredentials()..key = null,
    );
    addTearDown(ai.dispose);
    expect(
      await ai.generateSentences(word(), SentenceLevel.professional),
      isNull,
    );
    expect(calls, 0);
    expect(ai.error, contains('API Key'));
  });
}
