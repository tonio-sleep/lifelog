import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import '../today/quick_add.dart';
import 'voice_note_sheet.dart';

enum _SaveState { idle, unsaved, saving, saved, error }

class JournalEditorScreen extends ConsumerStatefulWidget {
  const JournalEditorScreen({
    super.key,
    this.entryId,
    this.initialDate,
    this.focusBody = false,
    this.initialKind = JournalEntryKind.journal,
  });

  final String? entryId;
  final DateTime? initialDate;
  final bool focusBody;
  final JournalEntryKind initialKind;

  @override
  ConsumerState<JournalEditorScreen> createState() =>
      _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  final _bodyFocus = FocusNode();

  JournalEntry? _source;
  late String _id;
  late DateTime _createdAt;
  late bool _draft;
  late bool _archived;
  late JournalEntryKind _kind;
  int? _mood;
  int? _energy;
  double? _sleepHours;
  int? _steps;
  String _meals = '';
  String _highlight = '';
  String? _placeId;
  String? _placeLabel;

  final List<TextEditingController> _vocabTerms = [];
  final List<TextEditingController> _vocabMeanings = [];
  final List<FocusNode> _vocabTermFocuses = [];

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
      kind: widget.initialKind,
    );
    _id = existing?.id ?? blank.id;
    _createdAt = existing?.createdAt ?? blank.createdAt;
    _draft = existing?.draft ?? true;
    _archived = existing?.archived ?? false;
    _kind = existing?.kind ?? widget.initialKind;
    _mood = existing?.mood;
    _energy = existing?.energy;
    _sleepHours = existing?.sleepHours;
    _steps = existing?.steps;
    _meals = existing?.meals ?? '';
    _highlight = existing?.highlight ?? '';
    _placeId = existing?.placeId;
    _placeLabel = existing?.placeLabel;
    _title = TextEditingController(text: existing?.title ?? '');
    _body = TextEditingController(text: existing?.body ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _showTags = (existing?.tags ?? const []).isNotEmpty;

    final vocab = existing?.vocabItems ?? const <VocabItem>[];
    if (vocab.isEmpty && _kind == JournalEntryKind.vocab) {
      _addVocabRow(notify: false);
      _addVocabRow(notify: false);
    } else {
      for (final item in vocab) {
        _addVocabRow(
          term: item.term,
          meaning: item.meaning,
          notify: false,
        );
      }
      if (_kind == JournalEntryKind.vocab && _vocabTerms.isEmpty) {
        _addVocabRow(notify: false);
      }
    }

    _title.addListener(_onChanged);
    _body.addListener(_onChanged);
    _tags.addListener(_onChanged);
    if (widget.focusBody) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_kind == JournalEntryKind.vocab && _vocabTermFocuses.isNotEmpty) {
          _vocabTermFocuses.first.requestFocus();
        } else {
          _bodyFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _bodyFocus.dispose();
    for (final c in _vocabTerms) {
      c.dispose();
    }
    for (final c in _vocabMeanings) {
      c.dispose();
    }
    for (final f in _vocabTermFocuses) {
      f.dispose();
    }
    super.dispose();
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

  List<VocabItem> get _currentVocabItems => List.generate(
        _vocabTerms.length,
        (i) => VocabItem(
          term: _vocabTerms[i].text,
          meaning: _vocabMeanings[i].text,
        ),
      );

  bool get _hasVocabContent => _currentVocabItems.any((v) => !v.isEmpty);

  bool get _hasContent {
    final media = ref
        .read(archiveProvider)
        .media
        .where((m) => m.journalEntryId == _id)
        .isNotEmpty;
    return _title.text.trim().isNotEmpty ||
        _body.text.trim().isNotEmpty ||
        _meals.trim().isNotEmpty ||
        _highlight.trim().isNotEmpty ||
        _steps != null ||
        _sleepHours != null ||
        _currentTags.isNotEmpty ||
        _mood != null ||
        _energy != null ||
        _placeId != null ||
        (_kind == JournalEntryKind.vocab && _hasVocabContent) ||
        media;
  }

  JournalEntry _buildEntry() {
    final tags = _currentTags;
    final vocab = _kind == JournalEntryKind.vocab
        ? _currentVocabItems.where((v) => !v.isEmpty).toList()
        : const <VocabItem>[];
    return JournalEntry(
      id: _id,
      createdAt: _createdAt,
      updatedAt: DateTime.now(),
      title: _title.text.trim(),
      body: _body.text,
      kind: _kind,
      vocabItems: vocab,
      mood: _mood,
      energy: _energy,
      sleepHours: _sleepHours,
      steps: _steps,
      meals: _meals,
      highlight: _highlight,
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

  Future<void> _addVoiceNote() async {
    final result = await showVoiceNoteSheet(context);
    if (result == null || !mounted) return;
    setState(() => _importing = true);
    try {
      if (!await _ensureSaved()) return;
      final bytes = await File(result.audioPath).readAsBytes();
      if (!mounted) return;
      await ref.read(archiveProvider.notifier).importMedia(
            bytes: Uint8List.fromList(bytes),
            fileName: result.fileName,
            mimeType: result.mimeType,
            caption: 'Voice note',
            tags: const ['voice-note', 'transcript'],
            journalEntryId: _id,
            createdAt: _createdAt,
          );

      final transcript = result.transcript.trim();
      if (transcript.isNotEmpty) {
        final current = _body.text;
        final needsSpace = current.isNotEmpty && !current.endsWith('\n');
        final addition = needsSpace ? '\n\n$transcript' : transcript;
        final selection = _body.selection;
        if (selection.isValid && selection.start >= 0 && selection.end >= 0) {
          final start = selection.start.clamp(0, current.length);
          final end = selection.end.clamp(0, current.length);
          final updated = current.replaceRange(start, end, addition);
          _body.value = TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(offset: start + addition.length),
          );
        } else {
          _body.text = '$current$addition';
          _body.selection = TextSelection.collapsed(offset: _body.text.length);
        }
      }

      if (!mounted) return;
      showSnack(
        context,
        transcript.isEmpty
            ? 'Voice note audio saved to this entry.'
            : 'Voice note saved with transcript.',
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not save voice note: $error');
    } finally {
      try {
        final f = File(result.audioPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _attachFiles() async {
    setState(() => _importing = true);
    try {
      final files = await pickMediaFromPhotosOrFiles(context);
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
        await ref.read(archiveProvider.notifier).importMedia(
              bytes: Uint8List.fromList(bytes),
              fileName: file.name,
              caption: details.caption,
              tags: details.tags,
              journalEntryId: _id,
              createdAt: _createdAt,
            );
      }
      if (!mounted) return;
      showSnack(
        context,
        files.length == 1 ? 'Added to the entry.' : '${files.length} items added.',
      );
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

  Future<void> _editFeeling() async {
    var mood = _mood;
    var energy = _energy;
    final noteController = TextEditingController(text: _highlight);
    await showLifelogSheet<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle(
              title: 'How are you feeling?',
              subtitle: 'Set mood and a note for this entry (optional).',
            ),
            Text(
              'Mood (1-10)',
              style: sheetContext.text.labelMedium
                  ?.copyWith(color: sheetContext.palette.mutedText),
            ),
            const SizedBox(height: Insets.sm),
            MoodScorePicker(
              value: mood,
              onChanged: (value) => setSheetState(() => mood = value),
            ),
            const SizedBox(height: Insets.md),
            Text(
              'Energy',
              style: sheetContext.text.labelMedium
                  ?.copyWith(color: sheetContext.palette.mutedText),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              children: [
                for (var i = 1; i <= 5; i++)
                  ChoiceChip(
                    label: Text('$i'),
                    selected: energy == i,
                    onSelected: (_) =>
                        setSheetState(() => energy = energy == i ? null : i),
                  ),
              ],
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: noteController,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Feeling note (optional)',
                hintText: 'What is on your mind right now?',
              ),
            ),
            const SizedBox(height: Insets.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      noteController.dispose();
      return;
    }
    setState(() {
      _mood = mood;
      _energy = energy;
      _highlight = noteController.text.trim();
      _state = _SaveState.unsaved;
    });
    Future<void>.delayed(const Duration(milliseconds: 400), noteController.dispose);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  void _addVocabRow({String term = '', String meaning = '', bool notify = true}) {
    final termCtrl = TextEditingController(text: term);
    final meaningCtrl = TextEditingController(text: meaning);
    final focus = FocusNode();
    termCtrl.addListener(_onChanged);
    meaningCtrl.addListener(_onChanged);
    if (notify) {
      setState(() {
        _vocabTerms.add(termCtrl);
        _vocabMeanings.add(meaningCtrl);
        _vocabTermFocuses.add(focus);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    } else {
      _vocabTerms.add(termCtrl);
      _vocabMeanings.add(meaningCtrl);
      _vocabTermFocuses.add(focus);
    }
  }

  void _removeVocabRow(int index) {
    if (index < 0 || index >= _vocabTerms.length) return;
    setState(() {
      _vocabTerms.removeAt(index).dispose();
      _vocabMeanings.removeAt(index).dispose();
      _vocabTermFocuses.removeAt(index).dispose();
    });
    _onChanged();
  }

  void _setKind(JournalEntryKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      if (kind == JournalEntryKind.vocab && _vocabTerms.isEmpty) {
        _addVocabRow(notify: false);
      }
      _state = _SaveState.unsaved;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _close() async {
    await _saveDraft();
    if (!mounted) return;
    _allowPop = true;
    Navigator.of(context).pop();
  }

  String _titleHint() => switch (_kind) {
        JournalEntryKind.journal => 'Title',
        JournalEntryKind.note => 'Note title',
        JournalEntryKind.vocab => 'Vocab list name (optional)',
      };

  String _bodyHint() => switch (_kind) {
        JournalEntryKind.journal => 'Start writing…',
        JournalEntryKind.note => 'Write a quick note…',
        JournalEntryKind.vocab => 'Notes about this vocab list (optional)…',
      };

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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

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
                padding:
                    const EdgeInsets.fromLTRB(Insets.xs, Insets.xs, Insets.md, 0),
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
                              _archived
                                  ? 'Restore from archive'
                                  : 'Archive entry',
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: Insets.lg),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: keyboardOpen
                      ? () => FocusScope.of(context).unfocus()
                      : null,
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
                              color:
                                  scheme.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.archive_outlined,
                                    size: 18, color: scheme.secondary),
                                const SizedBox(width: Insets.sm),
                                Expanded(
                                  child: Text(
                                    'Archived. Restore it from the menu to bring it back.',
                                    style: text.bodySmall
                                        ?.copyWith(color: scheme.secondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: Insets.sm,
                          runSpacing: Insets.sm,
                          children: [
                            for (final kind in JournalEntryKind.values)
                              ChoiceChip(
                                label: Text(kind.label),
                                selected: _kind == kind,
                                onSelected: (_) => _setKind(kind),
                              ),
                          ],
                        ),
                        const SizedBox(height: Insets.md),
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
                                  Icon(Icons.schedule_rounded,
                                      size: 15, color: palette.mutedText),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${formatDayLong(_createdAt)}, ${formatTime(_createdAt)}',
                                    style: text.labelMedium
                                        ?.copyWith(color: palette.mutedText),
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
                            hintText: _titleHint(),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintStyle: text.headlineMedium
                                ?.copyWith(color: palette.dimText),
                          ),
                        ),
                        AnimatedSize(
                          duration: Motion.base,
                          curve: Motion.out,
                          alignment: Alignment.topCenter,
                          child: media.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(
                                      top: Insets.md, bottom: Insets.xs),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      StoryStrip(
                                        items: media,
                                        scope: 'editor',
                                        height: 150,
                                      ),
                                      const SizedBox(height: Insets.xs),
                                      Text(
                                        'Tap a photo to caption or remove it.',
                                        style: text.labelSmall
                                            ?.copyWith(color: palette.dimText),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        if (_kind == JournalEntryKind.vocab) ...[
                          const SizedBox(height: Insets.md),
                          _VocabEditor(
                            termControllers: _vocabTerms,
                            meaningControllers: _vocabMeanings,
                            termFocuses: _vocabTermFocuses,
                            onAdd: () => _addVocabRow(),
                            onRemove: _removeVocabRow,
                          ),
                          const SizedBox(height: Insets.md),
                          TextField(
                            controller: _body,
                            focusNode: _bodyFocus,
                            minLines: 2,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppTheme.serif(text.bodyLarge, size: 16)
                                .copyWith(height: 1.6),
                            decoration: InputDecoration(
                              hintText: _bodyHint(),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              hintStyle:
                                  AppTheme.serif(text.bodyLarge, size: 16)
                                      .copyWith(color: palette.dimText),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: Insets.md),
                          TextField(
                            controller: _body,
                            focusNode: _bodyFocus,
                            minLines: 8,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppTheme.serif(text.bodyLarge, size: 17)
                                .copyWith(height: 1.65),
                            decoration: InputDecoration(
                              hintText: _bodyHint(),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              hintStyle:
                                  AppTheme.serif(text.bodyLarge, size: 17)
                                      .copyWith(color: palette.dimText),
                            ),
                          ),
                        ],
                        const SizedBox(height: Insets.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(Insets.md),
                          decoration: BoxDecoration(
                            color: palette.subtle,
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Text(
                            _kind == JournalEntryKind.vocab
                                ? 'Use this vocab entry for words, phrases, and meanings. You can add more entries to the same day to keep notes and vocab together.'
                                : 'Add entries to the same day, set how you feel for this entry, or use the mic to record a voice note with transcription. Sleep and steps sync separately from Health.',
                            style: text.bodySmall
                                ?.copyWith(color: palette.mutedText),
                          ),
                        ),
                        AnimatedSize(
                          duration: Motion.base,
                          curve: Motion.out,
                          alignment: Alignment.topCenter,
                          child: !_showTags
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding:
                                      const EdgeInsets.only(top: Insets.lg),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextField(
                                        controller: _tags,
                                        style: text.bodyMedium,
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Tags, separated by commas',
                                          prefixIcon:
                                              Icon(Icons.tag_rounded, size: 19),
                                        ),
                                      ),
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: _tags,
                                        builder: (context, value, _) {
                                          final tags = normaliseTags(
                                              value.text.split(','));
                                          if (tags.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                top: Insets.sm),
                                            child: Wrap(
                                              spacing: Insets.sm,
                                              runSpacing: Insets.sm,
                                              children: [
                                                for (final tag in tags)
                                                  TagPill(tag)
                                              ],
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
                            onTap: () {
                              if (keyboardOpen) {
                                FocusScope.of(context).unfocus();
                                return;
                              }
                              if (_kind == JournalEntryKind.vocab &&
                                  _vocabTermFocuses.isNotEmpty) {
                                _vocabTermFocuses.first.requestFocus();
                              } else {
                                _bodyFocus.requestFocus();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
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
              padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm, vertical: Insets.xs),
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
                        : Icon(Icons.add_photo_alternate_outlined,
                            color: palette.photo),
                  ),
                  IconButton(
                    tooltip: 'Voice note (record & transcribe)',
                    onPressed: _importing ? null : _addVoiceNote,
                    icon: Icon(Icons.mic_none_rounded, color: palette.journal),
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
                    tooltip: _mood == null
                        ? 'How you feel'
                        : 'Feeling: ${MoodScore.label(_mood!)}',
                    onPressed: _editFeeling,
                    icon: _mood == null
                        ? Icon(Icons.mood_outlined, color: palette.tracker)
                        : Icon(
                            Icons.mood_rounded,
                            color: moodColor(_mood!, context.scheme),
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
                        style:
                            text.labelMedium?.copyWith(color: palette.mutedText),
                      ),
                    ),
                  const Spacer(),
                  if (keyboardOpen)
                    TextButton(
                      onPressed: () => FocusScope.of(context).unfocus(),
                      child: Text(
                        'Done',
                        style: text.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _body,
                    builder: (context, value, _) {
                      final words = RegExp(r'\S+').allMatches(value.text).length;
                      final vocabCount = _kind == JournalEntryKind.vocab
                          ? _currentVocabItems.where((v) => !v.isEmpty).length
                          : 0;
                      final label = vocabCount > 0
                          ? '$vocabCount ${plural(vocabCount, 'word')}${words > 0 ? ' · $words ${plural(words, 'word')} notes' : ''}'
                          : '$words ${plural(words, 'word')}';
                      return Padding(
                        padding: const EdgeInsets.only(right: Insets.md),
                        child: Text(
                          label,
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

class _VocabEditor extends StatelessWidget {
  const _VocabEditor({
    required this.termControllers,
    required this.meaningControllers,
    required this.termFocuses,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> termControllers;
  final List<TextEditingController> meaningControllers;
  final List<FocusNode> termFocuses;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.translate_rounded, size: 18, color: palette.tracker),
            const SizedBox(width: Insets.sm),
            Text('Words and meanings', style: text.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add word'),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        if (termControllers.isEmpty)
          Text(
            'Add a word or phrase with its meaning.',
            style: text.bodySmall?.copyWith(color: palette.mutedText),
          ),
        for (var i = 0; i < termControllers.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: Insets.sm),
            padding: const EdgeInsets.all(Insets.sm),
            decoration: BoxDecoration(
              color: palette.subtle,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: termControllers[i],
                        focusNode: termFocuses[i],
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Word or phrase',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      TextField(
                        controller: meaningControllers[i],
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Meaning / translation / note',
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => onRemove(i),
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: palette.dimText),
                ),
              ],
            ),
          ),
      ],
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
