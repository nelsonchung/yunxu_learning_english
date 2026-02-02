import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/date_utils.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        if (notifier.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final dueList = notifier.dueToday();
        if (dueList.isEmpty) {
          return const Center(
            child: Text('今天沒有需要複習的單字'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: dueList.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final card = dueList[index];
            return _ReviewCard(
              card: card,
              onReview: () => notifier.markReviewed(card),
              onTap: () => Navigator.pushNamed(
                context,
                '/detail',
                arguments: card,
              ),
            );
          },
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.card,
    required this.onReview,
    required this.onTap,
  });

  final WordCard card;
  final VoidCallback onReview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (card.imagePath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(card.imagePath!),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (card.imagePath != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.word,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.sentences.isNotEmpty
                            ? card.sentences.first
                            : '無例句',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text('下次複習：${formatDate(card.nextReviewDate)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: onTap,
                  child: const Text('查看詳情'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: onReview,
                  child: const Text('完成複習'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
