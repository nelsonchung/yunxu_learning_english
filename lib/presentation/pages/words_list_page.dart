import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/words_notifier.dart';
import '../widgets/date_utils.dart';
import '../widgets/sort_selector.dart';

class WordsListPage extends StatelessWidget {
  const WordsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final words = notifier.words;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Text('排序：'),
                  SortSelector(
                    mode: notifier.sortMode,
                    onChanged: notifier.setSortMode,
                  ),
                ],
              ),
            ),
            Expanded(
              child: words.isEmpty
                  ? const Center(child: Text('尚未新增單字'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: words.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final card = words[index];
                        return ListTile(
                          leading: card.imagePath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(card.imagePath!),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : const CircleAvatar(child: Icon(Icons.book)),
                          title: Text(card.word),
                          subtitle: Text(
                            '建立日：${formatDate(card.createdAt)}\n下次複習：${formatDate(card.nextReviewDate)}',
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/detail',
                            arguments: card,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
