import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_bank_search_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/word_bank_page.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('搜尋框在有輸入時顯示清除按鈕並可清空文字', (tester) async {
    final wordsNotifier = _buildWordsNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: _FakeBuiltinWordBankRepository(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
        ],
        child: const MaterialApp(home: Scaffold(body: WordBankPage())),
      ),
    );

    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);

    await tester.enterText(searchField, 'bread');
    await tester.pump();

    expect(find.widgetWithIcon(IconButton, Icons.close), findsOneWidget);
    expect(tester.widget<TextField>(searchField).controller?.text, 'bread');

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();

    expect(tester.widget<TextField>(searchField).controller?.text, isEmpty);
    expect(find.widgetWithIcon(IconButton, Icons.close), findsNothing);
  });

  testWidgets('搜尋結果會在 debounce 後才更新', (tester) async {
    final wordsNotifier = _buildWordsNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: _FakeBuiltinWordBankRepository(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
        ],
        child: const MaterialApp(home: Scaffold(body: WordBankPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('bread'), findsOneWidget);
    expect(find.text('compensate'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'co');
    await tester.pump();

    expect(find.text('bread'), findsOneWidget);
    expect(find.text('compensate'), findsOneWidget);
    expect(find.text('正在更新搜尋結果...'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('bread'), findsNothing);
    expect(find.text('compensate'), findsOneWidget);
    expect(find.text('正在更新搜尋結果...'), findsNothing);
  });

  testWidgets('加入字庫單字提示會在兩秒後自動消失', (tester) async {
    final wordsNotifier = _buildWordsNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: _FakeBuiltinWordBankRepository(),
          ),
          ChangeNotifierProvider<WordsNotifier>.value(value: wordsNotifier),
        ],
        child: const MaterialApp(home: Scaffold(body: WordBankPage())),
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

class _FakeBuiltinWordBankRepository extends BuiltinWordBankRepository {
  _FakeBuiltinWordBankRepository()
    : _entries = [
        _BuiltinWordBankFixture.entry(
          word: 'bread',
          partOfSpeech: PartOfSpeech.noun,
          meaning: '麵包',
          difficultyLevel: 1,
        ),
        _BuiltinWordBankFixture.entry(
          word: 'compensate',
          partOfSpeech: PartOfSpeech.verb,
          meaning: '補償',
          difficultyLevel: 3,
        ),
      ],
      _searchService = const WordBankSearchService(),
      super(assetBundle: _UnusedAssetBundle());

  final List<BuiltinWordEntry> _entries;
  final WordBankSearchService _searchService;

  @override
  Future<List<BuiltinWordEntry>> fetchAll() {
    throw StateError('WordBankPage should not call fetchAll() in Phase 2');
  }

  @override
  Future<Map<BuiltinWordBankAudienceFilter, int>> fetchFilterCounts() async {
    return {
      BuiltinWordBankAudienceFilter.all: _entries.length,
      BuiltinWordBankAudienceFilter.general: 0,
      BuiltinWordBankAudienceFilter.elementary: 0,
      BuiltinWordBankAudienceFilter.juniorHigh: 0,
      BuiltinWordBankAudienceFilter.seniorHigh: _entries.length,
      BuiltinWordBankAudienceFilter.college: 0,
      BuiltinWordBankAudienceFilter.toeic: 0,
    };
  }

  @override
  Future<BuiltinWordBankSearchResult> search({
    required String query,
    required BuiltinWordBankAudienceFilter filter,
    int emptyQueryLimit = 100,
    int queryLimit = 200,
  }) async {
    final entries = _entries.where((entry) {
      switch (filter) {
        case BuiltinWordBankAudienceFilter.all:
          return true;
        case BuiltinWordBankAudienceFilter.general:
          return entry.audienceTags.contains(BuiltinAudienceTag.general);
        case BuiltinWordBankAudienceFilter.elementary:
          return entry.schoolLevels.contains(BuiltinSchoolLevel.elementary);
        case BuiltinWordBankAudienceFilter.juniorHigh:
          return entry.schoolLevels.contains(BuiltinSchoolLevel.juniorHigh);
        case BuiltinWordBankAudienceFilter.seniorHigh:
          return entry.schoolLevels.contains(BuiltinSchoolLevel.seniorHigh);
        case BuiltinWordBankAudienceFilter.college:
          return entry.schoolLevels.contains(BuiltinSchoolLevel.college);
        case BuiltinWordBankAudienceFilter.toeic:
          return entry.examTags.contains(BuiltinExamTag.toeic);
      }
    });

    final results = _searchService.search(
      entries: entries,
      query: query,
      emptyQueryLimit: emptyQueryLimit,
      queryLimit: queryLimit,
    );

    return BuiltinWordBankSearchResult(entries: results);
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

class _UnusedAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    throw UnsupportedError('Unused in fake query-based repository');
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
