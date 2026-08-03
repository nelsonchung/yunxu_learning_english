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

class _FakeWordRepository implements WordRepository {
  @override
  Future<void> add(WordCard card) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async => [];

  @override
  Future<List<WordCard>> fetchDue(DateTime day) async => [];

  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int> bytes) saveBytes,
  }) async => 0;

  @override
  Future<void> update(WordCard card) async {}
}
