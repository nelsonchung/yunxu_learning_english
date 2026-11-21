import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'data/repositories/builtin_word_bank_repository.dart';
import 'data/repositories/local_word_repository.dart';
import 'data/sources/word_local_db.dart';
import 'data/storage/image_storage.dart';
import 'data/storage/learning_image_store.dart';
import 'domain/services/learning_image_service.dart';
import 'domain/models/ai_provider.dart';
import 'presentation/state/learning_image_notifier.dart';
import 'data/repositories/local_settings_repository.dart';
import 'data/sources/settings_local_db.dart';
import 'data/repositories/local_sync_state_repository.dart';
import 'data/sources/sync_state_local_db.dart';
import 'domain/services/review_schedule_service.dart';
import 'domain/services/word_extension_service.dart';
import 'domain/services/sort_service.dart';
import 'domain/services/notification_service.dart';
import 'domain/services/cloud_sync_service.dart';
import 'domain/services/daily_word_recommendation_service.dart';
import 'domain/services/install_state_service.dart';
import 'domain/services/pronunciation_service.dart';
import 'domain/services/voice_practice_service.dart';
import 'domain/services/word_contribution_import_service.dart';
import 'domain/services/word_contribution_share_service.dart';
import 'data/storage/picture_catalog_store.dart';
import 'domain/services/online_picture_service.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/pages/add_word_page.dart';
import 'presentation/pages/edit_word_page.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/word_detail_page.dart';
import 'presentation/state/settings_notifier.dart';
import 'presentation/state/words_notifier.dart';

const bool _enableIOSCloudSync = bool.fromEnvironment('ENABLE_IOS_CLOUD_SYNC');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 80;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20;
  await Hive.initFlutter();

  final scheduleService = ReviewScheduleService();
  final repository = LocalWordRepository(
    localDb: WordLocalDb(),
    scheduleService: scheduleService,
  );
  final settingsRepository = LocalSettingsRepository(
    localDb: SettingsLocalDb(),
  );
  final builtinWordBankRepository = BuiltinWordBankRepository();
  final dailyWordRecommendationService = DailyWordRecommendationService();
  final initialSettings = await settingsRepository.fetch();
  final syncStateRepository = LocalSyncStateRepository(
    localDb: SyncStateLocalDb(),
  );
  final notificationService = NotificationService();
  await notificationService.initialize();
  final pronunciationService = PronunciationService();
  await pronunciationService.initialize(initialSettings);
  final openAiCredentials = SecureLearningImageCredentials();
  final aiHistoryStore = HiveLearningImageStore();
  final wordContributionImportService = WordContributionImportService(
    scheduleService: scheduleService,
  );
  final installStateService = InstallStateService();
  var allowAutoRestoreWhenLocalEmpty = true;
  if (Platform.isIOS) {
    allowAutoRestoreWhenLocalEmpty = await installStateService
        .shouldAutoRestoreOnEmptyData();
  }
  CloudSyncService? cloudSyncService;
  final cloudSyncAvailable =
      Platform.isMacOS || (Platform.isIOS && _enableIOSCloudSync);
  if (cloudSyncAvailable) {
    cloudSyncService = CloudSyncService(
      wordRepository: repository,
      settingsRepository: settingsRepository,
      syncStateRepository: syncStateRepository,
      containerId: 'iCloud.com.yunxu.yunxulearn',
      allowAutoRestoreWhenLocalEmpty: allowAutoRestoreWhenLocalEmpty,
    );
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<OnlinePictureService>(
          create: (_) {
            final store = PictureCatalogStore();
            return OnlinePictureService(
              readCache: store.read,
              writeCache: store.write,
              saveSource: store.saveSource,
            );
          },
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider<LearningImageNotifier>(
          create: (_) => LearningImageNotifier(
            service: LearningImageService(),
            store: aiHistoryStore,
            credentials: openAiCredentials,
            claudeCredentials: SecureLearningImageCredentials(
              provider: AiProvider.claude,
            ),
          )..initialize(),
        ),
        Provider<PronunciationService>.value(value: pronunciationService),
        if (Platform.isIOS)
          Provider<VoicePracticeService>(
            create: (_) => VoicePracticeService(
              loadOpenAiKey: openAiCredentials.load,
              saveAttempt: aiHistoryStore.putAttempt,
            ),
            dispose: (_, service) => service.dispose(),
          ),
        Provider<BuiltinWordBankRepository>.value(
          value: builtinWordBankRepository,
        ),
        Provider<WordExtensionService>(
          create: (_) => WordExtensionService(
            loadEntries: builtinWordBankRepository.fetchAll,
          ),
        ),
        Provider<DailyWordRecommendationService>.value(
          value: dailyWordRecommendationService,
        ),
        Provider<WordContributionShareService>(
          create: (_) => WordContributionShareService(),
        ),
        ChangeNotifierProvider(
          create: (_) => WordsNotifier(
            repository: repository,
            scheduleService: scheduleService,
            sortService: SortService(),
            imageStorage: ImageStorage(),
            wordContributionImportService: wordContributionImportService,
            syncStateRepository: syncStateRepository,
            syncService: cloudSyncService,
            initialSyncEnabled: initialSettings.syncEnabled,
            initialSyncIntervalSeconds: initialSettings.syncIntervalSeconds,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsNotifier(
            repository: settingsRepository,
            notificationService: notificationService,
            pronunciationService: pronunciationService,
          ),
        ),
      ],
      child: const EnglishLearningApp(),
    ),
  );
}

class EnglishLearningApp extends StatelessWidget {
  const EnglishLearningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '英文學習',
      theme: AppTheme.light(),
      routes: {
        '/': (context) => const HomePage(),
        '/add': (context) => const AddWordPage(),
        '/edit': (context) => const EditWordPage(),
        '/detail': (context) => const WordDetailPage(),
      },
    );
  }
}
