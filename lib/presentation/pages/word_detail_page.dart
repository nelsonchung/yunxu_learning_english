import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/word_card.dart';
import '../state/words_notifier.dart';
import '../widgets/app_background.dart';
import '../widgets/date_utils.dart';
import '../widgets/section_card.dart';

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
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Container(
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (card.imagePath != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.calendar_today,
                            label: '建立日 ${formatDate(card.createdAt)}',
                          ),
                          _InfoChip(
                            icon: Icons.schedule,
                            label: '下次複習 ${formatDate(card.nextReviewDate)}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '例句',
                subtitle: '共 ${card.sentences.length} 句',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: card.sentences
                      .map(
                        (sentence) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $sentence'),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: '複習紀錄',
                subtitle: '完成 ${card.history.length} 次',
                child: card.history.isEmpty
                    ? const Text('尚未完成任何複習')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: card.history
                            .map((date) => Text('• ${formatDate(date)}'))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF0B6E99)),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
