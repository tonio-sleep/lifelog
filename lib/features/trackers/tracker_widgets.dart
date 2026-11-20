import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';
import '../../domain/models/trackers.dart';
import '../../domain/tracker_stats.dart';
import 'tracker_detail_screen.dart';
import 'tracker_dialogs.dart';

const _skipColor = Color(0xFF8E96B3);

String? habitValueLabel(
  TrackerDefinition tracker,
  Iterable<TrackerRecord> records,
  DateTime day,
) {
  final label = TrackerMath.dailyLabel(tracker, records, day);
  if (label == null) return null;
  final target = tracker.target;
  final numeric =
      tracker.type == TrackerType.count || tracker.type == TrackerType.event;
  if (numeric && target != null && target > 0) {
    final total = TrackerMath.totalOn(records, tracker.id, day);
    return '${formatCompactNumber(total)} of ${formatCompactNumber(target)}';
  }
  return label;
}

/// Tap: the fastest correct thing for this kind of habit.
Future<void> habitPrimaryAction(
  BuildContext context,
  WidgetRef ref,
  TrackerDefinition tracker,
  DateTime day,
) async {
  final controller = ref.read(archiveProvider.notifier);
  final records = ref.read(archiveProvider).trackerRecords;
  switch (tracker.type) {
    case TrackerType.boolean:
      final done = HabitHistory(tracker, records).doneOn(day);
      if (done) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.mediumImpact();
      }
      await guard(
        context,
        controller.setBoolean(tracker, day, done ? null : true),
        errorPrefix: 'Could not update habit',
      );
    case TrackerType.count:
    case TrackerType.event:
      HapticFeedback.lightImpact();
      final controller = ref.read(archiveProvider.notifier);
      final archive = ref.read(archiveProvider);
      final existing = archive.trackerRecordsOn(day).where(
        (r) =>
            r.trackerId == tracker.id &&
            (r.startedAt == null && r.endedAt == null && r.note.trim().isEmpty),
      );
      final record = await guard(
        context,
        () async {
          if (existing.isNotEmpty) {
            final base = existing.last;
            final updated = base.copyWith(
              value: (base.value ?? 0) + 1,
              recordedAt: momentForDay(day),
            );
            await controller.updateRecord(updated);
            return updated;
          }
          return controller.logTracker(tracker, value: 1, at: momentForDay(day));
        }(),
        errorPrefix: 'Could not log activity',
      );
      if (record != null && context.mounted) {
        final total = TrackerMath.totalOn(
          ref.read(archiveProvider).trackerRecords,
          tracker.id,
          day,
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('${tracker.name}: ${formatCompactNumber(total)}'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  final latest = ref
                      .read(archiveProvider)
                      .trackerRecordsOn(day)
                      .where((r) => r.id == record.id)
                      .toList();
                  if (latest.isEmpty) return;
                  final current = latest.first;
                  final v = (current.value ?? 1) - 1;
                  if (v <= 0) {
                    await controller.deleteRecord(current.id);
                  } else {
                    await controller.updateRecord(current.copyWith(value: v));
                  }
                },
              ),
            ),
          );
      }
    case TrackerType.number:
    case TrackerType.duration:
    case TrackerType.rating:
    case TrackerType.text:
      await showTrackerLogDialog(context, ref, tracker, day: day);
  }
}

/// Long-press: the less common answer (an explicit "no", or a custom amount).
Future<void> habitSecondaryAction(
  BuildContext context,
  WidgetRef ref,
  TrackerDefinition tracker,
  DateTime day,
) async {
  if (tracker.type == TrackerType.boolean) {
    final skipped = HabitHistory(
      tracker,
      ref.read(archiveProvider).trackerRecords,
    ).skippedOn(day);
    await guard(
      context,
      ref
          .read(archiveProvider.notifier)
          .setBoolean(tracker, day, skipped ? null : false),
      errorPrefix: 'Could not update habit',
    );
    return;
  }
  await showTrackerLogDialog(context, ref, tracker, day: day);
}

/// A round control for one habit: ring = progress, centre = state.
class HabitOrb extends ConsumerWidget {
  const HabitOrb({
    super.key,
    required this.tracker,
    required this.day,
    this.size = 56,
    this.showLabel = true,
  });

