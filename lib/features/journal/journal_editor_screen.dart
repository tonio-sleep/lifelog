import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/places.dart';
import '../photos/photo_widgets.dart';
import '../places/place_dialogs.dart';

enum _SaveState { idle, unsaved, saving, saved, error }

const _moodIcons = <Mood, IconData>{
  Mood.awful: Icons.sentiment_very_dissatisfied_rounded,
  Mood.low: Icons.sentiment_dissatisfied_rounded,
  Mood.okay: Icons.sentiment_neutral_rounded,
  Mood.good: Icons.sentiment_satisfied_rounded,
  Mood.great: Icons.sentiment_very_satisfied_rounded,
};

class JournalEditorScreen extends ConsumerStatefulWidget {
  const JournalEditorScreen({
    super.key,
    this.entryId,
    this.initialDate,
    this.focusBody = false,
  });

  final String? entryId;
  final DateTime? initialDate;
  final bool focusBody;

  @override
  ConsumerState<JournalEditorScreen> createState() =>
      _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  late final TextEditingController _meals;
  late final TextEditingController _highlight;
  late final TextEditingController _steps;
  late final TextEditingController _sleep;
  final _bodyFocus = FocusNode();

  JournalEntry? _source;
  late String _id;
  late DateTime _createdAt;
  late bool _draft;
  late bool _archived;
  Mood? _mood;
  int? _energy;
  String? _placeId;
  String? _placeLabel;

  Timer? _debounce;
  _SaveState _state = _SaveState.idle;
  String? _error;
  bool _importing = false;
  bool _allowPop = false;
  bool _deleted = false;
  bool _showTags = false;
  DateTime? _lastSavedAt;

  bool get _isNew => _source == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.entryId == null
        ? null
        : ref.read(archiveProvider).entryById(widget.entryId!);
    _source = existing;
    final blank = JournalEntry.blank(
      widget.initialDate ?? DateTime.now(),
    );
    _id = existing?.id ?? blank.id;
    _createdAt = existing?.createdAt ?? blank.createdAt;
    _draft = existing?.draft ?? true;
    _archived = existing?.archived ?? false;
    _mood = existing?.mood;
    _energy = existing?.energy;
    _placeId = existing?.placeId;
    _placeLabel = existing?.placeLabel;
    _title = TextEditingController(text: existing?.title ?? '');
    _body = TextEditingController(text: existing?.body ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _meals = TextEditingController(text: existing?.meals ?? '');
    _highlight = TextEditingController(text: existing?.highlight ?? '');
    _steps = TextEditingController(text: existing?.steps?.toString() ?? '');
    _sleep = TextEditingController(text: existing?.sleepHours == null ? '' : _formatNum(existing!.sleepHours!));
    _showTags = (existing?.tags ?? const []).isNotEmpty;
    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
    _tags.addListener(_onChanged);
    _meals.addListener(_onChanged);
    _highlight.addListener(_onChanged);
    _steps.addListener(_onChanged);
    _sleep.addListener(_onChanged);
    if (widget.focusBody) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bodyFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _meals.dispose();
    _highlight.dispose();
    _steps.dispose();
    _sleep.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
  }

