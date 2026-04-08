import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/data/repositories/settings_repository.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/app_settings.dart';
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
    final scheduleService = ReviewScheduleService();
    final wordsNotifier = WordsNotifier(
      repository: _FakeWordRepository(),
      scheduleService: scheduleService,
      sortService: SortService(),
      imageStorage: ImageStorage(),
      wordContributionImportService: WordContributionImportService(
        scheduleService: scheduleService,
      ),
      initialSyncEnabled: false,
    );
    final settingsNotifier = SettingsNotifier(
      repository: _FakeSettingsRepository(),
      notificationService: NotificationService(),
      pronunciationService: PronunciationService(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: BuiltinWordBankRepository(
              assetBundle: _FakeWordBankAssetBundle(),
            ),
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

    final changeOneButton = find.widgetWithText(TextButton, '換一個').first;
    expect(changeOneButton, findsOneWidget);

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
}

class _FakeWordBankAssetBundle extends CachingAssetBundle {
  static final String _entriesJson = jsonEncode([
    _entryMap(
      word: 'anchor',
      partOfSpeech: 'noun',
      meaning: '錨；支點',
      difficultyLevel: 2,
    ),
    _entryMap(
      word: 'balance',
      partOfSpeech: 'verb',
      meaning: '使平衡',
      difficultyLevel: 2,
    ),
    _entryMap(
      word: 'curious',
      partOfSpeech: 'adjective',
      meaning: '好奇的',
      difficultyLevel: 2,
    ),
    _entryMap(
      word: 'daily',
      partOfSpeech: 'adverb',
      meaning: '每天地',
      difficultyLevel: 2,
    ),
  ]);

  @override
  Future<ByteData> load(String key) async {
    final contents = key.endsWith('word_bank_main-a.json')
        ? _entriesJson
        : '[]';
    final bytes = Uint8List.fromList(utf8.encode(contents));
    return ByteData.view(bytes.buffer);
  }

  static Map<String, Object?> _entryMap({
    required String word,
    required String partOfSpeech,
    required String meaning,
    required int difficultyLevel,
  }) {
    return {
      'word': word,
      'meaning': meaning,
      'partOfSpeech': partOfSpeech,
      'sentences': [
        'This is a sample sentence for $word.',
        'We use $word again in a second sentence.',
      ],
      'sourcePage': 1,
      'schoolLevels': ['seniorHigh'],
      'examTags': const <String>[],
      'audienceTags': const <String>[],
      'sourceTags': ['twCeec'],
      'difficultyLevel': difficultyLevel,
    };
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
  AppSettings _settings = AppSettings.defaults();

  @override
  Future<AppSettings> fetch() async => _settings;

  @override
  Future<bool> hasSavedSettings() async => true;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}
