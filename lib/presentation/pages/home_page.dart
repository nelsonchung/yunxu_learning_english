import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/words_notifier.dart';
import 'about_page.dart';
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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WordsNotifier>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('英文學習'),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/add'),
        tooltip: '新增單字',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.today),
            label: '今日複習',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '單字列表',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info_outline),
            label: '說明',
          ),
        ],
      ),
    );
  }
}
