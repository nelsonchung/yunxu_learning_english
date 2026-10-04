import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/domain/models/learning_image.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';

void main() {
  const content = LearningImageContent(
    word: 'chirp',
    meaning: '啾啾叫',
    partsOfSpeech: 'verb',
    sentences: [],
    memoryHint: '',
    diagram: '',
  );
  for (final mode in LearningImageMode.values) {
    test('known ${mode.model} snapshot retains accounting usage', () async {
      Map? recorded;
      final service = LearningImageService(
        client: MockClient((request) async {
          expect(jsonDecode(request.body)['model'], mode.model);
          return http.Response(
            jsonEncode({
              'model': '${mode.model}-2026-09-08',
              'data': [
                {
                  'b64_json': base64Encode([1, 2, 3]),
                },
              ],
              'usage': {
                'input_tokens': 100,
                'output_tokens': 200,
                'input_tokens_details': {'text_tokens': 100, 'image_tokens': 0},
              },
            }),
            200,
          );
        }),
        validateImage: (_) async {},
      );
      await service.generate(
        content,
        mode,
        'test-key',
        (_, usage, _) async => recorded = usage,
      );
      expect(recorded, isNotNull);
      expect(
        LearningImageCost.calculate(mode.model, recorded).unknown,
        isFalse,
      );
      service.dispose();
    });
  }
  test(
    'unrecognized response model is not charged at requested model rates',
    () async {
      Map? recorded;
      final service = LearningImageService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'model': 'unrecognized-image-model',
              'data': [
                {
                  'b64_json': base64Encode([1, 2, 3]),
                },
              ],
              'usage': {
                'input_tokens': 100,
                'output_tokens': 200,
                'input_tokens_details': {'text_tokens': 100, 'image_tokens': 0},
              },
            }),
            200,
          ),
        ),
        validateImage: (_) async {},
      );
      await service.generate(
        content,
        LearningImageMode.precise,
        'test-key',
        (_, usage, _) async => recorded = usage,
      );
      expect(recorded, isNull);
      expect(
        LearningImageCost.calculate(
          LearningImageMode.precise.model,
          recorded,
        ).unknown,
        isTrue,
      );
      service.dispose();
    },
  );
}
