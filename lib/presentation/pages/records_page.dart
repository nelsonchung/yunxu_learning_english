import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/models/sync_state.dart';
import '../../domain/models/word_card.dart';
import '../../domain/services/learning_progress_service.dart';
import '../state/words_notifier.dart';
import '../widgets/section_card.dart';

enum _ActivityViewMode { week, month }

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  _ActivityViewMode _viewMode = _ActivityViewMode.week;
  int _weekOffset = 0;
  int _monthOffset = 0;
  DateTime? _selectedCalendarDay;

  @override
  Widget build(BuildContext context) {
    return Consumer<WordsNotifier>(
      builder: (context, notifier, _) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        const progressService = LearningProgressService();
        final progress = progressService.summarize(notifier.words, now: now);
        final selectedEndDay = DateTime(
          today.year,
          today.month,
          today.day - (_weekOffset * 7),
        );
        final selectedDays = progressService.activityForSevenDays(
          notifier.words,
          endDay: selectedEndDay,
          latestAllowedAt: now,
        );
        final selectedMonth = DateTime(
          today.year,
          today.month - _monthOffset,
          1,
        );
        final monthActivities = progressService.activityForMonth(
          notifier.words,
          month: selectedMonth,
          latestAllowedAt: now,
        );
        final syncSupported = notifier.syncSupported;
        final syncEnabled = notifier.syncEnabled;
        final canSync = notifier.canSync;
        final isSyncing = notifier.isSyncing;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
          children: [
            SectionCard(
              title: '你的學習累積',
              subtitle: '看見持續使用留下來的成果',
              trailing: const Icon(
                Icons.insights_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProgressGrid(progress: progress),
                  const SizedBox(height: 18),
                  _ActivityViewModeTabs(
                    mode: _viewMode,
                    onChanged: (nextMode) {
                      setState(() {
                        _viewMode = nextMode;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  if (_viewMode == _ActivityViewMode.week) ...[
                    _ActivityWeekHeader(
                      days: selectedDays,
                      isCurrentWeek: _weekOffset == 0,
                      onPrevious: () {
                        setState(() {
                          _weekOffset++;
                        });
                      },
                      onNext: _weekOffset == 0
                          ? null
                          : () {
                              setState(() {
                                _weekOffset--;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    _ActivityWeek(days: selectedDays),
                  ] else ...[
                    _ActivityMonthHeader(
                      month: selectedMonth,
                      activities: monthActivities,
                      isCurrentMonth: _monthOffset == 0,
                      onPrevious: () {
                        setState(() {
                          _monthOffset++;
                          _selectedCalendarDay = null;
                        });
                      },
                      onNext: _monthOffset == 0
                          ? null
                          : () {
                              setState(() {
                                _monthOffset--;
                                _selectedCalendarDay = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    _ActivityMonthCalendar(
                      month: selectedMonth,
                      activities: monthActivities,
                      today: today,
                      selectedDay: _selectedCalendarDay,
                      onSelectDay: (day) {
                        setState(() {
                          _selectedCalendarDay = day;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    progress.latestActivityAt == null
                        ? '完成第一次複習後，這裡會開始記錄你的累積。'
                        : '最近學習活動：${_formatDateTime(progress.latestActivityAt)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ReviewPerformanceCard(progress: progress),
            if (progress.difficultWords.isNotEmpty) ...[
              const SizedBox(height: 16),
              _DifficultWordsCard(words: progress.difficultWords),
            ],
            const SizedBox(height: 16),
            SectionCard(
              title: '雲端同步紀錄',
              subtitle: syncSupported ? 'iCloud 備份與還原狀態' : '目前版本未啟用 iCloud 同步',
              trailing: Icon(
                canSync ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: const Color(0xFF0B6E99),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    label: '同步功能',
                    value: syncSupported
                        ? (syncEnabled ? '可用（iOS/macOS）' : '已停用（可在設定開啟）')
                        : '此版本未啟用',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(label: '目前狀態', value: isSyncing ? '同步中' : '待命'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '最後同步',
                    value: _formatDateTime(notifier.lastSyncAt),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '最近嘗試',
                    value: _formatDateTime(notifier.lastSyncAttemptAt),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '還原判定',
                    value: _restoreStatusText(notifier.restoreStatus),
                  ),
                  if (notifier.hasSyncError) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: '錯誤代碼',
                      value: notifier.lastSyncErrorCode ?? '-',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notifier.lastSyncErrorMessage ?? '未知錯誤',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (!canSync || isSyncing)
                          ? null
                          : () async {
                              final ok = await notifier.syncNow();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? '同步完成' : '同步失敗，請稍後重試'),
                                ),
                              );
                            },
                      icon: isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(isSyncing ? '同步中...' : '立即同步'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: '本地資料統計',
              subtitle: '裝置內目前資料量',
              trailing: const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF0B6E99),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: '單字總數', value: '${notifier.totalWords}'),
                  const SizedBox(height: 8),
                  _InfoRow(label: '待複習數', value: '${notifier.dueWordsCount}'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _restoreStatusText(RestoreStatus status) {
    switch (status) {
      case RestoreStatus.idle:
        return '待判定';
      case RestoreStatus.restoring:
        return '還原中';
      case RestoreStatus.restored:
        return '重裝還原成功';
      case RestoreStatus.newInstall:
        return '新安裝用戶';
      case RestoreStatus.failed:
        return '還原失敗（可重試）';
    }
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }
}

class _ActivityWeekHeader extends StatelessWidget {
  const _ActivityWeekHeader({
    required this.days,
    required this.isCurrentWeek,
    required this.onPrevious,
    required this.onNext,
  });

  final List<DailyLearningActivity> days;
  final bool isCurrentWeek;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = days.first.day;
    final end = days.last.day;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCurrentWeek ? '最近 7 天' : '先前 7 天',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatDate(start)} ～ ${_formatDate(end)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('previousActivityWeek'),
          onPressed: onPrevious,
          tooltip: '查看前 7 天',
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const ValueKey('nextActivityWeek'),
          onPressed: onNext,
          tooltip: '查看後 7 天',
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }
}

class _ReviewPerformanceCard extends StatelessWidget {
  const _ReviewPerformanceCard({required this.progress});

  final LearningProgressSummary progress;

  @override
  Widget build(BuildContext context) {
    final recallRate = progress.recentRecallRate;
    return SectionCard(
      title: '最近 7 天記憶回饋',
      subtitle: progress.recentRatedReviews == 0
          ? '完成四級記憶回饋後，這裡會開始統計'
          : '共記錄 ${progress.recentRatedReviews} 次有效回饋',
      trailing: CircleAvatar(
        backgroundColor: const Color(0xFF0B6E99).withValues(alpha: 0.1),
        child: Text(
          recallRate == null ? '—' : '$recallRate%',
          style: const TextStyle(
            color: Color(0xFF0B6E99),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recallRate == null ? '尚無可計算的記憶回饋' : '回想穩定率 $recallRate%',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RatingCountChip(
                rating: ReviewRating.forgot,
                count: progress.recentForgotReviews,
              ),
              _RatingCountChip(
                rating: ReviewRating.hard,
                count: progress.recentHardReviews,
              ),
              _RatingCountChip(
                rating: ReviewRating.good,
                count: progress.recentGoodReviews,
              ),
              _RatingCountChip(
                rating: ReviewRating.easy,
                count: progress.recentEasyReviews,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingCountChip extends StatelessWidget {
  const _RatingCountChip({required this.rating, required this.count});

  final ReviewRating rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: const Color(0xFF0B6E99).withValues(alpha: 0.12),
        child: Text('$count', style: Theme.of(context).textTheme.labelSmall),
      ),
      label: Text(rating.label),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF2F7F8),
    );
  }
}

class _DifficultWordsCard extends StatelessWidget {
  const _DifficultWordsCard({required this.words});

  final List<WordCard> words;

  @override
  Widget build(BuildContext context) {
    final visibleWords = words.take(5).toList(growable: false);
    return SectionCard(
      title: '需要加強的單字',
      subtitle: '最近三次回饋中，至少兩次感到困難',
      trailing: Text(
        '${words.length}',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFF0B6E99),
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        children: visibleWords
            .map((word) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(word.word),
                subtitle: Text(word.meaning),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, '/detail', arguments: word.id),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _ProgressGrid extends StatelessWidget {
  const _ProgressGrid({required this.progress});

  final LearningProgressSummary progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _ProgressTile(
              width: width,
              label: '目前連續',
              value: '${progress.currentStreak}',
              unit: '天',
            ),
            _ProgressTile(
              width: width,
              label: '最長連續',
              value: '${progress.longestStreak}',
              unit: '天',
            ),
            _ProgressTile(
              width: width,
              label: '已掌握',
              value: '${progress.masteredWords}',
              unit: '個單字',
            ),
            _ProgressTile(
              width: width,
              label: '累計複習',
              value: '${progress.totalReviews}',
              unit: '次',
            ),
            _ProgressTile(
              width: width,
              label: '本週活躍',
              value: '${progress.activeDaysThisWeek}',
              unit: '天',
            ),
            _ProgressTile(
              width: width,
              label: '近 30 天活躍',
              value: '${progress.activeDaysLast30}',
              unit: '天',
            ),
          ],
        );
      },
    );
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.width,
    required this.label,
    required this.value,
    required this.unit,
  });

  final double width;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B6E99).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF0B6E99),
                fontWeight: FontWeight.w700,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityViewModeTabs extends StatelessWidget {
  const _ActivityViewModeTabs({required this.mode, required this.onChanged});

  final _ActivityViewMode mode;
  final ValueChanged<_ActivityViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE6EEF1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              buttonKey: const ValueKey('activityViewWeekTab'),
              label: '7 天檢視',
              selected: mode == _ActivityViewMode.week,
              onTap: () => onChanged(_ActivityViewMode.week),
            ),
          ),
          Expanded(
            child: _TabButton(
              buttonKey: const ValueKey('activityViewMonthTab'),
              label: '月曆熱力圖',
              selected: mode == _ActivityViewMode.month,
              onTap: () => onChanged(_ActivityViewMode.month),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.buttonKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? const Color(0xFF0B6E99) : Colors.black54,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ActivityWeek extends StatelessWidget {
  const _ActivityWeek({required this.days});

  final List<DailyLearningActivity> days;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final maxCount = days.fold<int>(
      0,
      (current, day) => day.count > current ? day.count : current,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days
          .map((activity) {
            final intensity = maxCount == 0 ? 0.0 : activity.count / maxCount;
            final background = Color.lerp(
              const Color(0xFFE6EEF1),
              const Color(0xFF0B6E99),
              intensity,
            );
            return Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${activity.count}',
                    style: TextStyle(
                      color: intensity > 0.55 ? Colors.white : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _weekdayLabels[activity.day.weekday - 1],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            );
          })
          .toList(growable: false),
    );
  }
}

class _ActivityMonthHeader extends StatelessWidget {
  const _ActivityMonthHeader({
    required this.month,
    required this.activities,
    required this.isCurrentMonth,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final List<DailyLearningActivity> activities;
  final bool isCurrentMonth;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final activeDaysCount = activities.where((item) => item.count > 0).length;
    final totalCount = activities.fold<int>(0, (sum, item) => sum + item.count);
    final monthStr = month.month.toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${month.year} 年 $monthStr 月',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                '本月活躍 $activeDaysCount 天・共 $totalCount 次學習',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('previousActivityMonth'),
          onPressed: onPrevious,
          tooltip: '查看上個月',
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          key: const ValueKey('nextActivityMonth'),
          onPressed: onNext,
          tooltip: '查看下個月',
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ActivityMonthCalendar extends StatelessWidget {
  const _ActivityMonthCalendar({
    required this.month,
    required this.activities,
    required this.today,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final DateTime month;
  final List<DailyLearningActivity> activities;
  final DateTime today;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  static Color _colorForCount(int count, int maxCount) {
    if (count <= 0 || maxCount <= 0) {
      return const Color(0xFFE6EEF1);
    }
    final ratio = count / maxCount;
    if (ratio <= 0.34) {
      return const Color(0xFF9CC8DC);
    }
    if (ratio <= 0.67) {
      return const Color(0xFF4295B8);
    }
    return const Color(0xFF0B6E99);
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leadingEmptyCount = firstWeekday - 1;
    final maxCount = activities.fold<int>(
      0,
      (current, item) => item.count > current ? item.count : current,
    );

    DailyLearningActivity? selectedActivity;
    if (selectedDay != null) {
      for (final item in activities) {
        if (item.day == selectedDay) {
          selectedActivity = item;
          break;
        }
      }
    }

    final totalSlots = leadingEmptyCount + activities.length;
    final rowCount = (totalSlots / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _weekdayLabels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.black54),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 6),
        ...List.generate(rowCount, (rowIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: List.generate(7, (colIndex) {
                final cellIndex = rowIndex * 7 + colIndex;
                final dayIndex = cellIndex - leadingEmptyCount;
                if (dayIndex < 0 || dayIndex >= activities.length) {
                  return const Expanded(child: SizedBox(height: 36));
                }
                final activity = activities[dayIndex];
                final isToday = activity.day == today;
                final isSelected = activity.day == selectedDay;
                final isFuture = activity.day.isAfter(today);
                final bgColor = isFuture
                    ? const Color(0xFFF3F6F8)
                    : _colorForCount(activity.count, maxCount);
                final isDarkBg =
                    !isFuture &&
                    activity.count > 0 &&
                    maxCount > 0 &&
                    (activity.count / maxCount) > 0.34;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      key: ValueKey(
                        'calendarDay-${activity.day.year}-${activity.day.month}-${activity.day.day}',
                      ),
                      onTap: isFuture ? null : () => onSelectDay(activity.day),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(9),
                          border: isSelected
                              ? Border.all(
                                  color: const Color(0xFFD97706),
                                  width: 2,
                                )
                              : isToday
                              ? Border.all(
                                  color: const Color(0xFF0B6E99),
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: Text(
                          '${activity.day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isFuture
                                ? Colors.black26
                                : isDarkBg
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: (isToday || activity.count > 0)
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                selectedActivity == null
                    ? '點選日期可查看當日學習次數'
                    : '${selectedActivity.day.year}/${selectedActivity.day.month.toString().padLeft(2, '0')}/${selectedActivity.day.day.toString().padLeft(2, '0')}：完成 ${selectedActivity.count} 次學習',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ),
            Text(
              '少',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.black45),
            ),
            const SizedBox(width: 4),
            for (final color in const [
              Color(0xFFE6EEF1),
              Color(0xFF9CC8DC),
              Color(0xFF4295B8),
              Color(0xFF0B6E99),
            ])
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              '多',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.black45),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}
