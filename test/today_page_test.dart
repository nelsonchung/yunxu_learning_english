import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/data/repositories/settings_repository.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/app_settings.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/daily_word_recommendation_service.dart';
import 'package:yunxu_learning_english/domain/services/notification_service.dart';
import 'package:yunxu_learning_english/domain/services/pronunciation_service.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/today_page.dart';
import 'package:yunxu_learning_english/presentation/state/settings_notifier.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('換一個提示會在兩秒後自動消失', (tester) async {
    final wordsNotifier = _buildWordsNotifier();
    final settingsNotifier = _buildSettingsNotifier();
    final builtinRepository = _FakeBuiltinWordBankRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(value: builtinRepository),
          Provider<DailyWordRecommendationService>.value(
            value: DailyWordRecommendationService(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
          ChangeNotifierProvider<SettingsNotifier>.value(
            value: settingsNotifier,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TodayPage())),
      ),
    );

    await tester.pumpAndSettle();

    final changeOneButton = find.widgetWithText(TextButton, '換一個').first;
    expect(changeOneButton, findsOneWidget);
    expect(builtinRepository.recommendationRequestCount, 1);

    await tester.tap(changeOneButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('已略過'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('已略過'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('已略過'), findsNothing);
  });

  testWidgets('推薦會在背景準備完成後才顯示，不會先出現 loading spinner', (tester) async {
    final wordsNotifier = _buildWordsNotifier();
    final settingsNotifier = _buildSettingsNotifier();
    final builtinRepository = _FakeBuiltinWordBankRepository(
      delay: const Duration(milliseconds: 300),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(value: builtinRepository),
          Provider<DailyWordRecommendationService>.value(
            value: DailyWordRecommendationService(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
          ChangeNotifierProvider<SettingsNotifier>.value(
            value: settingsNotifier,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TodayPage())),
      ),
    );

    await tester.pump();

    expect(find.text('今日補新字'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('今日補新字'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
  });

  testWidgets('加入新字提示會在兩秒後自動消失', (tester) async {
    final wordsNotifier = _buildWordsNotifier();
    final settingsNotifier = _buildSettingsNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: _FakeBuiltinWordBankRepository(),
          ),
          Provider<DailyWordRecommendationService>.value(
            value: DailyWordRecommendationService(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
          ChangeNotifierProvider<SettingsNotifier>.value(
            value: settingsNotifier,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TodayPage())),
      ),
    );

    await tester.pumpAndSettle();

    final addButton = find.byIcon(Icons.add_circle_outline).first;
    expect(addButton, findsOneWidget);

    await tester.tap(addButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('已加入「'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('已加入「'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.textContaining('已加入「'), findsNothing);
  });

  testWidgets('每日推薦關閉時不會載入推薦候選', (tester) async {
    final wordsNotifier = _buildWordsNotifier();
    final settingsNotifier = _buildSettingsNotifier();
    await settingsNotifier.setDailyNewWordsEnabled(false);
    final builtinRepository = _FakeBuiltinWordBankRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(value: builtinRepository),
          Provider<DailyWordRecommendationService>.value(
            value: DailyWordRecommendationService(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
          ChangeNotifierProvider<SettingsNotifier>.value(
            value: settingsNotifier,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TodayPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('今日補新字'), findsNothing);
    expect(builtinRepository.recommendationRequestCount, 0);
  });
}

WordsNotifier _buildWordsNotifier() {
  final scheduleService = ReviewScheduleService();
  return WordsNotifier(
    repository: _FakeWordRepository(),
    scheduleService: scheduleService,
    sortService: SortService(),
    imageStorage: ImageStorage(),
    wordContributionImportService: WordContributionImportService(
      scheduleService: scheduleService,
    ),
    initialSyncEnabled: false,
  );
}

SettingsNotifier _buildSettingsNotifier({AppSettings? initialSettings}) {
  return SettingsNotifier(
    repository: _FakeSettingsRepository(
      initialSettings: initialSettings ?? AppSettings.defaults(),
    ),
    notificationService: NotificationService(),
    pronunciationService: PronunciationService(),
  );
}

class _FakeBuiltinWordBankRepository extends BuiltinWordBankRepository {
  _FakeBuiltinWordBankRepository({this.delay = Duration.zero})
    : _entries = [
        _BuiltinWordBankFixture.entry(
          word: 'anchor',
          partOfSpeech: PartOfSpeech.noun,
          meaning: '錨；支點',
          difficultyLevel: 2,
        ),
        _BuiltinWordBankFixture.entry(
          word: 'balance',
          partOfSpeech: PartOfSpeech.verb,
          meaning: '使平衡',
          difficultyLevel: 2,
        ),
        _BuiltinWordBankFixture.entry(
          word: 'curious',
          partOfSpeech: PartOfSpeech.adjective,
          meaning: '好奇的',
          difficultyLevel: 2,
        ),
        _BuiltinWordBankFixture.entry(
          word: 'daily',
          partOfSpeech: PartOfSpeech.adverb,
          meaning: '每天地',
          difficultyLevel: 2,
        ),
      ];

  final Duration delay;
  final List<BuiltinWordEntry> _entries;
  int recommendationRequestCount = 0;

  @override
  Future<List<BuiltinWordEntry>> fetchAll() {
    throw StateError('TodayPage should not call fetchAll() after optimization');
  }

  @override
  Future<List<BuiltinWordEntry>> fetchRecommendationCandidates({
    required List<WordCard> existingWords,
    required DateTime now,
    required int desiredCount,
    int minimumShardCount = 6,
    int? candidateLimit,
  }) async {
    recommendationRequestCount += 1;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return List<BuiltinWordEntry>.unmodifiable(_entries);
  }
}

class _BuiltinWordBankFixture {
  static BuiltinWordEntry entry({
    required String word,
    required PartOfSpeech partOfSpeech,
    required String meaning,
    required int difficultyLevel,
  }) {
    return BuiltinWordEntry(
      word: word,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      sentences: [
        'This is a sample sentence for $word.',
        'We use $word again in a second sentence.',
      ],
      sourcePage: 1,
      schoolLevels: const [BuiltinSchoolLevel.seniorHigh],
      examTags: const [],
      audienceTags: const [],
      sourceTags: const [BuiltinSourceTag.twCeec],
      difficultyLevel: difficultyLevel,
    );
  }
}

class _FakeWordRepository implements WordRepository {
  final List<WordCard> _cards = <WordCard>[];

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
