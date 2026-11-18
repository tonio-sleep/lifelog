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

enum QuickAddAction { write, vocab, checkin, activity, media, music, place, event }

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
      await createJournalEntry(
        context,
        date: day,
        focusBody: true,
        createNew: true,
      );
    case QuickAddAction.vocab:
      await createJournalEntry(
        context,
        date: day,
        focusBody: true,
        createNew: true,
        kind: JournalEntryKind.vocab,
      );
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
      (action: QuickAddAction.write, icon: Icons.edit_note_rounded, label: 'Journal', color: palette.journal),
      (action: QuickAddAction.vocab, icon: Icons.translate_rounded, label: 'Vocab list', color: palette.tracker),
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
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Insets.md,
          crossAxisSpacing: Insets.md,
          childAspectRatio: 0.95,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _healthAutoLoaded) return;
      _healthAutoLoaded = true;
      final services = ref.read(appServicesProvider);
      if (services.healthSteps.isSupported) {
        _importFromHealth();
      }
    });
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

  bool _loadingHealth = false;
  bool _healthAutoLoaded = false;
  bool _healthEditable = false;
  String? _healthMessage;
  bool _stepsFromHealth = false;
  bool _sleepFromHealth = false;

  Future<void> _importFromHealth({bool interactive = false}) async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      if (interactive && mounted) {
        showSnack(context, 'Health data is available on supported devices with Health access enabled.');
      }
      return;
    }
    setState(() {
      _loadingHealth = true;
      _healthMessage = null;
    });
    try {
      final granted = await services.healthSteps.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _healthMessage = interactive
              ? 'Health access was not granted.'
              : 'Allow Health access to auto-fill sleep and steps.';
        });
        if (interactive) showSnack(context, 'Health access was not granted.');
        return;
      }
      final summary = await services.healthSteps.getDailySummary(widget.day);
      if (!mounted) return;
      var updated = false;
      setState(() {
        if (summary.steps != null) {
          _steps.text = summary.steps.toString();
          _stepsFromHealth = true;
          updated = true;
        }
        if (summary.sleepHours != null) {
          _sleep.text = _fmtNum(summary.sleepHours!);
          _sleepFromHealth = true;
          updated = true;
        }
        _healthMessage = updated
            ? 'Sleep and steps synced from Health.'
            : 'No Health sleep or step data found for this day.';
      });
      if (interactive) {
        showSnack(
          context,
          updated
              ? 'Synced sleep and steps from Health.'
              : 'No Health sleep or step data found for this day.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _healthMessage = 'Could not read Health data.');
      if (interactive) showSnack(context, 'Could not read Health data: $error');
    } finally {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  List<String> _mealLines() {
    return _meals.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _addMeal() async {
    final controller = TextEditingController();
    final added = await showLifelogSheet<String>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Add food or drink',
            subtitle: 'Log it as you go through the day',
          ),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Breakfast: oats and coffee',
              labelText: 'Meal or item',
            ),
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    final text = added?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    final now = TimeOfDay.fromDateTime(DateTime.now());
    final timeLabel =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final line = '$timeLabel  $text';
    final lines = _mealLines()..add(line);
    setState(() => _meals.text = lines.join('\n'));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Refresh from Health if supported so saved values stay current.
    if (ref.read(appServicesProvider).healthSteps.isSupported) {
      try {
        final summary =
            await ref.read(appServicesProvider).healthSteps.getDailySummary(widget.day);
        if (summary.steps != null) _steps.text = summary.steps.toString();
        if (summary.sleepHours != null) _sleep.text = _fmtNum(summary.sleepHours!);
      } catch (_) {}
    }
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
              child: Text(
                'Sleep & steps',
                style: text.labelMedium?.copyWith(color: palette.mutedText),
              ),
            ),
            if (_loadingHealth)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: () => _importFromHealth(interactive: true),
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Sync from Health'),
              ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        QuietCard(
          padding: const EdgeInsets.all(Insets.md),
          color: palette.subtle.withValues(alpha: 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.bedtime_outlined,
                      label: 'Sleep',
                      value: _sleep.text.trim().isEmpty
                          ? 'Not available'
                          : '${_sleep.text.trim()} hr',
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.directions_walk_rounded,
                      label: 'Steps',
                      value: _steps.text.trim().isEmpty
                          ? 'Not available'
                          : _steps.text.trim(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xs),
              Text(
                _healthMessage ??
                    (ref.read(appServicesProvider).healthSteps.isSupported
                        ? 'Sleep and steps are automatically synced from Health when available.'
                        : 'Automatic Health sync is available on supported devices.'),
                style: text.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'What I ate',
                style: text.labelMedium?.copyWith(color: palette.mutedText),
              ),
            ),
            TextButton.icon(
              onPressed: _addMeal,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        if (_meals.text.trim().isEmpty)
          QuietCard(
            padding: const EdgeInsets.all(Insets.md),
            color: palette.subtle.withValues(alpha: 0.6),
            child: Text(
              'No meals added yet. Add items as you go through the day.',
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
          )
        else
          QuietCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _mealLines()) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.restaurant_outlined,
                            size: 16, color: palette.mutedText),
                        const SizedBox(width: Insets.sm),
                        Expanded(child: Text(line, style: text.bodyMedium)),
                      ],
                    ),
                  ),
                ],
              ],
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

enum _MediaPickSource { cameraPhoto, cameraVideo, library, files }

