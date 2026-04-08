import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:yunxu_learning_english/data/repositories/builtin_word_bank_repository.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/word_bank_page.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('搜尋框在有輸入時顯示清除按鈕並可清空文字', (tester) async {
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BuiltinWordBankRepository>.value(
            value: BuiltinWordBankRepository(
              assetBundle: _FakeWordBankAssetBundle(),
            ),
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
}

class _FakeWordBankAssetBundle extends CachingAssetBundle {
  static final String _entriesJson = jsonEncode([
    _entryMap(
      word: 'bread',
      partOfSpeech: 'noun',
      meaning: '麵包',
      difficultyLevel: 1,
    ),
    _entryMap(
      word: 'compensate',
      partOfSpeech: 'verb',
      meaning: '補償',
      difficultyLevel: 3,
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
