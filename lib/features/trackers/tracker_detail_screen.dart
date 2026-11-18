import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/trackers.dart';
import '../../domain/tracker_stats.dart';
import '../insights/charts.dart';
import 'tracker_dialogs.dart';

class TrackerDetailScreen extends ConsumerWidget {
  const TrackerDetailScreen({super.key, required this.trackerId});

  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final tracker = archive.trackerById(trackerId);
    if (tracker == null) {
      return ScreenFrame(
        title: 'Habit',
        children: const [
          EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Removed',
            message: 'This habit no longer exists.',
          ),
        ],
      );
    }

    final palette = context.palette;
    final text = context.text;
    final today = DateTime.now();
    final accent = trackerColor(tracker.colorValue);
    final records = archive.recordsForTracker(tracker.id);
    final history = HabitHistory(tracker, archive.trackerRecords);
    final todayLabel = TrackerMath.dailyLabel(tracker, archive.trackerRecords, today);
    final series = TrackerMath.dailySeries(tracker, archive.trackerRecords, today, 30);
    final weekTotal = series.skip(23).fold<double>(0, (sum, point) => sum + point.value);
    final monthTotal = series.fold<double>(0, (sum, point) => sum + point.value);
    final labels = [
      formatShortDate(series.first.day),
      formatShortDate(series[series.length ~/ 2].day),
      formatShortDate(series.last.day),
    ];
    final values = series.map((point) => point.value).toList();
    final unit = tracker.unit.trim();
    final streak = history.currentStreak(today);
    final best = history.bestStreak();

    return ScreenFrame(
      title: tracker.name,
      subtitle: [tracker.type.label, if (tracker.target != null) tracker.targetLabel].join(', '),
      actions: [
        HeaderButton(
          icon: Icons.tune_rounded,
          tooltip: 'Edit habit',
          onPressed: () => showTrackerEditor(context, ref, existing: tracker),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (value) async {
            if (value == 'pause') {
              await guard(
                context,
                ref.read(archiveProvider.notifier).saveTracker(
                  tracker.copyWith(active: !tracker.active),
                ),
                errorPrefix: 'Could not update habit',
              );
            } else if (value == 'delete') {
              await _delete(context, ref, tracker, records.length);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pause',
              child: Text(tracker.active ? 'Pause habit' : 'Resume habit'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete habit and records')),
          ],
        ),
      ],
      children: [
        QuietCard(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            children: [
              Row(
                children: [
                  ProgressRing(
                    value: history.progressOn(today),
                    size: 84,
                    stroke: 8,
                    color: accent,
                    child: Icon(trackerIcon(tracker.icon), color: accent, size: 28),
                  ),
                  const SizedBox(width: Insets.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today', style: text.labelMedium?.copyWith(color: palette.mutedText)),
                        Text(todayLabel ?? 'Not logged', style: text.headlineSmall),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => showTrackerLogDialog(context, ref, tracker),
                    child: const Text('Log'),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      compact: true,
                      icon: Icons.local_fire_department_rounded,
                      accent: context.scheme.secondary,
                      value: '$streak',
                      label: 'Current streak',
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: StatTile(
                      compact: true,
                      icon: Icons.emoji_events_outlined,
                      accent: accent,
                      value: '$best',
                      label: 'Best streak',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Last 30 days'),
        QuietCard(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            children: [
              MiniBarChart(
                values: values,
                labels: labels,
                color: accent,
                height: 110,
                highlightIndex: values.length - 1,
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Expanded(
                    child: _Figure(value: _totalLabel(tracker, weekTotal), label: 'Last 7 days'),
                  ),
                  Expanded(
                    child: _Figure(value: _totalLabel(tracker, monthTotal), label: 'Last 30 days'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'History'),
        if (records.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: 'No records yet',
            message: 'Tap Log, or use this habit from Today.',
            compact: true,
          )
        else
          Column(
            children: [
              for (final record in records.take(100))
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: QuietCard(
                    padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.sm, Insets.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                TrackerMath.recordLabel(tracker, record),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${relativeDayLabel(record.recordedAt)}, '
                                '${formatTime(record.recordedAt)}'
                                '${unit.isEmpty ? '' : '  $unit'}',
                                style: text.labelSmall?.copyWith(color: palette.dimText),
                              ),
                              if (record.note.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    record.note,
                                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Record actions',
                          icon: Icon(Icons.more_horiz_rounded, color: palette.dimText),
                          onSelected: (value) async {
                            if (value == 'edit') {
                              await showTrackerLogDialog(context, ref, tracker, editing: record);
                            } else if (value == 'delete') {
                              final ok = await confirm(
                                context,
                                title: 'Delete this record?',
                                message: 'This entry will be removed. The rest of the archive is unaffected.',
                              );
                              if (ok) {
                                if (!context.mounted) return;
                                await guard(
                                  context,
                                  ref.read(archiveProvider.notifier).deleteRecord(record.id),
                                  errorPrefix: 'Could not delete record',
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _totalLabel(TrackerDefinition tracker, double total) {
    switch (tracker.type) {
      case TrackerType.boolean:
        return '${total.round()} days';
      case TrackerType.duration:
        return formatDurationMinutes(total);
      case TrackerType.rating:
        return total == 0 ? '—' : total.toStringAsFixed(1);
      case TrackerType.text:
        return '${total.round()} notes';
      case TrackerType.count:
      case TrackerType.event:
      case TrackerType.number:
        final unit = tracker.unit.trim();
        return unit.isEmpty
            ? formatCompactNumber(total)
            : '${formatCompactNumber(total)} $unit';
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TrackerDefinition tracker,
    int recordCount,
  ) async {
    final ok = await confirm(
      context,
      title: 'Delete “${tracker.name}”?',
      message:
          'This removes the tracker and its $recordCount '
          '${recordCount == 1 ? 'record' : 'records'}. Other data is not '
          'affected. Consider archiving later if you want to keep history.',
    );
    if (!ok) return;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).deleteTracker(tracker.id),
      errorPrefix: 'Could not delete tracker',
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: context.text.titleMedium?.copyWith(fontFeatures: tabularFigures),
        ),
        Text(
          label,
          style: context.text.labelSmall?.copyWith(color: context.palette.dimText),
        ),
      ],
    );
  }
}
