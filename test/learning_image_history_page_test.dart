import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunxu_learning_english/data/storage/learning_image_store.dart';
import 'package:yunxu_learning_english/domain/models/learning_image.dart';
import 'package:yunxu_learning_english/domain/models/ai_provider.dart';
import 'package:yunxu_learning_english/domain/models/learning_image_history.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/presentation/pages/learning_image_history_page.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';
import 'package:yunxu_learning_english/presentation/widgets/ai_learning_image_settings.dart';

class _Credentials implements LearningImageCredentials {
  @override
  Future<String?> load() async => null;
  @override
  Future<void> save(String key) async {}
  @override
  Future<void> delete() async {}
}

class _WaitingCredentials extends _Credentials {
  @override
  Future<String?> load() => Completer<String?>().future;
}

class _Store implements LearningImageStore {
  AiProvider provider = AiProvider.openai;
  @override
  Future<AiProvider> loadProvider() async => provider;
  @override
  Future<void> saveProvider(AiProvider value) async {
    provider = value;
  }

  _Store(this.records);
  List<LearningImageAttempt> records;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<List<LearningImageAttempt>> attempts() async {
    await gate?.future;
    if (fail) throw StateError('local unavailable');
    return records;
  }

  @override
  Future<void> putAttempt(LearningImageAttempt value) async {}
  @override
  Future<LearningImageMode> loadMode() async => LearningImageMode.precise;
  @override
  Future<void> saveMode(LearningImageMode mode) async {}
  @override
  Future<void> putMetadata(LearningImageMetadata metadata) async {}
  @override
  Future<LearningImageMetadata?> metadataFor(String id) async => null;
}

LearningImageAttempt _attempt(
  String id, {
  String? word,
  String? flow,
  DateTime? date,
  String model = 'gpt-image-2.5-sunburst',
  double usd = .02,
  bool unknown = false,
  String? outcome = 'succeeded',
}) => LearningImageAttempt(
  id: id,
  model: model,
  createdAt: date ?? DateTime(2026, 10, 4, 10),
  word: word,
  wordId: word,
  generationId: flow,
  outcome: outcome,
  status: 'completed',
  requestId: 'request-$id',
  searches: model == 'gpt-5.4-mini' ? 1 : null,
  usage: {
    'input_tokens': 100,
    'output_tokens': 200,
    'input_tokens_details': {
      'text_tokens': 100,
      'image_tokens': 0,
      'cached_tokens': 0,
    },
  },
  savedCost: LearningImageCost(usd: usd, unknown: unknown),
);

