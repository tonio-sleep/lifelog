import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/day_provider.dart';
import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/trackers.dart';
import '../journal/journal_widgets.dart';
import '../music/music_dialogs.dart';
import '../photos/photo_widgets.dart';
import '../places/place_dialogs.dart';
import '../timeline/event_dialogs.dart';
import '../trackers/tracker_dialogs.dart';

enum QuickAddAction { write, meal, habit, steps, watch, media, music, place, event }

/// The one place where "add something" starts. Writes to whichever day Today
/// is showing.
Future<void> showQuickAdd(BuildContext context, WidgetRef ref) async {
  final day = ref.read(selectedDayProvider);
  final choice = await showLifelogSheet<QuickAddAction>(
    context,
    builder: (sheetContext) => _QuickAddSheet(day: day),
  );
  if (choice == null || !context.mounted) return;
  await runQuickAdd(context, ref, choice, day);
}

Future<void> runQuickAdd(
  BuildContext context,
  WidgetRef ref,
  QuickAddAction action,
  DateTime day,
) async {
  switch (action) {
    case QuickAddAction.write:
      await createJournalEntry(context, date: day, focusBody: true);
    case QuickAddAction.meal:
      await showTimelineEventEditor(
        context,
        ref,
        initialDate: day,
        dialogTitle: 'Log a meal',
        titleLabel: 'What did you eat?',
        titleHint: 'Breakfast: oats and coffee',
        prefillTitle: '',
      );
    case QuickAddAction.habit:
      await pickAndLogHabit(context, ref, day);
    case QuickAddAction.steps:
      await _logSteps(context, ref, day);
    case QuickAddAction.watch:
      await showTimelineEventEditor(
        context,
        ref,
        initialDate: day,
        dialogTitle: 'Log something you watched',
        titleLabel: 'What did you watch?',
        titleHint: 'Show or movie name',
      );
    case QuickAddAction.media:
      await importMediaForDay(context, ref, day);
    case QuickAddAction.music:
      await showManualScrobbleDialog(context, ref, day: day);
    case QuickAddAction.place:
      await showVisitEditor(context, ref, day: day);
    case QuickAddAction.event:
      await showTimelineEventEditor(context, ref, initialDate: day);
  }
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final items = <({QuickAddAction action, IconData icon, String label, Color color})>[
      (action: QuickAddAction.write, icon: Icons.edit_rounded, label: 'Write', color: palette.journal),
      (action: QuickAddAction.meal, icon: Icons.restaurant_rounded, label: 'Meal', color: palette.tracker),
      (action: QuickAddAction.habit, icon: Icons.task_alt_rounded, label: 'Habit', color: palette.tracker),
      (action: QuickAddAction.steps, icon: Icons.directions_walk_rounded, label: 'Steps', color: palette.place),
      (action: QuickAddAction.watch, icon: Icons.movie_rounded, label: 'Watch', color: palette.music),
      (action: QuickAddAction.media, icon: Icons.photo_camera_back_rounded, label: 'Media', color: palette.photo),
      (action: QuickAddAction.music, icon: Icons.graphic_eq_rounded, label: 'Music', color: palette.music),
      (action: QuickAddAction.place, icon: Icons.place_rounded, label: 'Place', color: palette.place),
      (action: QuickAddAction.event, icon: Icons.bolt_rounded, label: 'Event', color: palette.manual),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: 'Add',
          subtitle: 'To ${relativeDayLabel(day).toLowerCase()}',
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Insets.md,
          crossAxisSpacing: Insets.md,
          childAspectRatio: 1.08,
          children: [
            for (final item in items)
              Pressable(
                haptic: true,
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: () => Navigator.of(context).pop(item.action),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.subtle,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconBadge(icon: item.icon, color: item.color, size: 46, iconSize: 22),
                      const SizedBox(height: Insets.sm),
                      Text(item.label, style: context.text.labelLarge),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Chooses a habit (skipping the chooser when there is only one) and opens
/// its log sheet.
Future<void> pickAndLogHabit(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  final trackers = ref.read(archiveProvider).activeTrackers;
  if (trackers.isEmpty) {
    await showTrackerEditor(context, ref);
    return;
  }
  if (trackers.length == 1) {
    await showTrackerLogDialog(context, ref, trackers.first, day: day);
    return;
  }
  final chosen = await showLifelogSheet<TrackerDefinition>(
    context,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(title: 'Log a habit'),
        for (final tracker in trackers)
          Pressable(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => Navigator.of(sheetContext).pop(tracker),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Row(
                children: [
                  IconBadge(
                    icon: trackerIcon(tracker.icon),
                    color: trackerColor(tracker.colorValue),
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(child: Text(tracker.name, style: sheetContext.text.titleSmall)),
                  Text(
                    tracker.type.label,
                    style: sheetContext.text.labelSmall?.copyWith(
                      color: sheetContext.palette.dimText,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  if (chosen != null && context.mounted) {
    await showTrackerLogDialog(context, ref, chosen, day: day);
  }
}

/// Logs steps for the day. Tries Apple Health/Health Connect when available,
/// and saves to the day's check-in (journal). Also supports manual tracker logging.
Future<void> _logSteps(BuildContext context, WidgetRef ref, DateTime day) async {
  final services = ref.read(appServicesProvider);
  int? imported;
  if (services.healthSteps.isSupported) {
    final connect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Steps'),
        content: const Text(
          'Import today\'s step count from Apple Health / Health Connect, or enter it manually in your daily check-in?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Manual')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import from Health')),
        ],
      ),
    );
    if (connect == true && context.mounted) {
      final granted = await guard<bool>(
        context,
        services.healthSteps.requestPermission(),
        errorPrefix: 'Could not access Health data',
      );
      if (granted == true && context.mounted) {
        imported = await guard<int?>(
          context,
          services.healthSteps.getStepsForDay(day),
          errorPrefix: 'Could not read steps',
        );
      }
    } else if (connect == null) {
      return;
    }
  }

  if (imported != null && context.mounted) {
    // Save into daily journal entry's steps field
    final archive = ref.read(archiveProvider);
    final existing = archive.dailyEntryFor(day);
    final base = existing ??
        JournalEntry(
          id: 'day-${dayKey(day)}',
          createdAt: momentForDay(day),
          updatedAt: DateTime.now(),
          title: '',
          body: '',
          draft: true,
        );
    await ref.read(archiveProvider.notifier).saveEntry(
          base.copyWith(
            steps: imported,
            updatedAt: DateTime.now(),
          ),
        );
    if (context.mounted) {
      showSnack(context, 'Saved $imported steps for ${relativeDayLabel(day).toLowerCase()}.');
    }
    return;
  }

  // Manual path: open daily journal/check-in so user can enter steps and more
  if (!context.mounted) return;
  await createJournalEntry(context, date: day, focusBody: false);
}

/// Picks files, asks for a caption, encrypts and stores them on [day].
Future<void> importMediaForDay(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  String? journalEntryId,
}) async {
  try {
    final files = await openFiles();
    if (files.isEmpty) return;
    var added = 0;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final details = await askMediaDetails(context, fileName: file.name);
      if (details == null) continue;
      if (!context.mounted) return;
      await ref.read(archiveProvider.notifier).importMedia(
        bytes: Uint8List.fromList(bytes),
        fileName: file.name,
        caption: details.caption,
        tags: details.tags,
        journalEntryId: journalEntryId,
        createdAt: momentForDay(day),
      );
      added++;
    }
    if (context.mounted && added > 0) {
      showSnack(context, added == 1 ? 'Added to the day.' : '$added items added.');
    }
  } catch (error) {
    if (context.mounted) showSnack(context, 'Could not import media: $error');
  }
}
