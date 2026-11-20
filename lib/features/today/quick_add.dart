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
import '../meals/meal_dialogs.dart';
import '../music/music_dialogs.dart';
import '../photos/photo_widgets.dart';
import '../places/place_dialogs.dart';
import '../timeline/event_dialogs.dart';
import '../trackers/tracker_dialogs.dart';

enum QuickAddAction {
  write,
  vocab,
  checkin,
  meal,
  activity,
  media,
  music,
  place,
  event,
}

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
    case QuickAddAction.meal:
      await showMealEditor(context, ref, day);
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
      (action: QuickAddAction.checkin, icon: Icons.favorite_border_rounded, label: 'Check-in', color: palette.tracker),
      (action: QuickAddAction.meal, icon: Icons.restaurant_outlined, label: 'Meal / drink', color: palette.warning),
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
  DateTime day, {
  JournalEntry? existing,
}) async {
  await showLifelogSheet<void>(
    context,
    builder: (_) => _DailyCheckinSheet(day: day, existing: existing),
  );
}

class _DailyCheckinSheet extends ConsumerStatefulWidget {
  const _DailyCheckinSheet({required this.day, this.existing});
  final DateTime day;
  final JournalEntry? existing;

  @override
  ConsumerState<_DailyCheckinSheet> createState() => _DailyCheckinSheetState();
}

class _DailyCheckinSheetState extends ConsumerState<_DailyCheckinSheet> {
  late final TextEditingController _highlight;
  int? _mood;
  int? _energy;
  bool _saving = false;

  static const _prompts = <String>[
    'What is one small thing going well right now?',
    'How are you feeling in this moment?',
    'What is on your mind today?',
    'What are you grateful for right now?',
    'What would make the rest of today feel a little better?',
    'What is something you handled well today?',
    'What do you need more of today: rest, connection, or focus?',
    'Write one sentence about your day so far.',
  ];

  static const _energyLabels = <int, String>{
    1: 'Very low',
    2: 'Low',
    3: 'Okay',
    4: 'Good',
    5: 'High',
  };

  String get _prompt =>
      _prompts[(widget.day.day + (widget.existing?.createdAt.minute ?? DateTime.now().minute)) % _prompts.length];

  @override
  void initState() {
    super.initState();
    final entry = widget.existing;
    _highlight = TextEditingController(text: entry?.highlight ?? '');
    _mood = entry?.mood;
    _energy = entry?.energy;
  }

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  JournalEntry _baseEntry() {
    final existing = widget.existing;
    if (existing != null) return existing;
    final now = DateTime.now();
    final createdAt = sameDay(widget.day, now)
        ? now
        : DateTime(widget.day.year, widget.day.month, widget.day.day, 12);
    return JournalEntry(
      id: 'checkin-${now.microsecondsSinceEpoch}',
      createdAt: createdAt,
      updatedAt: now,
      title: '',
      body: '',
      draft: false,
    );
  }

  bool get isEditing => widget.existing != null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final base = _baseEntry();
    final entry = base.copyWith(
      mood: _mood,
      clearMood: _mood == null,
      energy: _energy,
      clearEnergy: _energy == null,
      highlight: _highlight.text.trim(),
      // Sleep/steps are tracked separately; legacy meal text is preserved.
      clearSleepHours: true,
      sleepHours: null,
      clearSteps: true,
      steps: null,
      updatedAt: DateTime.now(),
      draft: false,
    );
    try {
      await ref.read(archiveProvider.notifier).saveEntry(entry);
      if (mounted) {
        final message = isEditing
            ? 'Check-in updated.'
            : 'Check-in saved. Thanks for taking a moment for yourself.';
        showSnack(context, message);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save check-in: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirm(
      context,
      title: 'Delete this check-in?',
      message: 'This check-in will be removed from this day.',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(archiveProvider.notifier).deleteEntry(existing.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete check-in: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final base = _baseEntry();
    final hasContent =
        _mood != null || _energy != null || _highlight.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: isEditing ? 'Edit check-in' : 'How are you doing?',
          subtitle:
              '${relativeDayLabel(widget.day)} · ${formatTime(base.createdAt)}',
        ),
        QuietCard(
          padding: const EdgeInsets.all(Insets.md),
          color: palette.subtle.withValues(alpha: 0.55),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 18, color: palette.tracker),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  _prompt,
                  style: text.bodySmall
                      ?.copyWith(color: palette.mutedText, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        Text('Mood',
            style: text.labelMedium?.copyWith(color: palette.mutedText)),
        const SizedBox(height: Insets.sm),
        MoodScorePicker(
          value: _mood,
          onChanged: (value) => setState(() => _mood = value),
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Text('Energy',
                style: text.labelMedium?.copyWith(color: palette.mutedText)),
            if (_energy != null) ...[
              const SizedBox(width: Insets.sm),
              Text(
                _energyLabels[_energy!] ?? '',
                style: text.labelSmall?.copyWith(color: palette.tracker),
              ),
            ],
          ],
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: _energy == i,
                onSelected: (_) =>
                    setState(() => _energy = _energy == i ? null : i),
              ),
          ],
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _highlight,
          minLines: 2,
          maxLines: 5,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'A note for this moment',
            hintText:
                'A feeling, a highlight, or anything you want to remember',
            alignLabelWithHint: true,
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.edit_note_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          'You can add multiple check-ins in a day. Sleep and steps are tracked separately from Health.',
          style: text.bodySmall?.copyWith(color: palette.mutedText),
        ),
        if (!hasContent) ...[
          const SizedBox(height: Insets.xs),
          Text(
            'Even a quick note counts. Save as little or as much as you want.',
            style: text.bodySmall?.copyWith(color: palette.dimText),
          ),
        ],
        const SizedBox(height: Insets.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving
                ? 'Saving...'
                : (isEditing ? 'Save changes' : 'Save check-in')),
          ),
        ),
        if (isEditing) ...[
          const SizedBox(height: Insets.sm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _saving ? null : _delete,
              child: const Text('Delete check-in'),
            ),
          ),
        ],
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
        return await picker.pickMultipleMedia();
      case _MediaPickSource.files:
        return await openFiles();
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