/// Picks photos/videos by taking a new capture or choosing existing media/files.
/// On mobile this offers camera and library options; on desktop it opens the
/// file picker.
Future<List<XFile>> pickMediaFromPhotosOrFiles(BuildContext context) async {
  final canUseCamera = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  final canUseLibrary = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  if (!canUseCamera && !canUseLibrary) {
    return openFiles();
  }

  final choice = await showLifelogSheet<_MediaPickSource>(
    context,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      final items = <({IconData icon, String label, String hint, _MediaPickSource value, Color color})>[
        if (canUseCamera)
          (
            icon: Icons.photo_camera_outlined,
            label: 'Take photo',
            hint: 'Use the camera to capture a photo',
            value: _MediaPickSource.cameraPhoto,
            color: palette.photo,
          ),
        if (canUseCamera)
          (
            icon: Icons.videocam_outlined,
            label: 'Record video',
            hint: 'Use the camera to record a video',
            value: _MediaPickSource.cameraVideo,
            color: palette.music,
          ),
        if (canUseLibrary)
          (
            icon: Icons.photo_library_outlined,
            label: 'Choose from library',
            hint: 'Select existing photos or videos',
            value: _MediaPickSource.library,
            color: palette.journal,
          ),
        (
          icon: Icons.folder_open_outlined,
          label: 'Choose files',
          hint: 'Pick image or video files',
          value: _MediaPickSource.files,
          color: palette.place,
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Add media',
            subtitle: 'Take a photo/video or choose existing media',
          ),
          for (final item in items)
            Pressable(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () => Navigator.of(sheetContext).pop(item.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                child: Row(
                  children: [
                    IconBadge(
                      icon: item.icon,
                      color: item.color,
                      size: 40,
                      iconSize: 20,
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label,
                              style: sheetContext.text.titleSmall),
                          Text(
                            item.hint,
                            style: sheetContext.text.bodySmall?.copyWith(
                              color: sheetContext.palette.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: sheetContext.palette.dimText),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  if (choice == null) return const [];

  final picker = ImagePicker();
  try {
    switch (choice) {
      case _MediaPickSource.cameraPhoto:
        final file = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 95,
        );
        return file == null ? const [] : [file];
      case _MediaPickSource.cameraVideo:
        final file = await picker.pickVideo(source: ImageSource.camera);
        return file == null ? const [] : [file];
      case _MediaPickSource.library:
        return picker.pickMultipleMedia();
      case _MediaPickSource.files:
        return openFiles();
    }
  } catch (_) {
    if (choice == _MediaPickSource.library ||
        choice == _MediaPickSource.cameraPhoto ||
        choice == _MediaPickSource.cameraVideo) {
      return openFiles();
    }
    rethrow;
  }
}

/// Picks files, asks for a caption, encrypts and stores them on [day].
Future<void> importMediaForDay(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  String? journalEntryId,
}) async {
  try {
    final files = await pickMediaFromPhotosOrFiles(context);
    if (files.isEmpty || !context.mounted) return;
    await _importFilesWithProgress(
      context,
      ref,
      day,
      files,
      journalEntryId: journalEntryId,
    );
  } catch (error) {
    if (context.mounted) showSnack(context, 'Could not import media: $error');
  }
}

Future<void> _importFilesWithProgress(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
  List<XFile> files, {
  String? journalEntryId,
}) async {
  final progress = ValueNotifier<_ImportProgress>(
    _ImportProgress(total: files.length, current: 0, label: 'Preparing...'),
  );
  var dialogOpen = true;
  // Show a non-dismissible progress dialog while importing.
  // ignore: unawaited_futures
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<_ImportProgress>(
          valueListenable: progress,
          builder: (context, p, _) {
            final fraction = p.total <= 0 ? null : (p.current / p.total).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adding media',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Insets.md),
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: Insets.md),
                Text(
                  '${p.current} of ${p.total}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                ),
                if (p.label.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  ).whenComplete(() => dialogOpen = false);

  var added = 0;
  try {
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      progress.value = _ImportProgress(
        total: files.length,
        current: i,
        label: 'Reading ${file.name}',
      );
      final bytes = await file.readAsBytes();
      if (!context.mounted) break;

      progress.value = _ImportProgress(
        total: files.length,
        current: i,
        label: 'Details for ${file.name}',
      );
      final details = await askMediaDetails(context, fileName: file.name);
      if (details == null) {
        progress.value = _ImportProgress(
          total: files.length,
          current: i + 1,
          label: 'Skipped ${file.name}',
        );
        continue;
      }
      if (!context.mounted) break;

      progress.value = _ImportProgress(
        total: files.length,
        current: i,
        label: 'Saving ${file.name}',
      );
      await ref.read(archiveProvider.notifier).importMedia(
            bytes: Uint8List.fromList(bytes),
            fileName: file.name,
            caption: details.caption,
            tags: details.tags,
            journalEntryId: journalEntryId,
            createdAt: momentForDay(day),
          );
      added++;
      progress.value = _ImportProgress(
        total: files.length,
        current: i + 1,
        label: 'Added ${file.name}',
      );
    }
  } finally {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
  }

  if (context.mounted && added > 0) {
    showSnack(context, added == 1 ? 'Added to the day.' : '$added items added.');
  }
}

class _ImportProgress {
  const _ImportProgress({
    required this.total,
    required this.current,
    required this.label,
  });
  final int total;
  final int current;
  final String label;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: palette.mutedText),
            const SizedBox(width: 6),
            Text(label, style: text.labelSmall?.copyWith(color: palette.mutedText)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: text.titleSmall?.copyWith(fontFeatures: tabularFigures),
        ),
      ],
    );
  }
}
