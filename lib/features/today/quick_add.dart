import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

enum QuickAddAction { write, checkin, activity, media, music, place, event }

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
    case QuickAddAction.checkin:
      await showDailyCheckinSheet(context, ref, day);
    case QuickAddAction.activity:
      await pickAndLogHabit(context, ref, day);
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
      (action: QuickAddAction.write, icon: Icons.edit_rounded, label: 'Journal', color: palette.journal),
      (action: QuickAddAction.checkin, icon: Icons.favorite_border_rounded, label: 'Daily check-in', color: palette.tracker),
      (action: QuickAddAction.activity, icon: Icons.bolt_rounded, label: 'Activity', color: palette.tracker),
      (action: QuickAddAction.media, icon: Icons.photo_library_outlined, label: 'Photos', color: palette.photo),
      (action: QuickAddAction.music, icon: Icons.graphic_eq_rounded, label: 'Music', color: palette.music),
      (action: QuickAddAction.place, icon: Icons.place_rounded, label: 'Place', color: palette.place),
      (action: QuickAddAction.event, icon: Icons.push_pin_outlined, label: 'Event', color: palette.manual),
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
                      Text(
                        item.label,
                        textAlign: TextAlign.center,
                        style: context.text.labelLarge,
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
}

/// Chooses an activity (skipping the chooser when there is only one) and opens
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
        const SheetTitle(title: 'Log an activity'),
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

Future<void> showDailyCheckinSheet(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  await showLifelogSheet<void>(
    context,
    builder: (_) => _DailyCheckinSheet(day: day),
  );
}

class _DailyCheckinSheet extends ConsumerStatefulWidget {
  const _DailyCheckinSheet({required this.day});
  final DateTime day;

  @override
  ConsumerState<_DailyCheckinSheet> createState() => _DailyCheckinSheetState();
}

class _DailyCheckinSheetState extends ConsumerState<_DailyCheckinSheet> {
  late final TextEditingController _sleep;
  late final TextEditingController _steps;
  late final TextEditingController _meals;
  late final TextEditingController _highlight;
  Mood? _mood;
  int? _energy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = ref.read(archiveProvider).dailyEntryFor(widget.day);
    _sleep = TextEditingController(
      text: entry?.sleepHours == null ? '' : _fmtNum(entry!.sleepHours!),
    );
    _steps = TextEditingController(text: entry?.steps?.toString() ?? '');
    _meals = TextEditingController(text: entry?.meals ?? '');
    _highlight = TextEditingController(text: entry?.highlight ?? '');
    _mood = entry?.mood;
    _energy = entry?.energy;
  }

  @override
  void dispose() {
    _sleep.dispose();
    _steps.dispose();
    _meals.dispose();
    _highlight.dispose();
    super.dispose();
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
  }

  JournalEntry _baseEntry() {
    final archive = ref.read(archiveProvider);
    final existing = archive.dailyEntryFor(widget.day);
    return existing ??
        JournalEntry(
          id: 'day-${dayKey(widget.day)}',
          createdAt: momentForDay(widget.day),
          updatedAt: DateTime.now(),
          title: '',
          body: '',
          draft: true,
        );
  }

  Future<void> _importSteps() async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      if (mounted) showSnack(context, 'Health steps are available on supported devices with Health access.');
      return;
    }
    final granted = await guard<bool>(
      context,
      services.healthSteps.requestPermission(),
      errorPrefix: 'Could not access Health data',
    );
    if (granted != true || !mounted) return;
    final steps = await guard<int?>(
      context,
      services.healthSteps.getStepsForDay(widget.day),
      errorPrefix: 'Could not read steps',
    );
    if (!mounted) return;
    if (steps == null) {
      showSnack(context, 'No step data available for this day.');
      return;
    }
    setState(() => _steps.text = steps.toString());
    showSnack(context, 'Imported $steps steps from Health.');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final steps = int.tryParse(_steps.text.trim());
    final sleep = double.tryParse(_sleep.text.trim().replaceAll(',', '.'));
    final base = _baseEntry();
    final entry = base.copyWith(
      mood: _mood,
      clearMood: _mood == null,
      energy: _energy,
      clearEnergy: _energy == null,
      sleepHours: sleep,
      clearSleepHours: _sleep.text.trim().isEmpty,
      steps: steps,
      clearSteps: _steps.text.trim().isEmpty,
      meals: _meals.text.trim(),
      highlight: _highlight.text.trim(),
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(archiveProvider.notifier).saveEntry(entry);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save check-in: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: 'Daily check-in',
          subtitle: relativeDayLabel(widget.day),
        ),
        Text('How did it feel?', style: text.labelMedium?.copyWith(color: palette.mutedText)),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final mood in Mood.values)
              ChoiceChip(
                label: Text(mood.label),
                selected: _mood == mood,
                onSelected: (_) => setState(() => _mood = _mood == mood ? null : mood),
              ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Text('Energy', style: text.labelMedium?.copyWith(color: palette.mutedText)),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: _energy == i,
                onSelected: (_) => setState(() => _energy = _energy == i ? null : i),
              ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sleep,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Sleep (hours)',
                  hintText: '7.5',
                  prefixIcon: Icon(Icons.bedtime_outlined, size: 18),
                ),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: TextField(
                controller: _steps,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Steps',
                  hintText: '8000',
                  prefixIcon: const Icon(Icons.directions_walk_rounded, size: 18),
                  suffixIcon: IconButton(
                    tooltip: 'Import from Health',
                    onPressed: _importSteps,
                    icon: const Icon(Icons.favorite_outline_rounded, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _meals,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What I ate',
            hintText: 'Breakfast, lunch, dinner, snacks, drinks...',
            prefixIcon: Icon(Icons.restaurant_outlined, size: 18),
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _highlight,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Highlight or note',
            hintText: 'Best part, plans, or anything to remember',
            prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18),
          ),
        ),
        const SizedBox(height: Insets.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save check-in'),
          ),
        ),
      ],
    );
  }
}

/// Picks photos/videos from the library on mobile, or files on desktop.
Future<List<XFile>> pickMediaFromPhotosOrFiles() async {
  final usePhotos = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  if (usePhotos) {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultipleMedia();
      if (picked.isNotEmpty) return picked;
      // If user cancelled, fall through? no, return empty to respect cancel.
      return picked;
    } catch (_) {
      // fall through to file picker
    }
  }
  return openFiles();
}

/// Picks files, asks for a caption, encrypts and stores them on [day].
Future<void> importMediaForDay(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  String? journalEntryId,
}) async {
  try {
    final files = await pickMediaFromPhotosOrFiles();
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
