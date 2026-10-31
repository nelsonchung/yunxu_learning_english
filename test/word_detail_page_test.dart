import 'dart:async';
import 'dart:convert';
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
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/word_detail_page.dart';
import 'package:yunxu_learning_english/presentation/state/settings_notifier.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}) async {
  final pronunciationService = PronunciationService();
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        if (ai != null) ...[
          ChangeNotifierProvider<LearningImageNotifier>.value(value: ai),
          Provider<OnlinePictureService>(create: (_) => OnlinePictureService()),
        ],
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

WordsNotifier _buildWordsNotifier({List<WordCard> initialCards = const []}) {
  final scheduleService = ReviewScheduleService();
  return WordsNotifier(
    repository: _FakeWordRepository(initialCards: initialCards),
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
    meaning: '$word 的意思',
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

class _FakeWordRepository implements WordRepository {
  _FakeWordRepository({List<WordCard> initialCards = const []})
    : _cards = List<WordCard>.from(initialCards);

  final List<WordCard> _cards;

  @override
  Future<void> add(WordCard card) async {
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
