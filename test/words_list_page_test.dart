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
import 'package:yunxu_learning_english/presentation/pages/words_list_page.dart';
import 'package:yunxu_learning_english/presentation/state/settings_notifier.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('搜尋英文單字會只顯示符合 word 的卡片', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(id: '1', word: 'apple', meaning: '蘋果'),
        _wordCard(id: '2', word: 'bread', meaning: '麵包'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'app');
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bread'), findsNothing);
  });

  testWidgets('搜尋中文意思會顯示符合 meaning 的卡片', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(id: '1', word: 'apple', meaning: '蘋果'),
        _wordCard(id: '2', word: 'bread', meaning: '麵包'),
      ],
    );

    await tester.enterText(find.byType(TextField), '蘋果');
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bread'), findsNothing);
  });

  testWidgets('搜尋不會比對例句內容', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(
          id: '1',
          word: 'comet',
          meaning: '彗星',
          sentences: const ['The comet crossed the quiet orbit.'],
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'orbit');
    await tester.pump();

    expect(find.text('comet'), findsNothing);
    expect(find.text('找不到符合搜尋的單字'), findsOneWidget);
  });

  testWidgets('清除搜尋後恢復目前列表', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(id: '1', word: 'apple', meaning: '蘋果'),
        _wordCard(id: '2', word: 'bread', meaning: '麵包'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'app');
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bread'), findsNothing);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bread'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('搜尋可以和待補篩選疊加', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(id: '1', word: 'apple', meaning: '蘋果', sentences: const []),
        _wordCard(id: '2', word: 'application', meaning: '應用'),
        _wordCard(id: '3', word: 'bread', meaning: '麵包'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'app');
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '只看待補 1'));
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('application'), findsNothing);
    expect(find.text('bread'), findsNothing);
  });

  testWidgets('點選自訂標籤可以篩選單字', (tester) async {
    await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(
          id: '1',
          word: 'apple',
          meaning: '蘋果',
          customTags: const ['水果'],
        ),
        _wordCard(
          id: '2',
          word: 'bread',
          meaning: '麵包',
          customTags: const ['早餐'],
        ),
      ],
    );

    await tester.tap(find.text('水果 1'));
    await tester.pump();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('bread'), findsNothing);
  });

  testWidgets('可以從所有單字刪除自訂標籤', (tester) async {
    final wordsNotifier = await _pumpWordsListPage(
      tester,
      initialCards: [
        _wordCard(
          id: '1',
          word: 'apple',
          meaning: '蘋果',
          customTags: const ['期中考', '課本A'],
        ),
        _wordCard(
          id: '2',
          word: 'bread',
          meaning: '麵包',
          customTags: const ['期中考'],
        ),
      ],
    );

    expect(find.text('期中考 2'), findsOneWidget);
    expect(find.text('課本A 1'), findsOneWidget);

    await tester.tap(find.byTooltip('刪除標籤 期中考'));
    await tester.pumpAndSettle();

    expect(find.text('刪除標籤'), findsWidgets);
    expect(find.textContaining('這會從 2 個單字移除此標籤'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '刪除標籤'));
    await tester.pumpAndSettle();

    expect(find.text('期中考 2'), findsNothing);
    expect(find.text('課本A 1'), findsOneWidget);
    expect(
      wordsNotifier.words.any((card) => card.customTags.contains('期中考')),
      isFalse,
    );
    expect(wordsNotifier.findById('1')?.customTags, contains('課本A'));
  });
}

Future<WordsNotifier> _pumpWordsListPage(
  WidgetTester tester, {
  required List<WordCard> initialCards,
}) async {
  final wordsNotifier = _buildWordsNotifier(initialCards: initialCards);
  await wordsNotifier.load();
  final settingsNotifier = _buildSettingsNotifier(
    initialSettings: AppSettings.defaults().copyWith(showImages: false),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
        ChangeNotifierProvider<SettingsNotifier>.value(value: settingsNotifier),
      ],
      child: const MaterialApp(home: Scaffold(body: WordsListPage())),
    ),
  );
  await tester.pumpAndSettle();
  return wordsNotifier;
}

WordsNotifier _buildWordsNotifier({required List<WordCard> initialCards}) {
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

SettingsNotifier _buildSettingsNotifier({
  required AppSettings initialSettings,
}) {
  return SettingsNotifier(
    repository: _FakeSettingsRepository(initialSettings: initialSettings),
    notificationService: NotificationService(),
    pronunciationService: PronunciationService(),
  );
}

WordCard _wordCard({
  required String id,
  required String word,
  required String meaning,
  List<String> sentences = const ['This is a sample sentence.'],
  List<String> customTags = const [],
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000);
  return WordCard(
    id: id,
    word: word,
    meaning: meaning,
    partOfSpeech: PartOfSpeech.noun,
    sentences: sentences,
    origin: WordOrigin.manual,
    createdAt: now.add(Duration(minutes: id.hashCode.abs() % 1000)),
    updatedAt: now,
    reviewSchedule: const [1, 2, 3],
    nextReviewIndex: 0,
    nextReviewDate: now,
    history: const [],
    isDeleted: false,
    customTags: customTags,
  );
}

class _FakeWordRepository implements WordRepository {
  _FakeWordRepository({required List<WordCard> initialCards})
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
    return List<WordCard>.unmodifiable(_cards);
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
