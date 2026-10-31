import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/domain/models/ai_provider.dart';
import 'package:yunxu_learning_english/domain/models/sentence_level.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';

http.Response _response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

WordCard _word() => WordCard(
  id: 'word',
  word: 'chirp',
  meaning: '啾啾叫',
  sentences: [],
  origin: WordOrigin.manual,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  reviewSchedule: [1],
  nextReviewIndex: 0,
  nextReviewDate: DateTime(2026),
  history: [],
  isDeleted: false,
);

final _sentences = {
  'sentences': [
    {'english': 'Birds chirp.', 'translation': '鳥兒啾啾叫。'},
    {'english': 'Can you hear it chirp?', 'translation': '你聽得到牠啾啾叫嗎？'},
    {'english': 'It does not chirp at night.', 'translation': '牠晚上不會啾啾叫。'},
  ],
};

Map<String, Object?> _message({
  String stopReason = 'end_turn',
  List<Map<String, Object?>>? content,
}) => {
  'model': 'claude-sonnet-4-6',
  'stop_reason': stopReason,
  'usage': {
    'input_tokens': 100,
    'output_tokens': 200,
    'cache_read_input_tokens': 10,
    'private_text': 'must not persist',
    'server_tool_use': {'web_search_requests': 1},
  },
  'content':
      content ??
      [
        {'type': 'text', 'text': jsonEncode(_sentences)},
      ],
};

Future<void> _record(String? id, Map? usage, int? searches) async {}