LearningImageNotifier _notifier(_Store store) => LearningImageNotifier(
  service: LearningImageService(),
  store: store,
  credentials: _Credentials(),
);
Future<void> _pump(WidgetTester tester, LearningImageNotifier notifier) async {
  await tester.binding.setSurfaceSize(const Size(390, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<LearningImageNotifier>.value(
      value: notifier,
      child: MaterialApp(
        home: LearningImageHistoryPage(now: () => DateTime(2026, 10, 4, 12)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'flows group by ID while legacy requests stay separate and preserve costs',
    () {
      final entries = LearningImageHistoryEntry.group([
        _attempt(
          'r',
          word: 'chirp',
          flow: 'flow1',
          model: 'gpt-5.4-mini',
          usd: .01,
        ),
        _attempt('i', word: 'chirp', flow: 'flow1', usd: .02, unknown: true),
        _attempt('again', word: 'chirp', flow: 'flow1', usd: .03),
        _attempt('old1', usd: .04, outcome: null),
        _attempt('old2', usd: .05, outcome: null),
        _attempt(
          'new',
          word: 'chirp',
          flow: 'flow2',
          date: DateTime(2026, 10, 4, 11),
        ),
      ]);
      expect(entries.length, 4);
      expect(entries.first.id, 'flow:flow2');
      final flow = entries.singleWhere((e) => e.id == 'flow:flow1');
      expect(flow.word, 'chirp');
      expect(flow.researchCostUsd, .01);
      expect(flow.imageCostUsd, closeTo(.05, 1e-8));
      expect(flow.knownCostUsd, closeTo(.06, 1e-8));
      expect(flow.unknownCount, 1);
      expect(flow.imageCount, 2);
      expect(entries.where((e) => e.word == null).length, 2);
    },
  );
  testWidgets('history read does not wait for unavailable secure storage', (
    tester,
  ) async {
    final notifier = LearningImageNotifier(
      service: LearningImageService(),
      store: _Store([_attempt('saved', word: 'chirp', flow: 'saved')]),
      credentials: _WaitingCredentials(),
    );
    unawaited(notifier.initialize());
    await _pump(tester, notifier);
    expect(find.text('chirp'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('empty history is accessible without API key', (tester) async {
    await _pump(tester, _notifier(_Store([])));
    expect(find.text('尚無 AI 費用紀錄'), findsOneWidget);
    expect(find.text('已知費用 US\$0.000000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'legacy rows disclose missing word and outcome, with actual fee snapshot',
    (tester) async {
      await _pump(
        tester,
        _notifier(_Store([_attempt('legacy', usd: .123, outcome: null)])),
      );
      expect(find.text('未記錄單字'), findsOneWidget);
      await tester.tap(find.text('未記錄單字'));
      await tester.pumpAndSettle();
      expect(find.text('圖片生成・未記錄結果'), findsOneWidget);
      expect(find.text('Request ID：request-legacy'), findsOneWidget);
      expect(find.text('已知費用：US\$0.123000'), findsOneWidget);
      expect(find.text('費率版本：2026-10-04'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'word search narrows both rows and totals, unknown expense stays explicit',
    (tester) async {
      await _pump(
        tester,
        _notifier(
          _Store([
            _attempt('c', word: 'chirp', flow: 'c', usd: .05, unknown: true),
            _attempt('a', word: 'anchor', flow: 'a', usd: .12),
          ]),
        ),
      );
      expect(find.text('已知費用 US\$0.170000'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'CHIRP');
      await tester.pumpAndSettle();
      expect(find.text('chirp'), findsOneWidget);
      expect(find.text('anchor'), findsNothing);
      expect(find.text('已知費用 US\$0.050000'), findsOneWidget);
      expect(find.text('1 筆請求費用不完整，總額可能更高'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('沒有符合條件的紀錄'), findsOneWidget);
    },
  );
  testWidgets('today filter counts only today requests within an older flow', (
    tester,
  ) async {
    await _pump(
      tester,
      _notifier(
        _Store([
          _attempt(
            'old-research',
            word: 'chirp',
            flow: 'same',
            model: 'gpt-5.4-mini',
            usd: .4,
            date: DateTime(2026, 10, 3),
          ),
          _attempt('today-image', word: 'chirp', flow: 'same', usd: .02),
          _attempt(
            'old-word',
            word: 'anchor',
            flow: 'old',
            usd: .5,
            date: DateTime(2026, 9, 1),
          ),
        ]),
      ),
    );
    await tester.tap(find.text('全部時間'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天').last);
    await tester.pumpAndSettle();
    expect(find.text('已知費用 US\$0.020000'), findsOneWidget);
    expect(find.text('目前篩選：1 個流程・1 筆請求'), findsOneWidget);
    expect(find.text('anchor'), findsNothing);
    await tester.tap(find.text('chirp'));
    await tester.pumpAndSettle();
    expect(find.text('核對與搜尋：US\$0.000000\n圖片生成：US\$0.020000'), findsOneWidget);
  });
  testWidgets(
    'loading failure can retry local history without a paid request',
    (tester) async {
      final store = _Store([])..fail = true;
      await _pump(tester, _notifier(store));
      expect(find.text('重新讀取紀錄'), findsOneWidget);
      store.fail = false;
      await tester.tap(find.text('重新讀取紀錄'));
      await tester.pumpAndSettle();
      expect(find.text('尚無 AI 費用紀錄'), findsOneWidget);
    },
  );
  testWidgets('history follows new records while the page stays open', (
    tester,
  ) async {
    final store = _Store([]);
    final notifier = _notifier(store);
    await _pump(tester, notifier);
    store.records.add(_attempt('new', word: 'chirp', flow: 'new', usd: .09));
    await notifier.refreshHistory();
    await tester.pumpAndSettle();
    expect(find.text('chirp'), findsOneWidget);
    expect(find.text('已知費用 US\$0.090000'), findsOneWidget);
    expect(find.text('尚無 AI 費用紀錄'), findsNothing);
  });
  testWidgets('settings history entry opens without a configured key', (
    tester,
  ) async {
    final notifier = _notifier(_Store([]));
    await notifier.initialize();
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: notifier,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiLearningImageSettings()),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('AI 費用紀錄'));
    await tester.tap(find.text('AI 費用紀錄'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningImageHistoryPage), findsOneWidget);
    expect(find.text('尚無 AI 費用紀錄'), findsOneWidget);
  });
}
