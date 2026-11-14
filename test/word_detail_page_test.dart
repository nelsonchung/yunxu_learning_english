import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/services/word_extension_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/domain/services/online_picture_service.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';
import 'learning_image_test.dart' show MemoryCredentials, MemoryStore;
import 'sentence_generation_test.dart' show response;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yunxu_learning_english/data/repositories/settings_repository.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/app_settings.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/notification_service.dart';
import 'package:yunxu_learning_english/domain/services/pronunciation_service.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/voice_practice_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/word_detail_page.dart';
import 'package:yunxu_learning_english/presentation/state/settings_notifier.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final guided in [true, false]) {
    testWidgets(
      'iOS ${guided ? '引導練習兩句' : '情境對話三輪'}完成後顯示回饋',
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
      (tester) async {
        const channel = MethodChannel('voice_practice');
        const microphone = MethodChannel('voice_practice/microphone');
        final messenger = tester.binding.defaultBinaryMessenger;
        final audioCalls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          audioCalls.add(call.method);
          return null;
        });
        messenger.setMockMethodCallHandler(microphone, (_) async => null);
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(microphone, null);
        });

        final socket = _FakeLiveSocket();
        final requests = <Map<String, dynamic>>[];
        final credentials = MemoryCredentials()..key = null;
        final history = MemoryStore();
        final service = VoicePracticeService(
          loadOpenAiKey: credentials.load,
          saveAttempt: history.putAttempt,
          connectSocket: (uri, headers) async {
            expect(uri.toString(), 'wss://api.openai.com/v1/live/sessions');
            expect(headers['Authorization'], 'Bearer test-openai-key');
            return socket;
          },
          client: MockClient.streaming((request, _) async {
            expect(
              request.url.toString(),
              'https://api.openai.com/v1/responses',
            );
            expect(request.headers['authorization'], 'Bearer test-openai-key');
            final body =
                jsonDecode((request as http.Request).body)
                    as Map<String, dynamic>;
            expect(body['store'], isFalse);
            requests.add(
              jsonDecode(body['input'] as String) as Map<String, dynamic>,
            );
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'status': 'completed',
                    'model': 'gpt-6-luna',
                    'usage': {
                      'input_tokens': 1000,
                      'output_tokens': 100,
                      'input_tokens_details': {'cached_tokens': 100},
                    },
                    'output': [
                      {
                        'type': 'message',
                        'content': [
                          {
                            'type': 'output_text',
                            'text': jsonEncode({
                              'feedback': '搭配 make a reservation 很自然。',
                              'example':
                                  'I’d like to make a reservation for two.',
                            }),
                          },
                        ],
                      },
                    ],
                  }),
                ),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(service.dispose);
        final card = _wordCard(
          id: 'voice-test',
          word: 'reservation',
        ).copyWith(meaning: '預訂；保留');
        final words = _buildWordsNotifier(initialCards: [card]);
        addTearDown(words.dispose);
        await words.load();
        await _pumpDetailPage(
          tester,
          wordsNotifier: words,
          wordId: card.id,
          voicePractice: service,
        );

        Future<void> tap(String label) async {
          final button = find.text(label);
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await tap('AI 口說練習');
        expect(find.byType(TextField), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '引導練習'))
              .selected,
          isTrue,
        );
        if (!guided) await tap('情境對話');
        await tap('開始即時練習');
        expect(find.text('請先設定 OpenAI API Key。'), findsOneWidget);
        await credentials.save('test-openai-key');
        await tap('開始即時練習');
        expect(socket.sent.single['type'], 'session.start');
        expect(socket.sent.single['session']['model'], 'gpt-live-1');
        expect(
          socket.sent.single['session']['instructions'],
          contains(
            guided
                ? 'give a different everyday situation'
                : 'After three learner answers',
          ),
        );
        if (guided) {
          expect(
            socket.sent.single['session']['input'].toString(),
            contains('say one English example'),
          );
        }

        socket.emit({'type': 'session.started'});
        await tester.pumpAndSettle();
        expect(audioCalls, contains('start'));
        expect(socket.sent.last['type'], 'session.commentary.append');
        await messenger.handlePlatformMessage(
          'voice_practice/microphone',
          const StandardMethodCodec().encodeSuccessEnvelope(
            Uint8List.fromList([1, 2]),
          ),
          (_) {},
        );
        await tester.pump();
        expect(socket.sent.last['audio'], 'AQI=');

        await tap('靜音');
        expect(socket.sent.last['type'], 'session.input_audio.mute');
        await tap('取消靜音');

        void caption(bool learner, int start, String text) {
          socket.emit({
            'type': learner
                ? 'session.input_transcript.delta'
                : 'session.output_transcript.delta',
            'start_ms': start,
            'end_ms': start + 100,
            'delta': text,
          });
        }

        caption(false, 100, 'How can I help?');
        socket.emit({'type': 'session.output_audio.delta', 'delta': 'AQI='});
        caption(true, 300, 'I want to make a reservation，');
        caption(true, 420, '兩位。');
        await tester.pumpAndSettle();
        final partner = find.text('口說夥伴');
        final learner = find.text('你');
        expect(partner, findsOneWidget);
        expect(learner, findsOneWidget);
        expect(
          tester.getCenter(partner).dx,
          lessThan(tester.getCenter(learner).dx),
        );
        caption(false, 650, 'What time?');
        caption(true, 850, '晚上 seven.');
        if (!guided) {
          caption(false, 1100, 'Inside or outside?');
          caption(true, 1350, 'Inside，謝謝。');
        }
        await tester.pumpAndSettle();
        expect(audioCalls, containsAllInOrder(['play', 'interrupt']));
        expect(find.text(guided ? '已練習 2／2 句' : '已回答 3／3 輪'), findsOneWidget);
        socket.emit({
          'type': 'session.usage.updated',
          'usage': {'seconds': 12},
        });
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(socket.sent.last['type'], 'session.close');
        expect(audioCalls, contains('stop'));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        final attempts = await history.attempts();
        expect(attempts.map((attempt) => attempt.model), [
          'gpt-live-1',
          'gpt-6-luna',
        ]);
        expect(
          attempts.map((attempt) => attempt.generationId).toSet(),
          hasLength(1),
        );
        expect(attempts.first.usage?['seconds'], 15);
        expect(attempts.first.cost.usd, closeTo(.0125, 1e-10));
        expect(attempts.last.cost.usd, closeTo(.000141, 1e-10));
        expect(attempts.any((attempt) => attempt.cost.unknown), isFalse);
        expect(find.text('用詞回饋'), findsOneWidget);
        expect(
          find.text('I’d like to make a reservation for two.'),
          findsOneWidget,
        );
        expect(find.text('口說夥伴'), findsNothing);
        expect(
          tester.getTopLeft(find.text('英文示範')).dy,
          lessThan(tester.getTopLeft(find.text('查看對話')).dy),
        );
        await tap('查看對話');
        expect(find.text('口說夥伴'), findsWidgets);
        expect(find.text('I want to make a reservation，兩位。'), findsOneWidget);
        final lesson = requests.single;
        expect(lesson['meaning'], '預訂');
        expect((lesson['turns'] as List).map((turn) => turn['user']), [
          'I want to make a reservation，兩位。',
          '晚上 seven.',
          if (!guided) 'Inside，謝謝。',
        ]);
      },
    );
  }

  testWidgets('非原15字也能從字庫推薦並加入複習，只顯示有資料的類別', (tester) async {
    final source = _wordCard(
      id: 'beautiful-source',
      word: 'beautiful',
    ).copyWith(meaning: '美麗的', partsOfSpeech: [PartOfSpeech.adjective]);
    final words = _buildWordsNotifier(initialCards: [source]);
    addTearDown(words.dispose);
    await words.load();
    final service = WordExtensionService(
      loadEntries: () async => [
        _extensionEntry('beautiful', '美麗的', PartOfSpeech.adjective),
        _extensionEntry('pretty', '美麗的', PartOfSpeech.adjective),
      ],
    );
    await _pumpDetailPage(
      tester,
      wordsNotifier: words,
      wordId: source.id,
      extensionService: service,
    );
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(find.text('相關字・pretty'), findsOneWidget);
    expect(find.textContaining('容易混淆・'), findsNothing);
    final add = find.byKey(const ValueKey('add-extension-pretty'));
    await _scrollTo(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final added = words.words.singleWhere((card) => card.word == 'pretty');
    expect(added.meaning, '美麗的');
    expect(added.origin, WordOrigin.builtinWordBank);
    expect(added.partsOfSpeech, [PartOfSpeech.adjective]);
    expect(added.nextReviewDate, added.createdAt.add(const Duration(days: 1)));
    expect(words.findById(source.id), same(source));
    expect(tester.takeException(), isNull);
  });

  testWidgets('展開才載入，失敗後可重試，收合重開不重載', (tester) async {
    final source = _wordCard(id: 'load-source', word: 'decide');
    final words = _buildWordsNotifier(initialCards: [source]);
    addTearDown(words.dispose);
    await words.load();
    var calls = 0;
    final pending = Completer<List<BuiltinWordEntry>>();
    final service = WordExtensionService(
      loadEntries: () {
        calls++;
        if (calls == 1) return pending.future;
        return Future.value([
          _extensionEntry('decide', '決定', PartOfSpeech.verb),
        ]);
      },
    );
    await _pumpDetailPage(
      tester,
      wordsNotifier: words,
      wordId: source.id,
      extensionService: service,
    );
    expect(calls, 0);
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('load failed'));
    await tester.pumpAndSettle();
    final retry = find.text('重新載入');
    await _scrollTo(tester, retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('載入延伸內容失敗，請重試。'), findsNothing);
    expect(find.text('目前沒有足夠資料推薦相關字或易混淆字。'), findsOneWidget);
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('載入期間改變詞義後不顯示過期結果，重新展開依新義項查詢', (tester) async {
    final source = _wordCard(id: 'sense-source', word: 'bank').copyWith(
      meaning: '銀行',
      partsOfSpeech: [PartOfSpeech.noun],
      sentences: const [],
    );
    final words = _buildWordsNotifier(initialCards: [source]);
    addTearDown(words.dispose);
    await words.load();
    final pending = Completer<List<BuiltinWordEntry>>();
    final service = WordExtensionService(loadEntries: () => pending.future);
    await _pumpDetailPage(
      tester,
      wordsNotifier: words,
      wordId: source.id,
      extensionService: service,
    );
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pump();
    await words.updateWord(
      card: source,
      word: 'bank',
      meaning: '河岸',
      sentences: const [],
      partsOfSpeech: [PartOfSpeech.noun],
    );
    await tester.pump();
    pending.complete([
      _extensionEntry('bank', '銀行', PartOfSpeech.noun),
      _extensionEntry('bank account', '銀行帳戶', PartOfSpeech.phrase),
      _extensionEntry('shore', '河岸', PartOfSpeech.noun),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('相關字・bank account'), findsNothing);
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(find.text('相關字・shore'), findsOneWidget);
    expect(find.text('相關字・bank account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [375.0, 800.0]) {
    testWidgets('延伸相關字加入既有複習並保留原字 width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _wordCard(id: 'decide-source', word: 'decide');
      final words = _buildWordsNotifier(initialCards: [source]);
      addTearDown(words.dispose);
      await words.load();
      await _pumpDetailPage(tester, wordsNotifier: words, wordId: source.id);
      final explore = find.text('探索用法與相關字');
      await _scrollTo(tester, explore);
      await tester.tap(explore);
      await tester.pumpAndSettle();
      expect(find.text('用法例句'), findsWidgets);
      expect(find.text('相關字・decision'), findsOneWidget);
      expect(find.text('容易混淆・choose'), findsOneWidget);
      final add = find.text('加入相關字到複習');
      await _scrollTo(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(words.words, hasLength(2));
      final related = words.words.singleWhere(
        (card) => card.word == 'decision',
      );
      expect(related.partsOfSpeech, [PartOfSpeech.noun]);
      expect(related.meaning, isNotEmpty);
      expect(related.sentences.single, contains('decision'));
      expect(related.needsCompletion, isFalse);
      expect(related.reviewSchedule, ReviewScheduleService.defaultSchedule);
      expect(related.nextReviewIndex, 0);
      expect(
        related.nextReviewDate,
        related.createdAt.add(const Duration(days: 1)),
      );
      expect(related.history, isEmpty);
      expect(words.dueOnOrBefore(related.nextReviewDate), contains(related));
      expect(words.findById(source.id), same(source));
      await words.load();
      await tester.pumpAndSettle();
      expect(words.words, hasLength(2));
      final view = find.textContaining('已加入・查看單字');
      await _scrollTo(tester, view);
      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(find.text('decision'), findsOneWidget);
      expect(words.words, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('延伸學習辨識既有單字，不重複新增或重設已掌握狀態', (tester) async {
    final source = _wordCard(id: 'source', word: 'decide');
    final existing = _wordCard(id: 'existing', word: ' Decision ').copyWith(
      reviewState: WordReviewState.mastered,
      masteredAt: DateTime(2026),
    );
    final words = _buildWordsNotifier(initialCards: [source, existing]);
    addTearDown(words.dispose);
    await words.load();
    await _pumpDetailPage(tester, wordsNotifier: words, wordId: source.id);
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(find.text('加入相關字到複習'), findsNothing);
    expect(find.text('已加入・查看單字（已掌握）'), findsOneWidget);
    expect(words.findById(existing.id), same(existing));
  });

  testWidgets('加入失敗可重試，儲存中連點只新增一次', (tester) async {
    final source = _wordCard(id: 'source', word: 'decide');
    final repository = _FakeWordRepository(initialCards: [source]);
    final words = _buildWordsNotifier(repository: repository);
    addTearDown(words.dispose);
    await words.load();
    await _pumpDetailPage(tester, wordsNotifier: words, wordId: source.id);
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    final add = find.text('加入相關字到複習');
    await _scrollTo(tester, add);
    repository.failAdd = true;
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('加入失敗，請稍後再試'), findsOneWidget);
    expect(words.words, hasLength(1));
    repository.failAdd = false;
    final pending = Completer<void>();
    repository.pendingAdd = pending;
    await tester.tap(add);
    await tester.tap(add);
    await tester.pump();
    expect(find.text('加入中…'), findsOneWidget);
    expect(words.words, hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(words.words, hasLength(2));
    expect(
      repository.addCalls,
      2,
    ); // One failed request and one successful retry.
    expect(tester.takeException(), isNull);
  });

  testWidgets('資料不足時搜尋後顯示空結果，不硬湊', (tester) async {
    final source = _wordCard(id: 'unsupported', word: 'xyzzy');
    final words = _buildWordsNotifier(initialCards: [source]);
    addTearDown(words.dispose);
    await words.load();
    await _pumpDetailPage(tester, wordsNotifier: words, wordId: source.id);
    final explore = find.text('探索用法與相關字');
    await _scrollTo(tester, explore);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    final empty = find.text('目前沒有足夠的字庫或關係資料可推薦延伸內容。');
    await _scrollTo(tester, empty);
    expect(empty, findsOneWidget);
    expect(find.text('加入相關字到複習'), findsNothing);
    expect(words.words, hasLength(1));
  });

  for (final width in [375.0, 800.0]) {
    testWidgets('圖片按鈕並排，依程度生成預覽後才新增例句 width=$width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final card = _wordCard(id: 'sentence-word', word: 'chirp');
      final words = _buildWordsNotifier(initialCards: [card]);
      await words.load();
      var requests = 0;
      final regenerated = Completer<http.Response>();
      final ai = LearningImageNotifier(
        service: LearningImageService(
          client: MockClient((request) async {
            requests++;
            if (requests == 2) {
              final input =
                  jsonDecode(jsonDecode(request.body)['input']) as Map;
              expect(input['level'], '國小');
              expect(
                input['existingSentences'],
                contains('Birds chirp 0.\n鳥兒啾啾叫 0。'),
              );
              return regenerated.future;
            }
            if (requests == 3) return http.Response('{}', 500);
            expect(
              jsonDecode(jsonDecode(request.body)['input'])['level'],
              '國小',
            );
            return http.Response(
              jsonEncode(response()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
        store: MemoryStore(),
        credentials: MemoryCredentials(),
      );
      addTearDown(ai.dispose);
      await _pumpDetailPage(
        tester,
        wordsNotifier: words,
        wordId: card.id,
        ai: ai,
      );
      final online = tester.getRect(
        find.widgetWithText(OutlinedButton, '下載線上圖片'),
      );
      final image = tester.getRect(
        find.widgetWithText(OutlinedButton, 'AI 生成學習圖卡'),
      );
      expect(online.top, image.top);
      expect(online.right, lessThan(image.left));
      final button = find.text('AI 生成例句');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      for (final label in ['幼兒園', '國小', '國中', '高中', '大學', '專業人士']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '生成例句'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('國小'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '生成例句'));
      await tester.pumpAndSettle();
      expect(find.text('Birds chirp 0.\n鳥兒啾啾叫 0。'), findsOneWidget);
      expect(words.findById(card.id)!.sentences, card.sentences);
      await tester.tap(find.text('重新生成'));
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '國小'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '重新生成'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '新增至例句'))
            .onPressed,
        isNull,
      );
      expect(words.findById(card.id)!.sentences, card.sentences);
      regenerated.complete(
        http.Response(
          jsonEncode(response()).replaceAll('Birds chirp', 'New birds chirp'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('Birds chirp 0.\n鳥兒啾啾叫 0。'), findsNothing);
      expect(find.text('New birds chirp 0.\n鳥兒啾啾叫 0。'), findsOneWidget);
      await tester.tap(find.text('重新生成'));
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.text('New birds chirp 0.\n鳥兒啾啾叫 0。'), findsOneWidget);
      expect(find.textContaining('API 請求失敗'), findsOneWidget);
      await tester.tap(find.text('新增至例句'));
      await tester.pumpAndSettle();
      expect(words.findById(card.id)!.sentences, hasLength(4));
      expect(words.findById(card.id)!.sentences.first, card.sentences.first);
      expect(
        words.findById(card.id)!.sentences[1],
        'New birds chirp 0.\n鳥兒啾啾叫 0。',
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('新增生成例句會保留最新資料並拒絕過期詞義', () async {
    final card = _wordCard(id: 'append-word', word: 'apple');
    final words = _buildWordsNotifier(initialCards: [card]);
    await words.load();
    await words.appendGeneratedSentences(card, ['New sentence. 新例句。']);
    await words.appendGeneratedSentences(card, [
      'New sentence. 新例句。',
      'Another. 另一句。',
    ]);
    expect(words.findById(card.id)!.sentences, hasLength(3));
    await expectLater(
      words.appendGeneratedSentences(card.copyWith(meaning: '不同詞義'), [
        'Wrong.',
      ]),
      throwsStateError,
    );
    expect(words.findById(card.id)!.sentences, hasLength(3));
  });

  testWidgets('刪除操作藏在更多選單中，取消確認不會刪除單字', (tester) async {
    final card = _wordCard(id: 'word-anchor', word: 'anchor');
    final wordsNotifier = _buildWordsNotifier(initialCards: [card]);
    await wordsNotifier.load();

    await _pumpDetailPage(
      tester,
      wordsNotifier: wordsNotifier,
      wordId: card.id,
    );

    expect(
      find.widgetWithIcon(IconButton, Icons.edit_outlined),
      findsOneWidget,
    );
    expect(find.widgetWithIcon(IconButton, Icons.delete_outline), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('刪除單字'), findsOneWidget);

    await tester.tap(find.text('刪除單字'));
    await tester.pumpAndSettle();

    expect(find.text('刪除單字'), findsOneWidget);
    expect(find.text('確定要刪除「anchor」嗎？這個動作無法直接復原。'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(wordsNotifier.findById(card.id), isNotNull);
    expect(find.text('anchor'), findsOneWidget);
  });

  testWidgets('確認刪除後才移除單字並返回上一頁', (tester) async {
    final card = _wordCard(id: 'word-brisk', word: 'brisk');
    final wordsNotifier = _buildWordsNotifier(initialCards: [card]);
    await wordsNotifier.load();

    await _pumpDetailPage(
      tester,
      wordsNotifier: wordsNotifier,
      wordId: card.id,
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除單字'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await tester.pumpAndSettle();

    expect(wordsNotifier.findById(card.id), isNull);
    expect(find.text('首頁'), findsOneWidget);
  });

  testWidgets('已完成週期的單字可再複習一輪並保留自訂資料', (tester) async {
    final firstReview = DateTime(2026, 1, 2, 10);
    final lastReview = DateTime(2026, 2, 10, 10);
    final card = _wordCard(id: 'word-restart', word: 'resilient').copyWith(
      memoryHint: '像彈簧一樣復原',
      customTags: const ['重要'],
      nextReviewIndex: 3,
      nextReviewDate: lastReview,
      history: [firstReview, lastReview],
      reviewRatings: const [ReviewRating.hard, ReviewRating.good],
    );
    final wordsNotifier = _buildWordsNotifier(initialCards: [card]);
    await wordsNotifier.load();

    await _pumpDetailPage(
      tester,
      wordsNotifier: wordsNotifier,
      wordId: card.id,
    );

    final restartButton = find.widgetWithText(OutlinedButton, '再複習一輪');
    await tester.ensureVisible(restartButton);
    await tester.tap(restartButton);
    await tester.pumpAndSettle();

    expect(find.text('再複習一輪'), findsNWidgets(2));
    expect(find.textContaining('單字內容與過往複習紀錄都會保留'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '開始複習'));
    await tester.pumpAndSettle();

    final restarted = wordsNotifier.findById(card.id)!;
    expect(restarted.nextReviewIndex, 0);
    expect(
      restarted.nextReviewDate.difference(DateTime.now()).abs(),
      lessThan(const Duration(seconds: 5)),
    );
    expect(restarted.history, [firstReview, lastReview]);
    expect(restarted.reviewRatings, [ReviewRating.hard, ReviewRating.good]);
    expect(restarted.meaning, card.meaning);
    expect(restarted.sentences, card.sentences);
    expect(restarted.memoryHint, card.memoryHint);
    expect(restarted.customTags, card.customTags);
  });
}

Future<void> _pumpDetailPage(
  WidgetTester tester, {
  required WordsNotifier wordsNotifier,
  required String wordId,
  LearningImageNotifier? ai,
  WordExtensionService? extensionService,
  VoicePracticeService? voicePractice,
}) async {
  final pronunciationService = PronunciationService();
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        if (voicePractice != null)
          Provider<VoicePracticeService>.value(value: voicePractice),
        if (ai != null) ...[
          ChangeNotifierProvider<LearningImageNotifier>.value(value: ai),
          Provider<OnlinePictureService>(create: (_) => OnlinePictureService()),
        ],
        Provider<WordExtensionService>.value(
          value:
              extensionService ??
              WordExtensionService(
                loadEntries: () async => [
                  _extensionEntry('decide', '決定', PartOfSpeech.verb),
                  _extensionEntry('decision', '決定', PartOfSpeech.noun),
                  _extensionEntry('choose', '選擇', PartOfSpeech.verb),
                ],
              ),
        ),
        Provider<PronunciationService>.value(value: pronunciationService),
        ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
        ChangeNotifierProvider<SettingsNotifier>.value(
          value: SettingsNotifier(
            repository: _FakeSettingsRepository(
              initialSettings: AppSettings.defaults(),
            ),
            notificationService: NotificationService(),
            pronunciationService: pronunciationService,
          ),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        routes: {
          '/': (context) => const Scaffold(body: Center(child: Text('首頁'))),
          '/detail': (context) => const WordDetailPage(),
          '/edit': (context) => const Scaffold(body: Text('編輯頁')),
        },
      ),
    ),
  );

  navigatorKey.currentState!.pushNamed('/detail', arguments: wordId);
  await tester.pumpAndSettle();
}

WordsNotifier _buildWordsNotifier({
  List<WordCard> initialCards = const [],
  _FakeWordRepository? repository,
}) {
  final scheduleService = ReviewScheduleService();
  return WordsNotifier(
    repository: repository ?? _FakeWordRepository(initialCards: initialCards),
    scheduleService: scheduleService,
    sortService: SortService(),
    imageStorage: ImageStorage(),
    wordContributionImportService: WordContributionImportService(
      scheduleService: scheduleService,
    ),
    initialSyncEnabled: false,
  );
}

WordCard _wordCard({required String id, required String word}) {
  final now = DateTime(2026);
  return WordCard(
    id: id,
    word: word,
    meaning: word == 'decide' ? '決定' : '$word 的意思',
    partOfSpeech: PartOfSpeech.noun,
    sentences: ['We practiced $word in class.'],
    origin: WordOrigin.manual,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now.add(const Duration(days: 1)),
    history: const [],
    isDeleted: false,
  );
}

class _FakeLiveSocket extends Stream<dynamic> implements WebSocket {
  final _stream = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];

  void emit(Map<String, Object> event) => _stream.add(jsonEncode(event));

  @override
  int get readyState => WebSocket.open;

  @override
  void add(dynamic data) {
    final event = jsonDecode(data as String) as Map<String, dynamic>;
    sent.add(event);
    if (event['type'] == 'session.close') {
      emit({
        'type': 'session.closed',
        'usage': {'seconds': 15},
      });
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _stream.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWordRepository implements WordRepository {
  _FakeWordRepository({List<WordCard> initialCards = const []})
    : _cards = List<WordCard>.from(initialCards);

  final List<WordCard> _cards;
  bool failAdd = false;
  Completer<void>? pendingAdd;
  int addCalls = 0;

  @override
  Future<void> add(WordCard card) async {
    addCalls++;
    if (failAdd) throw StateError('storage unavailable');
    await pendingAdd?.future;
    _cards.add(card);
  }

  @override
  Future<void> delete(String id) async {
    _cards.removeWhere((card) => card.id == id);
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async {
    return List<WordCard>.unmodifiable(
      includeDeleted ? _cards : _cards.where((card) => !card.isDeleted),
    );
  }

  @override
  Future<List<WordCard>> fetchDue(DateTime day) async {
    return const <WordCard>[];
  }

  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int> bytes) saveBytes,
  }) async {
    return 0;
  }

  @override
  Future<void> update(WordCard card) async {
    final index = _cards.indexWhere((item) => item.id == card.id);
    if (index == -1) {
      return;
    }
    _cards[index] = card;
  }
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({required AppSettings initialSettings})
    : _settings = initialSettings;

  AppSettings _settings;

  @override
  Future<AppSettings> fetch() async => _settings;

  @override
  Future<bool> hasSavedSettings() async => true;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

BuiltinWordEntry _extensionEntry(
  String word,
  String meaning,
  PartOfSpeech part,
) => BuiltinWordEntry(
  word: word,
  meaning: meaning,
  partsOfSpeech: [part],
  sentences: ['$word is used in this sentence. 這句話使用了這個字。'],
  sourcePage: 0,
  schoolLevels: const [],
  examTags: const [],
  audienceTags: const [],
  sourceTags: const [BuiltinSourceTag.twCeec],
  difficultyLevel: 2,
);