  final TrackerDefinition tracker;
  final DateTime day;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final history = HabitHistory(tracker, archive.trackerRecords);
    final accent = trackerColor(tracker.colorValue);
    final done = history.doneOn(day);
    final skipped = history.skippedOn(day);
    final progress = history.progressOn(day);
    final palette = context.palette;
    final inner = size - 14;

    final orb = ProgressRing(
      value: skipped ? 0 : progress,
      size: size,
      stroke: size > 50 ? 4.5 : 4,
      color: accent,
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.out,
        width: inner,
        height: inner,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? accent
              : skipped
              ? _skipColor.withValues(alpha: 0.2)
              : accent.withValues(alpha: 0.12),
        ),
        child: AnimatedSwitcher(
          duration: Motion.fast,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            done
                ? Icons.check_rounded
                : skipped
                ? Icons.remove_rounded
                : trackerIcon(tracker.icon),
            key: ValueKey<int>(done ? 1 : (skipped ? 2 : 0)),
            size: inner * 0.5,
            color: done
                ? Colors.white
                : skipped
                ? _skipColor
                : accent,
          ),
        ),
      ),
    );

    final control = Pressable(
      scale: 0.9,
      borderRadius: BorderRadius.circular(size),
      onTap: () => habitPrimaryAction(context, ref, tracker, day),
      onLongPress: () => habitSecondaryAction(context, ref, tracker, day),
      child: orb,
    );
    if (!showLabel) {
      return Tooltip(message: tracker.name, child: control);
    }
    final value = habitValueLabel(tracker, archive.trackerRecords, day);
    return SizedBox(
      width: size + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          control,
          const SizedBox(height: 6),
          Text(
            tracker.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            value ?? ' ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(color: palette.dimText),
          ),
        ],
      ),
    );
  }
}

/// A habit as one line on the Habits screen: orb, name, real log count, last 7 days.
class HabitRow extends ConsumerWidget {
  const HabitRow({super.key, required this.tracker, required this.day});

  final TrackerDefinition tracker;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final history = HabitHistory(tracker, archive.trackerRecords);
    final accent = trackerColor(tracker.colorValue);
    final palette = context.palette;
    final value = habitValueLabel(tracker, archive.trackerRecords, day);
    final week = history.lastDays(day, 7);
    final now = DateTime.now();
    var loggedInLast30 = 0;
    for (var i = 0; i < 30; i++) {
      final dayInWindow = DateTime(now.year, now.month, now.day - i);
      if (history.loggedOn(dayInWindow)) loggedInLast30++;
    }

    return QuietCard(
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.lg, Insets.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrackerDetailScreen(trackerId: tracker.id),
        ),
      ),
      child: Row(
        children: [
          HabitOrb(tracker: tracker, day: day, size: 50, showLabel: false),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  value == null
                      ? 'Logged on $loggedInLast30 of the last 30 days'
                      : '$value · logged on $loggedInLast30 of the last 30 days',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(
                    color: value == null ? palette.dimText : palette.mutedText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < week.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: AnimatedContainer(
                    duration: Motion.base,
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: week[i] ? accent : accent.withValues(alpha: 0.18),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The compact activity strip shown on Today: one row of orbs, no descriptions.
class TodayHabits extends ConsumerWidget {
  const TodayHabits({super.key, required this.day, this.onSeeAll});

  final DateTime day;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final trackers = archive.activeTrackers;
    final palette = context.palette;

    if (trackers.isEmpty) {
      return QuietCard(
        onTap: () => showTrackerEditor(context, ref),
        child: Row(
          children: [
            IconBadge(
              icon: Icons.add_task_rounded,
              color: palette.tracker,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text('Add an activity', style: context.text.titleSmall),
            ),
            Icon(Icons.add_rounded, color: palette.dimText),
          ],
        ),
      );
    }

    final done = trackers
        .where((t) => HabitHistory(t, archive.trackerRecords).loggedOn(day))
        .length;
    final shown = trackers.take(12).toList();
    return QuietCard(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.sm, Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Activities', style: context.text.titleMedium),
              const SizedBox(width: Insets.sm),
              Text(
                done == 0 ? 'Optional' : '$done logged',
                style: context.text.labelMedium?.copyWith(
                  color: palette.mutedText,
                  fontFeatures: tabularFigures,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: Insets.xs),
              itemBuilder: (context, index) =>
                  HabitOrb(tracker: shown[index], day: day),
            ),
          ),
        ],
      ),
    );
  }
}
