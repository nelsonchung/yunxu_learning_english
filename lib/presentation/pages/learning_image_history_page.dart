import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/learning_image.dart';
import '../../domain/models/learning_image_history.dart';
import '../state/learning_image_notifier.dart';

enum _HistoryPeriod { all, today, week, month }

class LearningImageHistoryPage extends StatefulWidget {
  const LearningImageHistoryPage({super.key, this.now});
  final DateTime Function()? now;

  @override
  State<LearningImageHistoryPage> createState() =>
      _LearningImageHistoryPageState();
}

class _LearningImageHistoryPageState extends State<LearningImageHistoryPage> {
  Future<void>? _load;
  String _query = '';
  _HistoryPeriod _period = _HistoryPeriod.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= context.read<LearningImageNotifier>().refreshHistory();
  }

  bool _matchesPeriod(LearningImageAttempt attempt) {
    if (_period == _HistoryPeriod.all) return true;
    final now = (widget.now?.call() ?? DateTime.now()).toLocal();
    final cutoff = switch (_period) {
      _HistoryPeriod.all => now,
      _HistoryPeriod.today => DateTime(now.year, now.month, now.day),
      _HistoryPeriod.week => now.subtract(const Duration(days: 7)),
      _HistoryPeriod.month => now.subtract(const Duration(days: 30)),
    };
    final end = _period == _HistoryPeriod.today
        ? DateTime(now.year, now.month, now.day + 1)
        : now.add(const Duration(microseconds: 1));
    return !attempt.createdAt.isBefore(cutoff) &&
        attempt.createdAt.isBefore(end);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<LearningImageNotifier>();
    return Scaffold(
      appBar: AppBar(title: const Text('AI 費用紀錄')),
      body: FutureBuilder<void>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (notifier.historyError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(notifier.historyError!),
                    TextButton(
                      onPressed: () => setState(() {
                        _load = notifier.refreshHistory();
                      }),
                      child: const Text('重新讀取紀錄'),
                    ),
                  ],
                ),
              ),
            );
          }
          final entries =
              LearningImageHistoryEntry.group(
                    notifier.attempts.where(_matchesPeriod),
                  )
                  .where(
                    (entry) =>
                        _query.isEmpty ||
                        (entry.word ?? '').toLowerCase().contains(_query),
                  )
                  .toList();
          final knownUsd = entries.fold<double>(
            0,
            (sum, entry) => sum + entry.knownCostUsd,
          );
          final unknown = entries.fold<int>(
            0,
            (sum, entry) => sum + entry.unknownCount,
          );
          final count = entries.fold<int>(
            0,
            (sum, entry) => sum + entry.attempts.length,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: '搜尋單字',
                  prefixIcon: Icon(Icons.search),
                  hintText: '例如 chirp',
                ),
                onChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_HistoryPeriod>(
                initialValue: _period,
                decoration: const InputDecoration(labelText: '查詢期間'),
                items: const [
                  DropdownMenuItem(
                    value: _HistoryPeriod.all,
                    child: Text('全部時間'),
                  ),
                  DropdownMenuItem(
                    value: _HistoryPeriod.today,
                    child: Text('今天'),
                  ),
                  DropdownMenuItem(
                    value: _HistoryPeriod.week,
                    child: Text('最近 7 天'),
                  ),
                  DropdownMenuItem(
                    value: _HistoryPeriod.month,
                    child: Text('最近 30 天'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _period = value);
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('目前篩選：${entries.length} 個流程・$count 筆請求'),
                      Text(
                        '已知費用 ${_usd(knownUsd)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '約 NT\$${(knownUsd * LearningImageCost.exchangeRate).toStringAsFixed(2)}',
                      ),
                      if (unknown > 0) Text('$unknown 筆請求費用不完整，總額可能更高'),
                      const SizedBox(height: 8),
                      const Text(
                        '依 API 用量及儲存的費率計算，不代表最終帳單。台幣以 US\$1＝NT\$32 的預算匯率換算。',
                      ),
                    ],
                  ),
                ),
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    notifier.attempts.isEmpty ? '尚無 AI 費用紀錄' : '沒有符合條件的紀錄',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final entry in entries) _HistoryEntryCard(entry: entry),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('紀錄保存在此裝置。舊版未記錄單字及流程關聯的請求會分開列出，不會推測或合併。'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});
  final LearningImageHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isVoicePractice = entry.attempts.any((a) => a.model == 'gpt-live-1');
    final modes = entry.attempts
        .where(LearningImageHistoryEntry.isImage)
        .map(
          (a) => a.model == LearningImageMode.precise.model
              ? '精緻模式'
              : a.model == LearningImageMode.fast.model
              ? '快速模式'
              : a.model,
        )
        .toSet();
    final activity = isVoicePractice
        ? 'AI 口說練習'
        : '${modes.isEmpty ? '核對與搜尋' : modes.join('／')}・產圖嘗試 ${entry.imageCount} 次';
    return Card(
      child: ExpansionTile(
        key: ValueKey(entry.id),
        title: Text(entry.word ?? '未記錄單字'),
        subtitle: Text(
          '${_date(entry.latestAt)}\n'
          '$activity\n'
          '已知費用 ${_usd(entry.knownCostUsd)}${entry.unknownCount > 0 ? '（部分未知）' : ''}',
        ),
        children: [
          if (!isVoicePractice)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '核對與搜尋：${_usd(entry.researchCostUsd)}\n圖片生成：${_usd(entry.imageCostUsd)}'
                  '${entry.otherCostUsd > 0 ? '\n其他請求：${_usd(entry.otherCostUsd)}' : ''}',
                ),
              ),
            ),
          for (final attempt in entry.attempts)
            _AttemptDetail(attempt: attempt),
        ],
      ),
    );
  }
}