  void _onChanged() {
    final state = _state;
    if (state != _SaveState.unsaved) {
      setState(() => _state = _SaveState.unsaved);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_saveDraft());
    });
  }

  List<String> get _currentTags => normaliseTags(_tags.text.split(','));

  bool get _hasContent {
    final media = ref
        .read(archiveProvider)
        .media
        .where((m) => m.journalEntryId == _id)
        .isNotEmpty;
    return _title.text.trim().isNotEmpty ||
        _body.text.trim().isNotEmpty ||
        _meals.text.trim().isNotEmpty ||
        _highlight.text.trim().isNotEmpty ||
        _steps.text.trim().isNotEmpty ||
        _sleep.text.trim().isNotEmpty ||
        _currentTags.isNotEmpty ||
        _mood != null ||
        _energy != null ||
        _placeId != null ||
        media;
  }

  JournalEntry _buildEntry() {
    final tags = _currentTags;
    final stepsVal = int.tryParse(_steps.text.trim());
    final sleepVal = double.tryParse(_sleep.text.trim().replaceAll(',', '.'));
    return JournalEntry(
      id: _id,
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
      title: _title.text.trim(),
      body: _body.text,
      mood: _mood,
      energy: _energy,
      sleepHours: sleepVal,
      steps: stepsVal,
      meals: _meals.text.trim(),
      highlight: _highlight.text.trim(),
      tags: tags,
      placeId: _placeId,
      placeLabel: _placeLabel,
      draft: _draft,
      archived: _archived,
    );
  }

  Future<void> _saveDraft() async {
    if (_deleted) return;
    if (!_hasContent && _source == null) return;
    _debounce?.cancel();
    if (mounted) {
      setState(() {
        _state = _SaveState.saving;
        _error = null;
      });
    }
    try {
      await ref.read(archiveProvider.notifier).saveEntry(_buildEntry());
      if (!mounted) return;
      setState(() {
        _state = _SaveState.saved;
        _lastSavedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _SaveState.error;
        _error = '$error';
      });
    }
  }

  Future<void> _finish() async {
    _draft = false;
    await _saveDraft();
    if (!mounted) return;
    if (_state == _SaveState.error) return;
    _allowPop = true;
    Navigator.of(context).pop();
  }

  Future<void> _duplicate() async {
    await _saveDraft();
    if (!mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).duplicateEntry(_buildEntry()),
      errorPrefix: 'Could not duplicate entry',
    );
    if (!mounted) return;
    _allowPop = true;
    Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    _archived = !_archived;
    await _saveDraft();
    if (!mounted) return;
    showSnack(
      context,
      _archived
          ? 'Entry moved to the archive.'
          : 'Entry restored from the archive.',
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message:
          'The entry and its encrypted attachments will be permanently '
          'removed from this device. This cannot be undone.',
    );
    if (!ok || !mounted) return;
    _deleted = true;
    _debounce?.cancel();
    try {
      await ref.read(archiveProvider.notifier).deleteEntry(_id);
      if (!mounted) return;
      _allowPop = true;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _deleted = false;
      showSnack(context, 'Could not delete entry: $error');
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (!mounted) return;
    setState(() {
      _createdAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _createdAt.hour,
        time?.minute ?? _createdAt.minute,
      );
      _state = _SaveState.unsaved;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _attachFiles() async {
    setState(() => _importing = true);
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      if (!await _ensureSaved()) return;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final details = await askMediaDetails(
          context,
          fileName: file.name,
        );
        if (details == null) continue;
        if (!mounted) return;
        await ref
            .read(archiveProvider.notifier)
            .importMedia(
              bytes: Uint8List.fromList(bytes),
              fileName: file.name,
              caption: details.caption,
              tags: details.tags,
              journalEntryId: _id,
              createdAt: _createdAt,
            );
      }
      if (!mounted) return;
      showSnack(context, 'Encrypted attachment${files.length == 1 ? '' : 's'} added.');
    } catch (error) {
      if (mounted) showSnack(context, 'Could not import media: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _ensureSaved() async {
    if (_state == _SaveState.saving) {
      await _saveDraft();
    }
    await _saveDraft();
    return _state != _SaveState.error;
  }

  Future<void> _pickPlace() async {
    final archive = ref.read(archiveProvider);
    final places = [...archive.places]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final result = await showLifelogSheet<({Place? place})>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(title: 'Where was this?'),
          _PlaceOption(
            icon: Icons.location_off_outlined,
            label: 'No place',
            color: sheetContext.palette.manual,
            selected: _placeId == null,
            onTap: () => Navigator.of(sheetContext).pop((place: null)),
          ),
          for (final place in places)
            _PlaceOption(
              icon: Icons.place_rounded,
              label: place.name,
              detail: place.hasCoordinates ? 'Coordinates saved' : null,
              color: Color(place.colorValue),
              selected: _placeId == place.id,
              onTap: () => Navigator.of(sheetContext).pop((place: place)),
            ),
          _PlaceOption(
            icon: Icons.add_location_alt_outlined,
            label: 'New saved place',
            color: sheetContext.scheme.primary,
            onTap: () async {
              final place = await showPlaceEditor(sheetContext, ref);
              if (place != null && sheetContext.mounted) {
                Navigator.of(sheetContext).pop((place: place));
              }
            },
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final selected = result.place;
    setState(() {
      if (selected == null) {
        _placeId = null;
        _placeLabel = null;
      } else {
        _placeId = selected.id;
        _placeLabel = selected.name;
      }
      _state = _SaveState.unsaved;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  void _setMood(Mood? mood) {
    setState(() {
      _mood = mood;
      _state = _SaveState.unsaved;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  void _setEnergy(int? energy) {
    setState(() {
      _energy = energy;
      _state = _SaveState.unsaved;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _importStepsFromHealth() async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      if (mounted) showSnack(context, 'Health steps are available on iPhone/Android with Health access enabled.');
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
      services.healthSteps.getStepsForDay(_createdAt),
      errorPrefix: 'Could not read steps',
    );
    if (!mounted) return;
    if (steps == null) {
      showSnack(context, 'No step data available for this day.');
      return;
    }
    _steps.text = steps.toString();
    _onChanged();
    showSnack(context, 'Imported $steps steps from Health.');
  }

  Future<void> _close() async {
    await _saveDraft();
    if (!mounted) return;
    _allowPop = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final media = archive
        .mediaForEntry(_id)
        .where((item) => item.journalEntryId == _id)
        .toList();
    final palette = context.palette;
    final text = context.text;
    final scheme = context.scheme;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveDraft();
        if (!mounted) return;
        _allowPop = true;
        if (!context.mounted) return;
        Navigator.of(context).pop(result);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.xs, Insets.md, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: _SaveStatus(
                          state: _state,
                          savedAt: _lastSavedAt,
                          error: _error,
                        ),
                      ),
                    ),
                    if (!_isNew)
                      PopupMenuButton<String>(
                        tooltip: 'Entry actions',
                        onSelected: (value) async {
                          if (value == 'duplicate') await _duplicate();
                          if (value == 'archive') await _archive();
                          if (value == 'delete') await _delete();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate as draft'),
                          ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(
                              _archived ? 'Restore from archive' : 'Archive entry',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete entry'),
                          ),
                        ],
                      ),
                    const SizedBox(width: Insets.xs),
                    FilledButton(
                      onPressed: _state == _SaveState.saving ? null : _finish,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.page,
                        Insets.md,
                        Insets.page,
                        Insets.xl,
                      ),
                      children: [
                        if (_archived)
                          Container(
                            margin: const EdgeInsets.only(bottom: Insets.md),
                            padding: const EdgeInsets.all(Insets.md),
                            decoration: BoxDecoration(
                              color: scheme.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.archive_outlined, size: 18, color: scheme.secondary),
                                const SizedBox(width: Insets.sm),
                                Expanded(
                                  child: Text(
                                    'Archived. Restore it from the menu to bring it back.',
                                    style: text.bodySmall?.copyWith(color: scheme.secondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Pressable(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Insets.md,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: palette.subtle,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule_rounded, size: 15, color: palette.mutedText),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${formatDayLong(_createdAt)}, ${formatTime(_createdAt)}',
                                    style: text.labelMedium?.copyWith(color: palette.mutedText),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _title,
                          style: text.headlineMedium,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Title',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: text.headlineMedium?.copyWith(color: palette.dimText),
                          ),
                        ),
                        AnimatedSize(
                          duration: Motion.base,
                          curve: Motion.out,
                          alignment: Alignment.topCenter,
                          child: media.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: Insets.md, bottom: Insets.xs),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      StoryStrip(
                                        items: media,
                                        scope: 'editor',
                                        height: 150,
                                      ),
                                      const SizedBox(height: Insets.xs),
                                      Text(
                                        'Tap a photo to caption or remove it.',
                                        style: text.labelSmall?.copyWith(color: palette.dimText),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _body,
                          focusNode: _bodyFocus,
                          minLines: 8,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          style: AppTheme.serif(text.bodyLarge, size: 17).copyWith(height: 1.65),
                          decoration: InputDecoration(
                            hintText: 'Start writing…',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: AppTheme.serif(text.bodyLarge, size: 17)
                                .copyWith(color: palette.dimText),
                          ),
                        ),
                        const SizedBox(height: Insets.xl),
                        Text(
                          'How are you doing today?',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: Insets.xs),
                        Text(
                          'A quick check-in for your day (all optional).',
                          style: text.bodySmall?.copyWith(color: palette.mutedText),
                        ),
                        const SizedBox(height: Insets.md),
                        Text(
                          'Mood',
                          style: text.labelMedium?.copyWith(color: palette.mutedText),
                        ),
                        const SizedBox(height: Insets.sm),
                        Row(
                          children: [
                            for (final mood in Mood.values)
                              Padding(
                                padding: const EdgeInsets.only(right: Insets.sm),
                                child: _MoodDot(
                                  mood: mood,
                                  selected: _mood == mood,
                                  onTap: () => _setMood(_mood == mood ? null : mood),
                                ),
                              ),
                            const SizedBox(width: Insets.xs),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: Motion.fast,
                                child: Text(
                                  _mood?.label ?? '',
                                  key: ValueKey<String>(_mood?.label ?? ''),
                                  style: text.labelLarge?.copyWith(
                                    color: _mood == null
                                        ? palette.dimText
                                        : moodColor(_mood!, scheme),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Insets.md),
                        Text(
                          'Energy',
                          style: text.labelMedium?.copyWith(color: palette.mutedText),
                        ),
                        const SizedBox(height: Insets.sm),
                        Row(
                          children: [
                            for (var i = 1; i <= 5; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: Insets.sm),
                                child: _LevelDot(
                                  value: i,
                                  selected: _energy == i,
                                  onTap: () => _setEnergy(_energy == i ? null : i),
                                  color: scheme.primary,
                                ),
                              ),
                            const SizedBox(width: Insets.xs),
                            Expanded(
                              child: Text(
                                _energy == null ? '' : '$_energy / 5',
                                style: text.labelLarge?.copyWith(
                                  color: _energy == null ? palette.dimText : scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Insets.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _sleep,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Sleep (hours)',
                                  hintText: 'e.g. 7.5',
                                  prefixIcon: Icon(Icons.bedtime_outlined, size: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: Insets.md),
                            Expanded(
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _steps,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Steps',
                                      hintText: 'e.g. 8000',
                                      prefixIcon: Icon(Icons.directions_walk_rounded, size: 18),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: _importStepsFromHealth,
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.favorite_outline_rounded, size: 14),
                                      label: const Text('Import from Health', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _meals,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'What did you eat?',
                            hintText: 'Breakfast, lunch, dinner, snacks...',
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
                            labelText: 'Highlight or reflection',
                            hintText: 'Best part of the day, gratitude, or how it went',
                            prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18),
                          ),
                        ),
                        AnimatedSize(
                          duration: Motion.base,
                          curve: Motion.out,
                          alignment: Alignment.topCenter,
                          child: !_showTags
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: Insets.lg),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextField(
                                        controller: _tags,
                                        style: text.bodyMedium,
                                        decoration: const InputDecoration(
                                          hintText: 'Tags, separated by commas',
                                          prefixIcon: Icon(Icons.tag_rounded, size: 19),
                                        ),
                                      ),
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: _tags,
                                        builder: (context, value, _) {
                                          final tags = normaliseTags(value.text.split(','));
                                          if (tags.isEmpty) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.only(top: Insets.sm),
                                            child: Wrap(
                                              spacing: Insets.sm,
                                              runSpacing: Insets.sm,
                                              children: [for (final tag in tags) TagPill(tag)],
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        SizedBox(
                          height: 120,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => _bodyFocus.requestFocus(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: palette.card,
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Add photos or video',
                    onPressed: _importing ? null : _attachFiles,
                    icon: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.add_photo_alternate_outlined, color: palette.photo),
                  ),
                  IconButton(
                    tooltip: _placeLabel ?? 'Add a place',
                    onPressed: _pickPlace,
                    icon: Icon(
                      _placeLabel == null
                          ? Icons.place_outlined
                          : Icons.place_rounded,
                      color: palette.place,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tags',
                    onPressed: () => setState(() => _showTags = !_showTags),
                    icon: Icon(
                      Icons.tag_rounded,
                      color: _showTags ? scheme.primary : palette.mutedText,
                    ),
                  ),
                  if (_placeLabel != null)
                    Flexible(
                      child: Text(
                        _placeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(color: palette.mutedText),
                      ),
                    ),
                  const Spacer(),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _body,
                    builder: (context, value, _) {
                      final words = RegExp(r'\S+').allMatches(value.text).length;
                      return Padding(
                        padding: const EdgeInsets.only(right: Insets.md),
                        child: Text(
                          '$words ${plural(words, 'word')}',
                          style: text.labelSmall?.copyWith(
                            color: palette.dimText,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceOption extends StatelessWidget {
  const _PlaceOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.detail,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 38, iconSize: 19),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.titleSmall),
                  if (detail != null)
                    Text(
                      detail!,
                      style: context.text.labelSmall?.copyWith(
                        color: context.palette.dimText,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: context.scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _MoodDot extends StatelessWidget {
  const _MoodDot({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = moodColor(mood, context.scheme);
    return Tooltip(
      message: mood.label,
      child: Pressable(
        scale: 0.88,
        haptic: true,
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.out,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : color.withValues(alpha: 0.13),
          ),
          child: Icon(
            _moodIcons[mood] ?? Icons.sentiment_neutral_rounded,
            size: 22,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot({
    required this.value,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$value / 5',
      child: Pressable(
        scale: 0.9,
        haptic: true,
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.out,
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : color.withValues(alpha: 0.12),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            '$value',
            style: context.text.labelLarge?.copyWith(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// A calm pill that always says what is happening to the draft.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state, this.savedAt, this.error});

  final _SaveState state;
  final DateTime? savedAt;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = context.scheme;
    final (String label, Color color, Widget lead) = switch (state) {
      _SaveState.idle => (
        'Encrypted on this device',
        palette.dimText,
        Icon(Icons.lock_outline_rounded, size: 13, color: palette.dimText),
      ),
      _SaveState.unsaved => (
        'Editing',
        scheme.secondary,
        PulsingDot(color: scheme.secondary, size: 6),
      ),
      _SaveState.saving => (
        'Saving',
        palette.mutedText,
        PulsingDot(color: palette.mutedText, size: 6),
      ),
      _SaveState.saved => (
        savedAt == null ? 'Saved' : 'Saved ${formatTime(savedAt!)}',
        palette.tracker,
        Icon(Icons.check_circle_rounded, size: 14, color: palette.tracker),
      ),
      _SaveState.error => (
        'Could not save',
        scheme.error,
        Icon(Icons.error_outline_rounded, size: 14, color: scheme.error),
      ),
    };
    return Tooltip(
      message: state == _SaveState.error && error != null ? error! : label,
      child: AnimatedSwitcher(
        duration: Motion.fast,
        child: Row(
          key: ValueKey<String>(label),
          mainAxisSize: MainAxisSize.min,
          children: [
            lead,
            const SizedBox(width: 6),
            Text(
              label,
              style: context.text.labelMedium?.copyWith(
                color: color,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
