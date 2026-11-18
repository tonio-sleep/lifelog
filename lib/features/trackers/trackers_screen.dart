import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/trackers.dart';
import '../../domain/tracker_stats.dart';
import 'tracker_dialogs.dart';
import 'tracker_detail_screen.dart';
import 'tracker_widgets.dart';

class TrackersScreen extends ConsumerStatefulWidget {
  const TrackersScreen({super.key});

  @override
  ConsumerState<TrackersScreen> createState() => _TrackersScreenState();
}

class _TrackersScreenState extends ConsumerState<TrackersScreen> {
  late DateTime _day;
  bool _showPaused = false;

  @override
  void initState() {
    super.initState();
    _day = dayStart(DateTime.now());
  }

  void _shift(int delta) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final trackers = archive.activeTrackers;
    final paused = archive.trackers.where((t) => !t.active).toList();

    return ScreenFrame(
      title: 'Habits',
      actions: [
        HeaderButton(
          icon: Icons.auto_awesome_outlined,
          tooltip: 'Starter habits',
          onPressed: () => _showTemplates(context),
        ),
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'New habit',
          filled: true,
          onPressed: () => showTrackerEditor(context, ref),
        ),
      ],
      children: [
        DayNavigator(
          day: _day,
          onChanged: (value) => setState(() => _day = value),
        ),
        const SizedBox(height: Insets.lg),
        if (trackers.isEmpty)
          EmptyState(
            icon: Icons.task_alt_rounded,
            color: palette.tracker,
            title: 'No habits yet',
            message: 'Pick a few starters or create your own. Nothing is '
                'recorded unless you tap it.',
            actionLabel: 'Choose starters',
            onAction: () => _showTemplates(context),
          )
        else
          DaySwitcher(
            day: _day,
            onSwipe: _shift,
            builder: (context, day) => _HabitList(day: day),
          ),
        if (trackers.isEmpty)
          Center(
            child: TextButton(
              onPressed: () => showTrackerEditor(context, ref),
              child: const Text('Create your own'),
            ),
          ),
        if (paused.isNotEmpty) ...[
          const SizedBox(height: Insets.lg),
          Pressable(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => setState(() => _showPaused = !_showPaused),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm, horizontal: Insets.xs),
              child: Row(
                children: [
                  Text(
                    'Paused (${paused.length})',
                    style: context.text.labelLarge?.copyWith(color: palette.mutedText),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _showPaused ? 0.5 : 0,
                    duration: Motion.base,
                    child: Icon(Icons.expand_more_rounded, color: palette.mutedText),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.out,
            alignment: Alignment.topCenter,
            child: !_showPaused
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final tracker in paused)
                        QuietCard(
                          margin: const EdgeInsets.only(bottom: Insets.sm),
                          padding: const EdgeInsets.all(Insets.md),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TrackerDetailScreen(trackerId: tracker.id),
                            ),
                          ),
                          child: Row(
                            children: [
                              IconBadge(
                                icon: trackerIcon(tracker.icon),
                                color: trackerColor(tracker.colorValue),
                                size: 34,
                                iconSize: 17,
                              ),
                              const SizedBox(width: Insets.md),
                              Expanded(
                                child: Text(tracker.name, style: context.text.bodyMedium),
                              ),
                              Text(
                                '${archive.recordsForTracker(tracker.id).length} records',
                                style: context.text.labelSmall?.copyWith(
                                  color: palette.mutedText,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Future<void> _showTemplates(BuildContext context) async {
    final chosen = await showLifelogSheet<List<TrackerDefinition>>(
      context,
      builder: (_) => const _TemplateSheet(),
    );
    if (chosen == null || chosen.isEmpty) return;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).addTrackers(chosen),
      errorPrefix: 'Could not add habits',
    );
    if (context.mounted) {
      showSnack(
        context,
        '${chosen.length} ${plural(chosen.length, 'habit')} added.',
      );
    }
  }
}

/// Summary ring plus habits, grouped only when there is more than one group.
class _HabitList extends ConsumerWidget {
  const _HabitList({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final trackers = archive.activeTrackers;
    final palette = context.palette;
    final text = context.text;
    if (trackers.isEmpty) return const SizedBox.shrink();

    final histories = {
      for (final t in trackers) t.id: HabitHistory(t, archive.trackerRecords),
    };
    final done = trackers.where((t) => histories[t.id]!.doneOn(day)).length;
    final progress = done / trackers.length;
    final left = trackers.length - done;

    TrackerDefinition? streakLeader;
    var streakBest = 1;
    for (final t in trackers) {
      final s = histories[t.id]!.currentStreak(DateTime.now());
      if (s > streakBest) {
        streakBest = s;
        streakLeader = t;
      }
    }

    final byCategory = <String, List<TrackerDefinition>>{};
    for (final tracker in trackers) {
      byCategory.putIfAbsent(tracker.category, () => []).add(tracker);
    }
    final categories = byCategory.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuietCard(
          padding: const EdgeInsets.all(Insets.lg),
          child: Row(
            children: [
              ProgressRing(
                value: progress,
                size: 76,
                stroke: 8,
                color: palette.tracker,
                child: Text(
                  '$done/${trackers.length}',
                  style: text.titleMedium?.copyWith(fontFeatures: tabularFigures),
                ),
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      left == 0 ? 'All done' : '$left left',
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    if (streakLeader != null)
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 15,
                            color: context.scheme.secondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${streakLeader.name}, $streakBest days',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: palette.mutedText,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Tap a habit to log it. Hold for more.',
                        style: text.bodySmall?.copyWith(color: palette.mutedText),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final category in categories) ...[
          if (categories.length > 1)
            Padding(
              padding: const EdgeInsets.only(
                top: Insets.lg,
                bottom: Insets.sm,
                left: Insets.xs,
              ),
              child: Text(
                category,
                style: text.labelLarge?.copyWith(color: palette.mutedText),
              ),
            )
          else
            const SizedBox(height: Insets.md),
          for (final tracker in byCategory[category]!)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: HabitRow(tracker: tracker, day: day),
            ),
        ],
      ],
    );
  }
}

class _TemplateSheet extends StatefulWidget {
  const _TemplateSheet();

  @override
  State<_TemplateSheet> createState() => _TemplateSheetState();
}

class _TemplateSheetState extends State<_TemplateSheet> {
  final _selected = <String>{'shower', 'water', 'reading'};

  static const _templates =
      <({String key, String label, String note, IconData icon})>[
        (key: 'shower', label: 'Shower', note: 'Yes / no', icon: Icons.shower_outlined),
        (key: 'water', label: 'Water', note: 'Glasses, goal 8', icon: Icons.water_drop_outlined),
        (key: 'mood', label: 'Mood', note: 'Rating', icon: Icons.sentiment_satisfied_alt_outlined),
        (key: 'reading', label: 'Reading', note: 'Minutes', icon: Icons.menu_book_outlined),
        (key: 'walk', label: 'Walk', note: 'Minutes', icon: Icons.directions_walk_rounded),
        (key: 'restroom', label: 'Restroom', note: 'Count', icon: Icons.wc_rounded),
        (key: 'coffee', label: 'Coffee', note: 'Count', icon: Icons.coffee_outlined),
      ];

  List<TrackerDefinition> _build() {
    final out = <TrackerDefinition>[];
    if (_selected.contains('shower')) out.add(TrackerTemplates.shower());
    if (_selected.contains('water')) out.add(TrackerTemplates.water());
    if (_selected.contains('mood')) out.add(TrackerTemplates.mood());
    if (_selected.contains('reading')) out.add(TrackerTemplates.reading());
    if (_selected.contains('walk')) out.add(TrackerTemplates.walk());
    if (_selected.contains('restroom')) out.add(TrackerTemplates.restroom());
    if (_selected.contains('coffee')) out.add(TrackerTemplates.coffee());
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(title: 'Starter habits'),
        for (final template in _templates)
          Pressable(
            haptic: true,
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => setState(() {
              if (!_selected.add(template.key)) _selected.remove(template.key);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Row(
                children: [
                  IconBadge(icon: template.icon, color: palette.tracker, size: 40, iconSize: 20),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(template.label, style: context.text.titleSmall),
                        Text(
                          template.note,
                          style: context.text.labelSmall?.copyWith(color: palette.dimText),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _selected.contains(template.key)
                          ? context.scheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: _selected.contains(template.key)
                            ? context.scheme.primary
                            : palette.border,
                        width: 1.5,
                      ),
                    ),
                    child: _selected.contains(template.key)
                        ? Icon(Icons.check_rounded, size: 16, color: context.scheme.onPrimary)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Insets.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_build()),
            child: Text('Add ${_selected.length}'),
          ),
        ),
      ],
    );
  }
}
