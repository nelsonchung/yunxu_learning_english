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
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            _HeroHeader(total: dueList.length),
            const SizedBox(height: 16),
            if (dueList.isEmpty)
              const _EmptyState()
            else
              ...dueList.map(
                (card) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ReviewCard(
                    card: card,
                    onReview: () => notifier.markReviewed(card),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/detail',
                      arguments: card,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B6E99), Color(0xFF1CA7A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日複習',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  total.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '依照遺忘曲線安排的複習卡片',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: const [
                    _Pill(text: '1'),
                    _Pill(text: '2'),
                    _Pill(text: '3'),
                    _Pill(text: '5'),
                    _Pill(text: '7'),
                    _Pill(text: '12'),
                    _Pill(text: '19'),
                    _Pill(text: '31'),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.auto_graph,
            color: Colors.white70,
            size: 42,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0B6E99).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF0B6E99)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('今天沒有需要複習的單字，做得很好！'),
          ),
        ],
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (card.imagePath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(card.imagePath!),
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B6E99).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.book, color: Color(0xFF0B6E99)),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.word,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card.sentences.isNotEmpty
                                ? card.sentences.first
                                : '無例句',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${card.meaning} · ${card.partOfSpeech.label}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 16),
                              const SizedBox(width: 4),
                              Text('下次：${formatDate(card.nextReviewDate)}'),
                            ],
                          ),
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
        ),
      ),
    );
  }
}
