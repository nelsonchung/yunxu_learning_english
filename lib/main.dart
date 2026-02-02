import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'data/repositories/local_word_repository.dart';
import 'data/sources/word_local_db.dart';
import 'data/storage/image_storage.dart';
import 'domain/services/review_schedule_service.dart';
import 'domain/services/sort_service.dart';
import 'presentation/pages/add_word_page.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/word_detail_page.dart';
import 'presentation/state/words_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final scheduleService = ReviewScheduleService();
  final repository = LocalWordRepository(
    localDb: WordLocalDb(),
    scheduleService: scheduleService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => WordsNotifier(
            repository: repository,
            scheduleService: scheduleService,
            sortService: SortService(),
            imageStorage: ImageStorage(),
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
      title: '英文學習',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const HomePage(),
        '/add': (context) => const AddWordPage(),
        '/detail': (context) => const WordDetailPage(),
      },
    );
  }
}
