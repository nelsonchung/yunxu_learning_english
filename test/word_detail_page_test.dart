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
}

Future<void> _pumpDetailPage(
  WidgetTester tester, {
  required WordsNotifier wordsNotifier,
  required String wordId,
}) async {
  final pronunciationService = PronunciationService();
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
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
