import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/app_background.dart';
import 'about_page.dart';
import 'records_page.dart';
import 'settings_page.dart';
import 'today_page.dart';
import 'words_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return const TodayPage();
      case 1:
        return const WordsListPage();
      case 2:
        return const SettingsPage();
      case 3:
        return const RecordsPage();
      case 4:
      default:
        return const AboutPage();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wordsNotifier = context.read<WordsNotifier>();
      final settingsNotifier = context.read<SettingsNotifier>();
      wordsNotifier.load();
      settingsNotifier.load().then((_) {
        wordsNotifier.setSyncEnabled(settingsNotifier.syncEnabled);
        wordsNotifier.setSyncIntervalSeconds(
          settingsNotifier.syncIntervalSeconds,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('英文學習')),
      body: AppBackground(child: _buildCurrentPage()),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/add'),
        tooltip: '新增單字',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: '今日複習'),
          NavigationDestination(icon: Icon(Icons.list), label: '單字列表'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '設定',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: '紀錄',
          ),
          NavigationDestination(icon: Icon(Icons.info_outline), label: '說明'),
        ],
      ),
    );
  }
}
