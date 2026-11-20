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
      title: 'Activities',
      actions: [
        HeaderButton(
          icon: Icons.auto_awesome_outlined,
          tooltip: 'Starter activities',
          onPressed: () => _showTemplates(context),
        ),
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'New activity',
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
            title: 'Build your daily habits',
            message: 'Track what matters to you each day — what you ate, brushing your teeth, showering, water, movement, and more. Start with built-in habits or create your own, and log them in a way that fits your life.',
            actionLabel: 'Add daily essentials',
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
      errorPrefix: 'Could not add activities',
    );
    if (context.mounted) {
      showSnack(
        context,
        '${chosen.length} ${plural(chosen.length, 'activity', 'activities')} added.',
      );
    }
  }
}

/// Summary plus activities for the day, grouped only when there is more than one group.
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
    final done = trackers.where((t) => histories[t.id]!.loggedOn(day)).length;

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
                value: trackers.isEmpty ? 0 : done / trackers.length,
                size: 76,
                stroke: 8,
                color: palette.tracker,
                child: Text(
                  '$done',
                  style: text.titleMedium?.copyWith(fontFeatures: tabularFigures),
                ),
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done == 0 ? 'What did you do today?' : '$done logged today',
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
                        'Tap to log quickly. Hold for details like time or duration.',
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
  // Meals are a first-class record now, so no longer seeded as a habit.
  final _selected = <String>{'brushTeeth', 'shower', 'water'};

  static const _templates = <({
    String key,
    String label,
    String note,
    String group,
    IconData icon,
  })>[
    (
      key: 'brushTeeth',
      label: 'Brushed my teeth',
      note: 'Goal: 2 times (morning and night)',
      group: 'Daily essentials',
      icon: Icons.cleaning_services_outlined,
    ),
    (
      key: 'shower',
      label: 'Took a shower',
      note: 'Yes / no',
      group: 'Daily essentials',
      icon: Icons.shower_outlined,
    ),
    (
      key: 'water',
      label: 'Water',
      note: 'Glasses, goal 8',
      group: 'Daily essentials',
      icon: Icons.water_drop_outlined,
    ),
    (
      key: 'skincare',
      label: 'Skincare',
      note: 'Yes / no',
      group: 'Personal care',
      icon: Icons.spa_outlined,
    ),
    (
      key: 'vitamins',
      label: 'Vitamins / supplements',
      note: 'Yes / no',
      group: 'Health',
      icon: Icons.medication_outlined,
    ),
    (
      key: 'exercise',
      label: 'Exercise',
      note: 'Minutes or sessions',
      group: 'Health',
      icon: Icons.fitness_center_rounded,
    ),
    (
      key: 'walk',
      label: 'Walk',
      note: 'Minutes',
      group: 'Health',
      icon: Icons.directions_walk_rounded,
    ),
    (
      key: 'meditation',
      label: 'Meditation',
      note: 'Minutes',
      group: 'Wellbeing',
      icon: Icons.self_improvement_rounded,
    ),
    (
      key: 'mood',
      label: 'Mood reflection',
      note: '1-5 rating',
      group: 'Wellbeing',
      icon: Icons.sentiment_satisfied_alt_outlined,
    ),
    (
      key: 'reading',
      label: 'Reading',
      note: 'Minutes',
      group: 'Growth',
      icon: Icons.menu_book_outlined,
    ),
    (
      key: 'coffee',
      label: 'Coffee',
      note: 'Count',
      group: 'Daily life',
      icon: Icons.coffee_outlined,
    ),
    (
      key: 'restroom',
      label: 'Restroom',
      note: 'Count',
      group: 'Health',
      icon: Icons.wc_rounded,
    ),
  ];

  List<TrackerDefinition> _build() {
    final out = <TrackerDefinition>[];
    for (final key in _selected) {
      switch (key) {
        case 'meals':
          out.add(TrackerTemplates.meals());
        case 'brushTeeth':
          out.add(TrackerTemplates.brushTeeth());
        case 'shower':
          out.add(TrackerTemplates.shower());
        case 'water':
          out.add(TrackerTemplates.water());
        case 'skincare':
          out.add(TrackerTemplates.skincare());
        case 'vitamins':
          out.add(TrackerTemplates.vitamins());
        case 'exercise':
          out.add(TrackerTemplates.exercise());
        case 'walk':
          out.add(TrackerTemplates.walk());
        case 'meditation':
          out.add(TrackerTemplates.meditation());
        case 'mood':
          out.add(TrackerTemplates.mood());
        case 'reading':
          out.add(TrackerTemplates.reading());
        case 'coffee':
          out.add(TrackerTemplates.coffee());
        case 'restroom':
          out.add(TrackerTemplates.restroom());
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final groups = <String,
        List<
            ({
              String key,
              String label,
              String note,
              String group,
              IconData icon,
            })>>{};
    for (final t in _templates) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(
          title: 'Daily habits and activities',
          subtitle:
              'Choose built-in habits to track. You can customize or create your own anytime.',
        ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Insets.md, bottom: Insets.xs),
            child: Text(
              entry.key,
              style:
                  context.text.labelLarge?.copyWith(color: palette.mutedText),
            ),
          ),
          for (final template in entry.value)
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
                    IconBadge(
                      icon: template.icon,
                      color: palette.tracker,
                      size: 40,
                      iconSize: 20,
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(template.label,
                              style: context.text.titleSmall),
                          Text(
                            template.note,
                            style: context.text.labelSmall
                                ?.copyWith(color: palette.dimText),
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
                          ? Icon(Icons.check_rounded,
                              size: 16, color: context.scheme.onPrimary)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: Insets.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_build()),
            child: Text(
              'Add ${_selected.length} ${_selected.length == 1 ? 'habit' : 'habits'}',
            ),
          ),
        ),
      ],
    );
  }
}
