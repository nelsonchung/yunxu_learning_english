import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/models/builtin_word_entry.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_bank_refresh_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/pages/word_bank_refresh_page.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';

void main() {
  late _Repository repository;
  late WordsNotifier notifier;
  late WordBankRefreshService service;

  setUp(() async {
    repository = _Repository(_card());
    service = WordBankRefreshService(lookup: (_) async => [_entry()]);
  });

  tearDown(() => notifier.dispose());

  Future<void> pump(
    WidgetTester tester, {
    bool batch = false,
    Size size = const Size(1100, 2000),
  }) async {
    final schedule = ReviewScheduleService();
    notifier = WordsNotifier(
      repository: repository,
      scheduleService: schedule,
      sortService: SortService(),
      imageStorage: ImageStorage(),
      wordContributionImportService: WordContributionImportService(
        scheduleService: schedule,
      ),
    );
    await notifier.load();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WordsNotifier>.value(value: notifier),
          Provider<WordBankRefreshService>.value(value: service),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => batch
                        ? const WordBankRefreshListPage()
                        : const WordBankRefreshPage(wordId: 'habit'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('refresh-preview')));
    await tester.tap(find.byKey(const Key('refresh-preview')));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await preview(tester);
    await tester.tap(find.text('套用更新'));
    await tester.pumpAndSettle();
  }

  testWidgets('預設保留所有欄位，取消確認不會寫入', (tester) async {
    await pump(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('refresh-preview')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('使用字庫內容'));
    await tester.pump();
    await preview(tester);
    expect(find.text('確認更新內容'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.writes, 0);
    expect(notifier.findById('habit')!.meaning, '習慣');
  });

  testWidgets('只替換中文意思，保留例句與複習紀錄', (tester) async {
    final original = repository.card;
    await pump(tester);
    await tester.tap(find.text('使用字庫內容'));
    await tester.pump();
    await apply(tester);
    final updated = notifier.findById('habit')!;
    expect(updated.meaning, '習慣；慣常的行為');
    expect(updated.sentences, original.sentences);
    expect(updated.history, original.history);
    expect(updated.nextReviewDate, original.nextReviewDate);
    expect(updated.nextReviewIndex, original.nextReviewIndex);
    expect(updated.reviewRatings, original.reviewRatings);
    expect(repository.writes, 1);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('選句補充不重複加入既有例句且保留原清單', (tester) async {
    repository.card = repository.card.copyWith(
      sentences: ['I read every night.', 'I read every night.'],
    );
    await pump(tester);
    await tester.tap(find.text('保留並加入選取例句'));
    await tester.pumpAndSettle();
    final existing = find.widgetWithText(
      CheckboxListTile,
      'I read every night.',
    );
    expect(tester.widget<CheckboxListTile>(existing).onChanged, isNull);
    final addition = find.widgetWithText(
      CheckboxListTile,
      'She walks every morning.',
    );
    await tester.tap(addition);
    await tester.pump();
    await apply(tester);
    expect(notifier.findById('habit')!.sentences, [
      'I read every night.',
      'I read every night.',
      'She walks every morning.',
    ]);
    expect(notifier.findById('habit')!.meaning, '習慣');
  });

  testWidgets('中文可帶入後修改，取代例句可再編輯並預覽', (tester) async {
    await pump(tester);
    await tester.tap(find.text('自行編輯'));
    await tester.pump();
    await tester.tap(find.text('帶入字庫內容'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '習慣；慣常的行為',
    );
    await tester.enterText(find.byType(TextField), '習慣；習性');
    await tester.tap(find.text('用字庫例句全部取代'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯更新後的例句'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'I have a good habit.',
    );
    await tester.tap(find.text('完成編輯'));
    await tester.pumpAndSettle();
    await apply(tester);
    expect(notifier.findById('habit')!.meaning, '習慣；習性');
    expect(notifier.findById('habit')!.sentences, ['I have a good habit.']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('寫入失敗保留選擇且可以重試', (tester) async {
    repository.fail = true;
    await pump(tester);
    await tester.tap(find.text('使用字庫內容'));
    await tester.pump();
    await apply(tester);
    expect(notifier.findById('habit')!.meaning, '習慣');
    expect(find.textContaining('disk full'), findsWidgets);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '使用字庫內容'))
          .selected,
      isTrue,
    );
    repository.fail = false;
    await apply(tester);
    expect(notifier.findById('habit')!.meaning, '習慣；慣常的行為');
  });

  testWidgets('預覽後內容改變會拒絕舊預覽，重新比對顯示最新內容', (tester) async {
    await pump(tester);
    final card = notifier.findById('habit')!;
    await notifier.updateWord(
      card: card,
      word: card.word,
      meaning: '我改過的意思',
      sentences: card.sentences,
      partsOfSpeech: card.partsOfSpeech,
    );
    await tester.pump();
    await tester.tap(find.text('使用字庫內容'));
    await tester.pump();
    await apply(tester);
    expect(notifier.findById('habit')!.meaning, '我改過的意思');
    await tester.ensureVisible(find.text('重新比對').first);
    await tester.tap(find.text('重新比對').first);
    await tester.pumpAndSettle();
    expect(find.text('我改過的意思'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('refresh-preview')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('檢查清單列出差異，開啟單字逐筆確認', (tester) async {
    await pump(tester, batch: true);
    expect(find.text('中文意思、例句'), findsOneWidget);
    await tester.tap(find.text('habit'));
    await tester.pumpAndSettle();
    expect(find.text('比對字庫內容'), findsOneWidget);
    expect(repository.writes, 0);
  });

  testWidgets('手機窄螢幕可選擇內容並確認更新，無版面溢出', (tester) async {
    await pump(tester, size: const Size(390, 844));
    await tester.tap(find.text('使用字庫內容'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('refresh-preview')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await apply(tester);
    expect(notifier.findById('habit')!.meaning, '習慣；慣常的行為');
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺少對應或查詢失敗均不允許更新，失敗可重試', (tester) async {
    var failLookup = true;
    service = WordBankRefreshService(
      lookup: (_) async {
        if (failLookup) throw StateError('lookup unavailable');
        return [];
      },
    );
    await pump(tester);
    expect(find.textContaining('lookup unavailable'), findsOneWidget);
    failLookup = false;
    await tester.tap(find.text('重新比對').first);
    await tester.pumpAndSettle();
    expect(find.text('目前字庫找不到對應單字，未變更任何內容。'), findsOneWidget);
    expect(find.byKey(const Key('refresh-preview')), findsNothing);
    expect(repository.writes, 0);
  });
}

BuiltinWordEntry _entry() => BuiltinWordEntry(
  word: 'habit',
  meaning: '習慣；慣常的行為',
  sentences: ['I read every night.', 'She walks every morning.'],
  partsOfSpeech: const [PartOfSpeech.noun],
  sourcePage: 1,
  schoolLevels: const [],
  examTags: const [],
  audienceTags: const [],
  sourceTags: const [],
);

WordCard _card() => WordCard(
  id: 'habit',
  word: 'habit',
  meaning: '習慣',
  sentences: ['I read every night.'],
  partsOfSpeech: const [PartOfSpeech.noun],
  origin: WordOrigin.builtinWordBank,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 2, 1),
  reviewSchedule: const [1, 3, 7],
  nextReviewIndex: 2,
  nextReviewDate: DateTime(2026, 3, 1),
  history: [DateTime(2026, 1, 2), DateTime(2026, 1, 5)],
  reviewRatings: const [ReviewRating.hard, ReviewRating.good],
  isDeleted: false,
);

class _Repository implements WordRepository {
  _Repository(this.card);
  WordCard card;
  int writes = 0;
  bool fail = false;

  @override
  Future<void> update(WordCard value) async {
    if (fail) throw StateError('disk full');
    card = value;
    writes++;
  }

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async => [
    card,
  ];
  @override
  Future<List<WordCard>> fetchDue(DateTime day) async => [];
  @override
  Future<void> add(WordCard value) async => card = value;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<int> migrateImageBytesToPaths({
    required Future<String> Function(List<int>) saveBytes,
  }) async => 0;
}