void main() {
  test(
    'Claude uses Messages authentication, schema and shared level prompts',
    () async {
      String? recordedId;
      Map? recordedUsage;
      final service = LearningImageService(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.anthropic.com/v1/messages',
          );
          expect(request.headers['x-api-key'], 'claude-key');
          expect(request.headers['authorization'], isNull);
          expect(request.headers['anthropic-version'], '2023-06-01');
          expect(
            request.headers['anthropic-dangerous-direct-browser-access'],
            'true',
          );
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'claude-sonnet-4-6');
          expect(body['system'], contains(SentenceLevel.elementary.guidance));
          expect(body['messages'][0]['role'], 'user');
          expect(jsonDecode(body['messages'][0]['content'])['word'], 'chirp');
          expect(body['output_config']['format']['type'], 'json_schema');
          final schema = body['output_config']['format']['schema'];
          expect(
            schema['properties']['sentences'].containsKey('minItems'),
            false,
          );
          expect(
            schema['properties']['sentences'].containsKey('maxItems'),
            false,
          );
          expect(body.containsKey('tools'), false);
          return _response(
            jsonEncode(_message()),
            200,
            headers: {'request-id': 'request-1'},
          );
        }),
      );
      addTearDown(service.dispose);
      final result = await service.generateSentences(
        _word(),
        SentenceLevel.elementary,
        'claude-key',
        (id, usage, searches) async {
          recordedId = id;
          recordedUsage = usage;
          expect(searches, 0);
        },
        provider: AiProvider.claude,
      );
      expect(result, hasLength(3));
      expect(result.first, 'Birds chirp.\n鳥兒啾啾叫。');
      expect(recordedId, 'request-1');
      expect(recordedUsage, {
        'input_tokens': 100,
        'output_tokens': 200,
        'cache_read_input_tokens': 10,
      });
    },
  );

  for (final reason in ['max_tokens', 'refusal', 'pause_turn', 'tool_use']) {
    test(
      'Claude rejects incomplete stop reason $reason after accounting',
      () async {
        var recorded = false;
        final service = LearningImageService(
          client: MockClient(
            (_) async =>
                _response(jsonEncode(_message(stopReason: reason)), 200),
          ),
        );
        addTearDown(service.dispose);
        await expectLater(
          service.generateSentences(_word(), SentenceLevel.elementary, 'key', (
            _,
            _,
            _,
          ) async {
            recorded = true;
          }, provider: AiProvider.claude),
          throwsA(isA<LearningImageException>()),
        );
        expect(recorded, true);
        expect(service.isDispatching, false);
      },
    );
  }

  test('Claude validates exactly three complete bilingual examples', () async {
    final service = LearningImageService(
      client: MockClient(
        (_) async => _response(
          jsonEncode(
            _message(
              content: [
                {'type': 'text', 'text': '{"sentences": []}'},
              ],
            ),
          ),
          200,
        ),
      ),
    );
    addTearDown(service.dispose);
    await expectLater(
      service.generateSentences(
        _word(),
        SentenceLevel.elementary,
        'key',
        _record,
        provider: AiProvider.claude,
      ),
      throwsA(isA<LearningImageException>()),
    );
  });

  test(
    'Claude research extracts actual sources and excludes search preamble',
    () async {
      final service = LearningImageService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('output_config'), false);
          expect(body['tools'], [
            {
              'type': 'web_search_20250305',
              'name': 'web_search',
              'max_uses': 4,
            },
          ]);
          return _response(
            jsonEncode(
              _message(
                content: [
                  {'type': 'text', 'text': 'I will search.'},
                  {
                    'type': 'server_tool_use',
                    'name': 'web_search',
                    'id': 'search-1',
                  },
                  {
                    'type': 'web_search_tool_result',
                    'tool_use_id': 'search-1',
                    'content': [
                      {
                        'type': 'web_search_result',
                        'title': 'Dictionary',
                        'url': 'https://example.com/chirp',
                      },
                      {
                        'type': 'web_search_result',
                        'title': 'Unsafe',
                        'url': 'javascript:alert(1)',
                      },
                    ],
                  },
                  {
                    'type': 'text',
                    'text': jsonEncode({
                      'word': 'chirp',
                      'meaning': '啾啾叫',
                      'partsOfSpeech': 'verb',
                      'sentences': ['Birds chirp. 鳥兒啾啾叫。'],
                      'memoryHint': '小鳥',
                      'diagram': '聲音',
                      'conflict': '',
                    }),
                  },
                ],
              ),
            ),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      final result = await service.research(_word(), 'key', (
        _,
        _,
        searches,
      ) async {
        expect(searches, 1);
      }, provider: AiProvider.claude);
      expect(result.meaning, '啾啾叫');
      expect(result.sources, hasLength(1));
      expect(result.sources.single.url, 'https://example.com/chirp');
    },
  );

  for (final content in [
    [
      {'type': 'text', 'text': '{}'},
    ],
    [
      {
        'type': 'web_search_tool_result',
        'content': {
          'type': 'web_search_tool_result_error',
          'error_code': 'unavailable',
        },
      },
    ],
  ]) {
    test(
      'Claude research requires successful web search results $content',
      () async {
        final service = LearningImageService(
          client: MockClient(
            (_) async => _response(jsonEncode(_message(content: content)), 200),
          ),
        );
        addTearDown(service.dispose);
        await expectLater(
          service.research(
            _word(),
            'key',
            _record,
            provider: AiProvider.claude,
          ),
          throwsA(isA<LearningImageException>()),
        );
      },
    );
  }

  test(
    'Claude authentication errors never expose returned server text',
    () async {
      var recorded = false;
      final service = LearningImageService(
        client: MockClient(
          (_) async => _response('{"error":{"message":"secret-key"}}', 401),
        ),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.generateSentences(_word(), SentenceLevel.elementary, 'key', (
          _,
          usage,
          _,
        ) async {
          recorded = true;
          expect(usage, isNull);
        }, provider: AiProvider.claude),
        throwsA(
          isA<LearningImageException>().having(
            (e) => e.message,
            'message',
            'Claude API Key 無效，請重新設定。',
          ),
        ),
      );
      expect(recorded, true);
    },
  );

  test(
    'default provider retains OpenAI Responses endpoint and schema',
    () async {
      final service = LearningImageService(
        client: MockClient((request) async {
          expect(request.url.host, 'api.openai.com');
          expect(request.url.path, '/v1/responses');
          expect(request.headers['authorization'], 'Bearer openai-key');
          expect(request.headers['x-api-key'], isNull);
          expect(
            jsonDecode(
              request.body,
            )['text']['format']['schema']['properties']['sentences']['minItems'],
            3,
          );
          return _response(
            jsonEncode({
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': jsonEncode(_sentences)},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      expect(
        await service.generateSentences(
          _word(),
          SentenceLevel.elementary,
          'openai-key',
          _record,
        ),
        hasLength(3),
      );
    },
  );
}
