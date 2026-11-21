import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunxu_learning_english/data/storage/learning_image_store.dart';
import 'package:yunxu_learning_english/data/repositories/word_repository.dart';
import 'package:yunxu_learning_english/data/repositories/settings_repository.dart';
import 'package:yunxu_learning_english/domain/services/notification_service.dart';
import 'package:yunxu_learning_english/domain/services/pronunciation_service.dart';
import 'package:yunxu_learning_english/presentation/state/settings_notifier.dart';
import 'package:yunxu_learning_english/presentation/pages/word_detail_page.dart';
import 'package:yunxu_learning_english/data/storage/image_storage.dart';
import 'package:yunxu_learning_english/domain/services/review_schedule_service.dart';
import 'package:yunxu_learning_english/domain/services/sort_service.dart';
import 'package:yunxu_learning_english/domain/services/word_contribution_import_service.dart';
import 'package:yunxu_learning_english/presentation/state/words_notifier.dart';
import 'package:yunxu_learning_english/domain/models/learning_image.dart';
import 'package:yunxu_learning_english/domain/models/ai_provider.dart';
import 'package:yunxu_learning_english/domain/models/word_card.dart';
import 'package:yunxu_learning_english/presentation/pages/learning_image_page.dart';
import 'package:yunxu_learning_english/domain/services/learning_image_service.dart';
import 'package:yunxu_learning_english/presentation/state/learning_image_notifier.dart';
import 'package:yunxu_learning_english/presentation/widgets/ai_learning_image_settings.dart';

class _Credentials implements LearningImageCredentials {
  String? key;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String?> load() async => key;
  @override
  Future<void> save(String value) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('storage unavailable');
    key = value;
  }

  @override
  Future<void> delete() async {
    if (fail) throw StateError('storage unavailable');
    key = null;
  }
}

class _Store implements LearningImageStore {
  AiProvider provider = AiProvider.openai;
  @override
  Future<AiProvider> loadProvider() async => provider;
  @override
  Future<void> saveProvider(AiProvider value) async {
    provider = value;
  }

  LearningImageMode mode = LearningImageMode.precise;
  @override
  Future<List<LearningImageAttempt>> attempts() async => [];
  @override
  Future<void> putAttempt(LearningImageAttempt attempt) async {}
  @override
  Future<LearningImageMode> loadMode() async => mode;
  @override
  Future<void> saveMode(LearningImageMode value) async {
    mode = value;
  }

  @override
  Future<void> putMetadata(LearningImageMetadata metadata) async {}
  @override
  Future<LearningImageMetadata?> metadataFor(String wordId) async => null;
}

class _UiNotifier extends LearningImageNotifier {
  _UiNotifier()
    : super(
        service: LearningImageService(),
        store: _Store(),
        credentials: _Credentials(),
      );
  bool? usedExisting;
  int regenerated = 0;
  WordCard? started;
  LearningImageMetadata? savedMetadata;
  @override
  Future<LearningImageMetadata?> metadataFor(String wordId) async =>
      savedMetadata;
  @override
  Future<void> start(WordCard card) async {
    started = card;
  }

  @override
  Future<void> resolveConflict({required bool useExisting}) async {
    usedExisting = useExisting;
  }

  @override
  Future<void> regenerate() async {
    regenerated++;
  }
}

WordCard _word() {
  final now = DateTime(2026, 10, 4);
  return WordCard(
    id: 'chirp',
    word: 'chirp',
    meaning: '啁啾',
    sentences: ['Birds chirp.'],
    origin: WordOrigin.manual,
    createdAt: now,
    updatedAt: now,
    reviewSchedule: [1],
    nextReviewIndex: 0,
    nextReviewDate: now,
    history: [],
    isDeleted: false,
  );
}

const _content = LearningImageContent(
  word: 'chirp',
  meaning: '發出短促尖細聲',
  partsOfSpeech: 'verb',
  sentences: ['Birds chirp. 鳥兒啁啾。'],
  memoryHint: '',
  diagram: '',
  conflict: '詞義需補充',
);

class _Repository implements WordRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsRepository implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends SettingsNotifier {
  _Settings()
    : super(
        repository: _SettingsRepository(),
        notificationService: NotificationService(),
        pronunciationService: PronunciationService(),
      );
  @override
  bool get showImages => false;
}

class _Words extends WordsNotifier {
  _Words(this.latest)
    : super(
        repository: _Repository(),
        scheduleService: ReviewScheduleService(),
        sortService: SortService(),
        imageStorage: ImageStorage(),
        wordContributionImportService: WordContributionImportService(
          scheduleService: ReviewScheduleService(),
        ),
      );
  WordCard? latest;
  int applies = 0;
  Completer<void>? applyGate;
  @override
  WordCard? findById(String id) => latest;
  @override
  Future<void> updateWordImage(
    String id,
    List<int> bytes, {
    WordCard? expectedCard,
    bool allowImageReplacement = false,
  }) async {
    applies++;
    if (applyGate != null) await applyGate!.future;
  }
}

