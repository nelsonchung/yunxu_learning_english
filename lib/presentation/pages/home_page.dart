import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/words_notifier.dart';
import '../state/settings_notifier.dart';
import '../widgets/app_background.dart';
import 'about_page.dart';
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

  final _pages = const [
    TodayPage(),
    WordsListPage(),
    AboutPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WordsNotifier>().load();
      context.read<SettingsNotifier>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('英文學習'),
      ),
      body: AppBackground(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
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
          NavigationDestination(
            icon: Icon(Icons.today),
            label: '今日複習',
          ),
          NavigationDestination(
            icon: Icon(Icons.list),
            label: '單字列表',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            label: '說明',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