class _AttemptDetail extends StatelessWidget {
  const _AttemptDetail({required this.attempt});
  final LearningImageAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final usage = attempt.usage;
    final isLive = attempt.model == 'gpt-live-1';
    final details = usage?['input_tokens_details'] is Map
        ? usage!['input_tokens_details'] as Map
        : null;
    String count(dynamic value) =>
        value is int && value >= 0 ? '$value' : '未提供';
    final phase = LearningImageHistoryEntry.isResearch(attempt)
        ? '核對與搜尋'
        : LearningImageHistoryEntry.isImage(attempt)
        ? '圖片生成'
        : isLive
        ? '即時語音'
        : attempt.model == 'gpt-6-luna'
        ? '口說用詞回饋'
        : '其他請求';
    final result = switch (attempt.outcome) {
      'inProgress' => '結果未確認',
      'succeeded' => '完成',
      'failed' => '失敗',
      'cancelled' => '已取消',
      'timedOut' => '逾時',
      'notSent' => '未送出',
      _ => '未記錄結果',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text('$phase・$result', style: Theme.of(context).textTheme.titleSmall),
          Text(_date(attempt.createdAt)),
          Text(
            '已知費用：${_usd(attempt.cost.usd)}${attempt.cost.unknown ? '（費用不完整）' : ''}',
          ),
          Text(
            '用量狀態：${attempt.status == 'completed'
                ? '已收到用量'
                : attempt.status == 'not_sent'
                ? '未送出請求'
                : '用量未確認'}',
          ),
          Text('模型：${attempt.model}'),
          if (isLive)
            Text('計費秒數：${usage?['seconds'] ?? '未提供'}')
          else ...[
            Text('輸入 tokens：${count(usage?['input_tokens'])}'),
            Text('輸出 tokens：${count(usage?['output_tokens'])}'),
          ],
          if (LearningImageHistoryEntry.isResearch(attempt)) ...[
            Text('快取輸入 tokens：${count(details?['cached_tokens'])}'),
            Text('搜尋次數：${count(attempt.searches)}'),
          ] else if (LearningImageHistoryEntry.isImage(attempt)) ...[
            Text('文字輸入 tokens：${count(details?['text_tokens'])}'),
            Text('圖片輸入 tokens：${count(details?['image_tokens'])}'),
          ],
          Text('費率版本：${attempt.rateDate}'),
          SelectableText('Request ID：${attempt.requestId ?? '未取得'}'),
          if (attempt.generationId != null)
            SelectableText('流程 ID：${attempt.generationId}'),
          SelectableText('紀錄 ID：${attempt.id}'),
        ],
      ),
    );
  }
}

String _usd(double value) => 'US\$${value.toStringAsFixed(6)}';
String _date(DateTime value) {
  final date = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}/${pad(date.month)}/${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}