Future<void> _pumpReady(
  WidgetTester tester,
  _UiNotifier ai,
  _Words words,
) async {
  ai.hasKey = true;
  ai.hasOpenAiKey = true;
  ai.stage = LearningImageStage.ready;
  ai.sourceWord = _word();
  ai.content = _content;
  ai.imageBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=',
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LearningImageNotifier>.value(value: ai),
        ChangeNotifierProvider<WordsNotifier>.value(value: words),
      ],
      child: MaterialApp(home: LearningImagePage(initialWord: _word())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('使用這張圖片'), 300);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('switching provider clears drafts and edits only its own key', (
    tester,
  ) async {
    final openai = _Credentials()..key = 'original-openai';
    final claude = _Credentials();
    final ai = LearningImageNotifier(
      service: LearningImageService(),
      store: _Store(),
      credentials: openai,
      claudeCredentials: claude,
    );
    addTearDown(ai.dispose);
    await ai.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: ai,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiLearningImageSettings()),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'unsaved-openai');
    await tester.tap(find.byTooltip('顯示金鑰'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<AiProvider>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude').last);
    await tester.pumpAndSettle();
    expect(ai.provider, AiProvider.claude);
    expect(find.text('Claude API Key'), findsOneWidget);
    expect(find.text('尚未設定 API Key'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.enterText(find.byType(TextField), 'claude-key');
    await tester.pump();
    await tester.tap(find.text('儲存金鑰'));
    await tester.pumpAndSettle();
    expect(claude.key, 'claude-key');
    expect(openai.key, 'original-openai');
    await tester.tap(find.text('刪除金鑰'));
    await tester.pumpAndSettle();
    expect(claude.key, isNull);
    expect(openai.key, 'original-openai');
  });

  testWidgets(
    'applying locks navigation and the generation session until save settles',
    (tester) async {
      final ai = _UiNotifier();
      final words = _Words(_word())..applyGate = Completer<void>();
      await _pumpReady(tester, ai, words);
      await tester.tap(find.text('使用這張圖片'));
      await tester.pump();
      expect(ai.isApplying, isTrue);
      ai.discard();
      expect(ai.content, isNotNull);
      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
      words.applyGate!.completeError(StateError('disk failure'));
      await tester.pumpAndSettle();
      expect(ai.isApplying, isFalse);
      expect(ai.content, isNotNull);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
    },
  );

  testWidgets(
    'saved sources survive container relocation but hide after replacement',
    (tester) async {
      final ai = _UiNotifier()
        ..savedMetadata = LearningImageMetadata(
          wordId: 'chirp',
          imageIdentity: '/old-container/unique.png',
          content: _content,
          model: 'test',
          createdAt: DateTime(2026),
        );
      final words = _Words(
        _word().copyWith(imagePath: '/new-container/unique.png'),
      );
      Future<void> pumpDetail() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<PronunciationService>(
                create: (_) => PronunciationService(),
              ),
              ChangeNotifierProvider<LearningImageNotifier>.value(value: ai),
              ChangeNotifierProvider<WordsNotifier>.value(value: words),
              ChangeNotifierProvider<SettingsNotifier>(
                create: (_) => _Settings(),
              ),
            ],
            child: MaterialApp(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                settings: const RouteSettings(arguments: 'chirp'),
                builder: (_) => const WordDetailPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpDetail();
      expect(find.text('AI 圖片參考來源'), findsOneWidget);
      words.latest = _word().copyWith(imagePath: '/new-container/replaced.png');
      await tester.pumpWidget(const SizedBox());
      await pumpDetail();
      expect(find.text('AI 圖片參考來源'), findsNothing);
    },
  );

  testWidgets('restored mode updates an already mounted dropdown', (
    tester,
  ) async {
    final store = _Store()..mode = LearningImageMode.fast;
    final ai = LearningImageNotifier(
      service: LearningImageService(),
      store: store,
      credentials: _Credentials(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: ai,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiLearningImageSettings()),
          ),
        ),
      ),
    );
    await ai.initialize();
    await tester.pumpAndSettle();
    final state = tester.state<FormFieldState<LearningImageMode>>(
      find.byType(DropdownButtonFormField<LearningImageMode>),
    );
    expect(state.value, LearningImageMode.fast);
  });
  testWidgets('storage failures preserve key status and render a local error', (
    tester,
  ) async {
    final credentials = _Credentials()
      ..key = 'old'
      ..fail = true;
    final ai = LearningImageNotifier(
      service: LearningImageService(),
      store: _Store(),
      credentials: credentials,
    );
    await ai.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: ai,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiLearningImageSettings()),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('儲存金鑰'));
    await tester.pumpAndSettle();
    expect(find.text('無法更新金鑰，請確認裝置安全儲存可用'), findsOneWidget);
    expect(credentials.key, 'old');
    await tester.tap(find.text('刪除金鑰'));
    await tester.pumpAndSettle();
    expect(credentials.key, 'old');
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending secure save can complete after leaving settings', (
    tester,
  ) async {
    final credentials = _Credentials()..gate = Completer<void>();
    final ai = LearningImageNotifier(
      service: LearningImageService(),
      store: _Store(),
      credentials: credentials,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: ai,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiLearningImageSettings()),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('儲存金鑰'));
    await tester.pumpWidget(const SizedBox());
    credentials.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('deleted word blocks applying a ready image', (tester) async {
    final ai = _UiNotifier();
    final words = _Words(null);
    await _pumpReady(tester, ai, words);
    await tester.tap(find.text('使用這張圖片'));
    await tester.pump();
    expect(find.text('單字已刪除，無法套用圖片'), findsOneWidget);
    expect(words.applies, 0);
  });
  testWidgets('image clear during generation requires explicit confirmation', (
    tester,
  ) async {
    final ai = _UiNotifier();
    final words = _Words(_word().copyWith(imageCleared: true));
    await _pumpReady(tester, ai, words);
    await tester.tap(find.text('使用這張圖片'));
    await tester.pumpAndSettle();
    expect(find.text('圖片已變更'), findsOneWidget);
    await tester.tap(find.text('保留目前圖片'));
    await tester.pumpAndSettle();
    expect(words.applies, 0);
  });
  testWidgets(
    'stale text discards obsolete preview and restarts with latest word',
    (tester) async {
      final ai = _UiNotifier();
      final latest = _word().copyWith(meaning: '更新的意思');
      final words = _Words(latest);
      await _pumpReady(tester, ai, words);
      await tester.tap(find.text('使用這張圖片'));
      await tester.pumpAndSettle();
      expect(words.applies, 0);
      expect(ai.content, isNull);
      await tester.ensureVisible(find.text('核對並生成圖片'));
      await tester.tap(find.text('核對並生成圖片'));
      expect(ai.started?.meaning, '更新的意思');
    },
  );

  testWidgets('conflict choices show the actual difference before generation', (
    tester,
  ) async {
    final notifier = _UiNotifier()
      ..hasOpenAiKey = true
      ..hasKey = true
      ..stage = LearningImageStage.conflict
      ..sourceWord = _word()
      ..content = _content;
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: notifier,
        child: MaterialApp(home: LearningImagePage(initialWord: _word())),
      ),
    );
    expect(find.text('差異：詞義需補充'), findsOneWidget);
    expect(find.text('核對中文：發出短促尖細聲'), findsOneWidget);
    await tester.tap(find.text('使用目前內容'));
    expect(notifier.usedExisting, isTrue);
  });
  testWidgets('failed image request retries only image using vetted content', (
    tester,
  ) async {
    final notifier = _UiNotifier()
      ..hasOpenAiKey = true
      ..hasKey = true
      ..stage = LearningImageStage.failed
      ..sourceWord = _word()
      ..content = _content
      ..error = '模型無權限';
    await tester.pumpWidget(
      ChangeNotifierProvider<LearningImageNotifier>.value(
        value: notifier,
        child: MaterialApp(home: LearningImagePage(initialWord: _word())),
      ),
    );
    expect(find.text('模型無權限'), findsOneWidget);
    await tester.tap(find.text('重新生成圖片（再次計費）'));
    expect(notifier.regenerated, 1);
  });

  testWidgets('settings are optional in existing provider trees', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiLearningImageSettings())),
    );
    expect(find.text('AI 學習圖卡'), findsNothing);
  });
  testWidgets('key visibility, save and delete use credentials only', (
    tester,
  ) async {
    final credentials = _Credentials();
    final notifier = LearningImageNotifier(
      service: LearningImageService(),
      store: _Store(),
      credentials: credentials,
    );
    await notifier.initialize();
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
    expect(find.text('尚未設定 API Key'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-test-only');
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('顯示金鑰'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
    await tester.pump();
    await tester.tap(find.text('儲存金鑰'));
    await tester.pumpAndSettle();
    expect(credentials.key, 'sk-test-only');
    expect(find.text('API Key 已設定'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('刪除金鑰'));
    await tester.pumpAndSettle();
    expect(credentials.key, isNull);
    expect(find.text('尚未設定 API Key'), findsOneWidget);
  });
}
