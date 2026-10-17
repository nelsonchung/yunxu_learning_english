import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/records_page.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('可前後切換七天學習紀錄，且不能切到未來', (tester) async {
    final notifier = _buildWordsNotifier();
    await notifier.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<WordsNotifier>.value(
        value: notifier,
        child: const MaterialApp(home: Scaffold(body: RecordsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近 7 天'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('nextActivityWeek')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('previousActivityWeek')));
    await tester.pump();

    expect(find.text('先前 7 天'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('nextActivityWeek')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('nextActivityWeek')));
    await tester.pump();

    expect(find.text('最近 7 天'), findsOneWidget);
  });

  testWidgets('顯示目前連續與最長連續天數，並可切換至月曆熱力圖與前後月份', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = DateTime(now.year, now.month, now.day - 1, 10);
    final notifier = _buildWordsNotifier(
      initialCards: [
        WordCard(
          id: 'streak-1',
          word: 'persist',
          meaning: '堅持',
          partsOfSpeech: const [PartOfSpeech.verb],
          sentences: const ['She persisted in her studies.'],
          origin: WordOrigin.manual,
          createdAt: yesterday,
          updatedAt: today,
          reviewSchedule: const [1, 2, 3],
          nextReviewIndex: 1,
          nextReviewDate: today.add(const Duration(days: 1)),
          history: [today],
          reviewRatings: const [ReviewRating.good],
          isDeleted: false,
        ),
      ],
    );
    await notifier.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<WordsNotifier>.value(
        value: notifier,
        child: const MaterialApp(home: Scaffold(body: RecordsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('目前連續'), findsOneWidget);
    expect(find.text('最長連續'), findsOneWidget);
    expect(find.text('7 天檢視'), findsOneWidget);
    expect(find.text('月曆熱力圖'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('activityViewMonthTab')));
    await tester.pumpAndSettle();

    final currentMonthStr = now.month.toString().padLeft(2, '0');
    expect(find.text('${now.year} 年 $currentMonthStr 月'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('nextActivityMonth')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('previousActivityMonth')));
    await tester.pumpAndSettle();

    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final prevMonthStr = prevMonth.month.toString().padLeft(2, '0');
    expect(find.text('${prevMonth.year} 年 $prevMonthStr 月'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('nextActivityMonth')))
          .onPressed,
      isNotNull,
    );
  });
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

class _FakeWordRepository implements WordRepository {
  _FakeWordRepository({this.initialCards = const []});

  final List<WordCard> initialCards;

  @override
  Future<void> add(WordCard card) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async =>
      initialCards;

  @override
  Future<List<WordCard>> fetchDue(DateTime day) async => [];

  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int> bytes) saveBytes,
  }) async => 0;

  @override
  Future<void> update(WordCard card) async {}
}
