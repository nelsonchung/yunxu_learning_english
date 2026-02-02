import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/date_utils.dart';

class WordDetailPage extends StatelessWidget {
  const WordDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final card = ModalRoute.of(context)?.settings.arguments as WordCard?;
    if (card == null) {
      return const Scaffold(
        body: Center(child: Text('找不到單字資料')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(card.word),
        actions: [
          IconButton(
            onPressed: () async {
              final notifier = context.read<WordsNotifier>();
              await notifier.deleteWord(card);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            tooltip: '刪除單字',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (card.imagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(card.imagePath!),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (card.imagePath != null) const SizedBox(height: 16),
          Text(
            card.word,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text('例句'),
          const SizedBox(height: 8),
          ...card.sentences.map(
            (sentence) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $sentence'),
            ),
          ),
          const SizedBox(height: 12),
          Text('建立日：${formatDate(card.createdAt)}'),
          Text('下次複習：${formatDate(card.nextReviewDate)}'),
          const SizedBox(height: 16),
          const Text('複習紀錄'),
          const SizedBox(height: 8),
          if (card.history.isEmpty)
            const Text('尚未完成任何複習')
          else
            ...card.history.map((date) => Text('• ${formatDate(date)}')),
        ],
      ),
    );
  }
}
