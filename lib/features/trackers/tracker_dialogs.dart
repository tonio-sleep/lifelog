import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/trackers.dart';

const trackerIconChoices = <String>[
  'circle',
  'shower',
  'water',
  'mood',
  'book',
  'walk',
  'meal',
  'sleep',
  'restroom',
  'star',
  'coffee',
  'work',
  'music',
  'heart',
];

const trackerColorChoices = <int>[
  0xFF5B6CFF,
  0xFF2FA37A,
  0xFF2F9BD0,
  0xFFE07B39,
  0xFFD6567A,
  0xFF9A62DB,
  0xFFC9A227,
  0xFF4DB6AC,
];

IconData trackerIcon(String key) => switch (key) {
  'shower' => Icons.shower_outlined,
  'water' => Icons.water_drop_outlined,
  'mood' => Icons.sentiment_satisfied_alt_outlined,
  'book' => Icons.menu_book_outlined,
  'walk' => Icons.directions_walk_rounded,
  'meal' => Icons.restaurant_outlined,
  'sleep' => Icons.bedtime_outlined,
  'restroom' => Icons.wc_rounded,
  'star' => Icons.star_outline_rounded,
  'coffee' => Icons.coffee_outlined,
  'work' => Icons.work_outline_rounded,
  'music' => Icons.music_note_outlined,
  'heart' => Icons.favorite_outline_rounded,
  _ => Icons.circle_outlined,
};

Color trackerColor(int value) => Color(value);

/// Optional starter templates. They are only added when the user chooses them;
/// no sample records are ever created.
class TrackerTemplates {
  const TrackerTemplates._();

  static TrackerDefinition shower() => _base(
    name: 'Shower',
    type: TrackerType.boolean,
    icon: 'shower',
    color: 0xFF4C7F96,
    category: 'Personal care',
  );

  static TrackerDefinition water() => _base(
    name: 'Water',
    type: TrackerType.count,
    icon: 'water',
    color: 0xFF4C7F96,
    category: 'Daily life',
    target: 8,
    unit: 'glasses',
  );

  static TrackerDefinition mood() => _base(
    name: 'Mood',
    type: TrackerType.rating,
    icon: 'mood',
    color: 0xFF8A6BA1,
    category: 'Daily life',
  );

  static TrackerDefinition reading() => _base(
    name: 'Reading',
    type: TrackerType.duration,
    icon: 'book',
    color: 0xFFA08052,
    category: 'Daily life',
    unit: 'min',
  );

  static TrackerDefinition walk() => _base(
    name: 'Walk',
    type: TrackerType.duration,
    icon: 'walk',
    color: 0xFF6B8F71,
    category: 'Daily life',
    unit: 'min',
  );

  static TrackerDefinition restroom() => _base(
    name: 'Restroom',
    type: TrackerType.count,
    icon: 'restroom',
    color: 0xFF6A7A8C,
    category: 'Bathroom',
  );

  static TrackerDefinition coffee() => _base(
    name: 'Coffee',
    type: TrackerType.count,
    icon: 'coffee',
    color: 0xFFA08052,
    category: 'Daily life',
  );

  static TrackerDefinition _base({
    required String name,
    required TrackerType type,
    required String icon,
    required int color,
    required String category,
    double? target,
    String unit = '',
  }) {
    return TrackerDefinition(
      id: const Uuid().v4(),
      name: name,
      type: type,
      createdAt: DateTime.now(),
      icon: icon,
      colorValue: color,
      category: category,
      target: target,
      unit: unit,
    );
  }
}

IconData trackerTypeIcon(TrackerType type) => switch (type) {
  TrackerType.boolean => Icons.check_circle_outline_rounded,
  TrackerType.count => Icons.exposure_plus_1_rounded,
  TrackerType.number => Icons.numbers_rounded,
  TrackerType.duration => Icons.timer_outlined,
  TrackerType.rating => Icons.star_outline_rounded,
  TrackerType.text => Icons.notes_rounded,
  TrackerType.event => Icons.bolt_rounded,
};

Future<void> showTrackerLogDialog(
  BuildContext context,
  WidgetRef ref,
  TrackerDefinition tracker, {
  DateTime? day,
  TrackerRecord? editing,
}) async {
  await showLifelogSheet<void>(
    context,
    builder: (_) => _TrackerLogSheet(
      tracker: tracker,
      day: day ?? DateTime.now(),
      editing: editing,
    ),
  );
}

class _TrackerLogSheet extends ConsumerStatefulWidget {
  const _TrackerLogSheet({
    required this.tracker,
    required this.day,
    this.editing,
  });

  final TrackerDefinition tracker;
  final DateTime day;
  final TrackerRecord? editing;

  @override
  ConsumerState<_TrackerLogSheet> createState() => _TrackerLogSheetState();
}

class _TrackerLogSheetState extends ConsumerState<_TrackerLogSheet> {
  late final TextEditingController _valueController;
  late final TextEditingController _textController;
  late final TextEditingController _noteController;
  late final TextEditingController _durationController;
  late final TextEditingController _countController;
  late DateTime _when;
  DateTime? _startedAt;
  DateTime? _endedAt;
  late int _rating;
  bool _boolValue = true;
  bool _busy = false;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final now = DateTime.now();
    _when =
        editing?.recordedAt ??
        DateTime(
          widget.day.year,
          widget.day.month,
          widget.day.day,
          now.hour,
          now.minute,
        );
    _startedAt = editing?.startedAt;
    _endedAt = editing?.endedAt;
    _rating = (editing?.value ?? 3).round().clamp(1, 5);
    if (editing != null && widget.tracker.type == TrackerType.boolean) {
      _boolValue = (editing.value ?? 0) > 0;
    }
    _valueController = TextEditingController(
      text: editing?.value == null
          ? (widget.tracker.type == TrackerType.count ? '1' : '')
          : formatCompactNumber(editing!.value!),
    );
    _textController = TextEditingController(text: editing?.text ?? '');
    _noteController = TextEditingController(text: editing?.note ?? '');
    final dur = editing?.durationMinutes ?? editing?.effectiveDurationMinutes;
    _durationController = TextEditingController(
      text: dur == null ? '' : formatCompactNumber(dur),
    );
    _countController = TextEditingController(
      text: editing?.count == null ? '' : formatCompactNumber(editing!.count!),
    );
    _more = (editing?.note ?? '').isNotEmpty ||
        editing?.startedAt != null ||
        editing?.endedAt != null ||
        (editing?.durationMinutes != null) ||
        (editing?.count != null);
  }

  @override
  void dispose() {
    _valueController.dispose();
    _textController.dispose();
    _noteController.dispose();
    _durationController.dispose();
    _countController.dispose();
    super.dispose();
  }

  void _bump(double delta) {
    final current = double.tryParse(_valueController.text.trim()) ?? 0;
    final next = (current + delta).clamp(0, 1000000).toDouble();
    HapticFeedback.selectionClick();
    setState(() => _valueController.text = formatCompactNumber(next));
  }

  @override
  Widget build(BuildContext context) {
    final tracker = widget.tracker;
    final palette = context.palette;
    final accent = trackerColor(tracker.colorValue);
    final text = context.text;
    final needsNumber =
        tracker.type == TrackerType.count ||
        tracker.type == TrackerType.number ||
        tracker.type == TrackerType.duration ||
        tracker.type == TrackerType.event;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          leading: IconBadge(
            icon: trackerIcon(tracker.icon),
            color: accent,
            size: 44,
            iconSize: 22,
          ),
          title: tracker.name,
          subtitle: tracker.target == null ? null : tracker.targetLabel,
        ),
        if (tracker.type == TrackerType.boolean)
          Row(
            children: [
              for (final option in const [true, false]) ...[
                if (!option) const SizedBox(width: Insets.md),
                Expanded(
                  child: Pressable(
                    haptic: true,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    onTap: () => setState(() => _boolValue = option),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _boolValue == option
                            ? (option ? accent : const Color(0xFF8E96B3))
                                  .withValues(alpha: 0.18)
                            : palette.subtle,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        border: Border.all(
                          color: _boolValue == option
                              ? (option ? accent : const Color(0xFF8E96B3))
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        option ? 'Yes' : 'No',
                        style: text.titleMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        if (needsNumber) ...[
          Row(
            children: [
              if (tracker.type == TrackerType.count)
                IconButton.filledTonal(
                  onPressed: () => _bump(-1),
                  icon: const Icon(Icons.remove_rounded),
                ),
              Expanded(
                child: TextField(
                  controller: _valueController,
                  autofocus: tracker.type != TrackerType.count,
                  textAlign: TextAlign.center,
                  style: text.headlineMedium?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '0',
                    suffixText: tracker.type == TrackerType.duration
                        ? 'min'
                        : (tracker.unit.trim().isEmpty ? null : tracker.unit),
                  ),
                ),
              ),
              if (tracker.type == TrackerType.count)
                IconButton.filledTonal(
                  onPressed: () => _bump(1),
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
          if (tracker.type == TrackerType.duration) ...[
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final minutes in const [5, 10, 15, 30, 45, 60])
                  ActionChip(
                    label: Text('$minutes min'),
                    onPressed: () => setState(
                      () => _valueController.text = '$minutes',
                    ),
                  ),
              ],
            ),
          ],
        ],
        if (tracker.type == TrackerType.text)
          TextField(
            controller: _textController,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Write a short note'),
          ),
        if (tracker.type == TrackerType.rating)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                Pressable(
                  scale: 0.85,
                  haptic: true,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: () => setState(() => _rating = i),
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.sm),
                    child: AnimatedScale(
                      scale: i <= _rating ? 1.0 : 0.86,
                      duration: Motion.base,
                      curve: Motion.spring,
                      child: Icon(
                        i <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 40,
                        color: i <= _rating
                            ? context.scheme.secondary
                            : palette.dimText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: Insets.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _more = !_more),
            icon: AnimatedRotation(
              turns: _more ? 0.5 : 0,
              duration: Motion.base,
              child: const Icon(Icons.expand_more_rounded, size: 20),
            ),
            label: Text(_more ? 'Less' : 'Note or time'),
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: !_more
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tracker.type != TrackerType.count && tracker.type != TrackerType.event)
                      TextField(
                        controller: _countController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Count/times (optional)',
                          hintText: 'e.g. 2',
                          prefixIcon: Icon(Icons.tag_rounded, size: 18),
                        ),
                      ),
                    if (tracker.type != TrackerType.count && tracker.type != TrackerType.event)
                      const SizedBox(height: Insets.sm),
                    Text(
                      'Time & duration',
                      style: context.text.labelMedium?.copyWith(
                        color: context.palette.mutedText,
                      ),
                    ),
                    const SizedBox(height: Insets.xs),
                    Row(
                      children: [
                        Expanded(
                          child: _TimePickButton(
                            label: 'From',
                            value: _startedAt,
                            onTap: () => _pickRangeTime(isStart: true),
                            onClear: _startedAt == null
                                ? null
                                : () => setState(() {
                                      _startedAt = null;
                                      if (_endedAt == null) _durationController.clear();
                                    }),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Expanded(
                          child: _TimePickButton(
                            label: 'To',
                            value: _endedAt,
                            onTap: () => _pickRangeTime(isStart: false),
                            onClear: _endedAt == null
                                ? null
                                : () => setState(() {
                                      _endedAt = null;
                                      if (_startedAt == null) _durationController.clear();
                                    }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _durationController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Duration (minutes)',
                              hintText: 'e.g. 16',
                              prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                              suffixText: 'min',
                              helperText: _startedAt != null || _endedAt != null
                                  ? 'Set minutes to auto-calc the other time'
                                  : 'Optional. You can also set From/To times',
                            ),
                            onChanged: (_) => setState(_syncRangeFromDuration),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        IconButton.filledTonal(
                          tooltip: 'Set duration',
                          onPressed: _setDurationByPicker,
                          icon: const Icon(Icons.timelapse_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final m in const [5, 10, 15, 16, 30, 45, 60])
                          ActionChip(
                            label: Text('$m min'),
                            onPressed: () => setState(() {
                              _setDurationMinutes(m.toDouble());
                              _syncRangeFromDuration();
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    TextField(
                      controller: _noteController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Add a note',
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    Pressable(
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: _pickWhen,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Insets.sm,
                          horizontal: Insets.xs,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 18,
                              color: palette.mutedText,
                            ),
                            const SizedBox(width: Insets.sm),
                            Text(
                              '${formatDayLong(_when)}, ${formatTime(_when)}',
                              style: text.bodySmall,
                            ),
                            const Spacer(),
                            Text(
                              'Logged time',
                              style: text.labelMedium?.copyWith(
                                color: context.scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: Insets.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(
              _busy
                  ? 'Saving'
                  : widget.editing == null
                  ? 'Log'
                  : 'Save',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted) return;
    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  double? get _enteredDurationMinutes {
    final t = _durationController.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _setDurationMinutes(double minutes, {bool fromRange = false}) {
    final m = minutes < 0 ? 0 : minutes;
    final text = formatCompactNumber(m);
    _durationController.text = text;
    if (widget.tracker.type == TrackerType.duration) {
      _valueController.text = text;
    } else if (!fromRange && widget.tracker.type == TrackerType.event) {
      // keep event value independent unless user wants it; do not override
    }
  }

  void _syncRangeFromDuration() {
    final mins = _enteredDurationMinutes ??
        (widget.tracker.type == TrackerType.duration
            ? double.tryParse(_valueController.text.trim().replaceAll(',', '.'))
            : null);
    if (mins == null) return;
    final whole = mins.round();
    if (_startedAt != null && _endedAt == null) {
      _endedAt = _startedAt!.add(Duration(minutes: whole));
    } else if (_startedAt == null && _endedAt != null) {
      _startedAt = _endedAt!.subtract(Duration(minutes: whole));
    } else if (_startedAt != null && _endedAt != null) {
      // if user adjusted duration while both set, move end time from start
      _endedAt = _startedAt!.add(Duration(minutes: whole));
    }
  }

  Future<void> _pickRangeTime({required bool isStart}) async {
    final base = (isStart ? _startedAt : _endedAt) ?? _when;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _startedAt = picked;
      } else {
        _endedAt = picked;
      }
      if (_startedAt != null && _endedAt != null) {
        final diff = _endedAt!.difference(_startedAt!).inMinutes.toDouble();
        if (diff >= 0) {
          _setDurationMinutes(diff, fromRange: true);
        }
      } else {
        _syncRangeFromDuration();
      }
    });
  }

  Future<void> _setDurationByPicker() async {
    final current = (_enteredDurationMinutes ??
            (widget.tracker.type == TrackerType.duration
                ? double.tryParse(_valueController.text.trim().replaceAll(',', '.'))
                : null) ??
            0)
        .round();
    final controller = TextEditingController(text: current <= 0 ? '' : '$current');
    final mins = await showLifelogSheet<int>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Set duration',
            subtitle: 'Enter minutes, or pick a quick value',
          ),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Minutes',
              hintText: '16',
              suffixText: 'min',
            ),
          ),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final m in const [5, 10, 15, 16, 20, 30, 45, 60, 90])
                ActionChip(
                  label: Text('$m min'),
                  onPressed: () => Navigator.of(ctx).pop(m),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null) return;
                Navigator.of(ctx).pop(v);
              },
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (mins == null || !mounted) return;
    setState(() {
      _setDurationMinutes(mins.toDouble());
      _syncRangeFromDuration();
    });
  }

  Future<void> _save() async {
    final tracker = widget.tracker;
    double? value;
    var text = '';
    switch (tracker.type) {
      case TrackerType.boolean:
        value = _boolValue ? 1 : 0;
      case TrackerType.rating:
        value = _rating.toDouble();
      case TrackerType.text:
        text = _textController.text.trim();
        if (text.isEmpty) {
          showSnack(context, 'Write a short note first.');
          return;
        }
      case TrackerType.count:
      case TrackerType.number:
      case TrackerType.duration:
      case TrackerType.event:
        value = double.tryParse(_valueController.text.trim().replaceAll(',', '.'));
        if (value == null) {
          showSnack(context, 'Enter a valid number.');
          return;
        }
    }

    final note = _noteController.text.trim();
    final durText = _durationController.text.trim().replaceAll(',', '.');
    double? durationMinutes = durText.isEmpty ? null : double.tryParse(durText);
    final countText = _countController.text.trim().replaceAll(',', '.');
    double? count = countText.isEmpty ? null : double.tryParse(countText);
    if (countText.isNotEmpty && count == null) {
      showSnack(context, 'Enter a valid count.');
      return;
    }
    DateTime? startedAt = _startedAt;
    DateTime? endedAt = _endedAt;
    if (startedAt != null && endedAt != null) {
      final diff = endedAt.difference(startedAt).inMinutes.toDouble();
      if (diff < 0) {
        showSnack(context, 'End time must be after start time.');
        return;
      }
      durationMinutes ??= diff;
    }
    if (tracker.type == TrackerType.duration) {
      durationMinutes = value;
    }
    final recordedAt = startedAt ?? _when;

    setState(() => _busy = true);
    final controller = ref.read(archiveProvider.notifier);
    try {
      if (widget.editing != null) {
        await controller.updateRecord(
          widget.editing!.copyWith(
            recordedAt: recordedAt,
            value: value,
            text: text,
            note: note,
            startedAt: startedAt,
            clearStartedAt: startedAt == null,
            endedAt: endedAt,
            clearEndedAt: endedAt == null,
            durationMinutes: durationMinutes,
            clearDurationMinutes: durationMinutes == null,
            count: count,
            clearCount: count == null,
          ),
        );
      } else {
        await controller.logTracker(
          tracker,
          value: value,
          text: text,
          note: note,
          at: recordedAt,
          startedAt: startedAt,
          endedAt: endedAt,
          durationMinutes: durationMinutes,
          count: count,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Could not save: $error');
        setState(() => _busy = false);
      }
    }
  }
}

class _TimePickButton extends StatelessWidget {
  const _TimePickButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 10),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null ? '$label: --:--' : '$label: ${formatTime(value!)}',
              style: context.text.bodySmall,
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close_rounded, size: 16, color: palette.mutedText),
            ),
        ],
      ),
    );
  }
}

Future<TrackerDefinition?> showTrackerEditor(
  BuildContext context,
  WidgetRef ref, {
  TrackerDefinition? existing,
  String? initialName,
  TrackerType? initialType,
}) async {
  final saved = await showLifelogSheet<TrackerDefinition>(
    context,
    builder: (_) => _TrackerEditorSheet(
      existing: existing,
      initialName: initialName,
      initialType: initialType,
    ),
  );
  if (saved == null) return null;
  if (!context.mounted) return saved;
  await guard(
    context,
    ref.read(archiveProvider.notifier).saveTracker(saved),
    errorPrefix: 'Could not save tracker',
  );
  return saved;
}

class _TrackerEditorSheet extends ConsumerStatefulWidget {
  const _TrackerEditorSheet({
    this.existing,
    this.initialName,
    this.initialType,
  });

  final TrackerDefinition? existing;
  final String? initialName;
  final TrackerType? initialType;

  @override
  ConsumerState<_TrackerEditorSheet> createState() =>
      _TrackerEditorSheetState();
}

class _TrackerEditorSheetState extends ConsumerState<_TrackerEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _unitController;
  late final TextEditingController _targetController;
  late TrackerType _type;
  late String _icon;
  late int _color;
  late bool _multiplePerDay;
  bool _customize = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(
      text: existing?.name ?? widget.initialName ?? '',
    );
    _categoryController = TextEditingController(
      text: existing?.category ?? 'Personal',
    );
    _unitController = TextEditingController(text: existing?.unit ?? '');
    _targetController = TextEditingController(
      text: existing?.target == null
          ? ''
          : formatCompactNumber(existing!.target!),
    );
    _type = existing?.type ?? widget.initialType ?? TrackerType.boolean;
    _icon = existing?.icon ?? 'circle';
    _color = existing?.colorValue ?? trackerColorChoices.first;
    _multiplePerDay = existing?.multiplePerDay ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _unitController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = trackerColor(_color);
    final needsUnit =
        _type == TrackerType.number || _type == TrackerType.duration;
    final supportsTarget =
        _type == TrackerType.count ||
        _type == TrackerType.number ||
        _type == TrackerType.duration;

    Widget label(String value) => Padding(
      padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
      child: Text(
        value,
        style: context.text.labelMedium?.copyWith(color: palette.mutedText),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: widget.existing == null ? 'New activity' : 'Edit activity',
          leading: IconBadge(
            icon: trackerIcon(_icon),
            color: accent,
            size: 44,
            iconSize: 22,
          ),
        ),
        TextField(
          controller: _nameController,
          autofocus: widget.existing == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Shower, reading, workout, water'),
        ),
        label('Track as'),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final type in TrackerType.values)
              ChoiceChip(
                avatar: Icon(
                  trackerTypeIcon(type),
                  size: 16,
                  color: _type == type ? accent : palette.mutedText,
                ),
                label: Text(type.label),
                selected: _type == type,
                showCheckmark: false,
                selectedColor: accent.withValues(alpha: 0.16),
                onSelected: (_) => setState(() => _type = type),
              ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _customize = !_customize),
            icon: AnimatedRotation(
              turns: _customize ? 0.5 : 0,
              duration: Motion.base,
              child: const Icon(Icons.expand_more_rounded, size: 20),
            ),
            label: Text(_customize ? 'Hide options' : 'Customize'),
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: !_customize
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (supportsTarget) ...[
                      TextField(
                        controller: _targetController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Daily target',
                          hintText: '8',
                        ),
                      ),
                      const SizedBox(height: Insets.md),
                    ],
                    if (needsUnit) ...[
                      TextField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          hintText: 'pages, glasses',
                        ),
                      ),
                      const SizedBox(height: Insets.md),
                    ],
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(labelText: 'Group'),
                    ),
                    label('Icon'),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final icon in trackerIconChoices)
                          Pressable(
                            borderRadius: BorderRadius.circular(Radii.sm),
                            onTap: () => setState(() => _icon = icon),
                            child: AnimatedContainer(
                              duration: Motion.fast,
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _icon == icon
                                    ? accent.withValues(alpha: 0.16)
                                    : palette.subtle,
                                borderRadius: BorderRadius.circular(Radii.sm),
                                border: Border.all(
                                  color: _icon == icon
                                      ? accent
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                trackerIcon(icon),
                                size: 19,
                                color: _icon == icon
                                    ? accent
                                    : palette.mutedText,
                              ),
                            ),
                          ),
                      ],
                    ),
                    label('Colour'),
                    Wrap(
                      spacing: Insets.md,
                      runSpacing: Insets.sm,
                      children: [
                        for (final color in trackerColorChoices)
                          Pressable(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            scale: 0.9,
                            onTap: () => setState(() => _color = color),
                            child: AnimatedContainer(
                              duration: Motion.fast,
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: trackerColor(color),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _color == color
                                      ? context.scheme.onSurface
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _multiplePerDay,
                      onChanged: (value) =>
                          setState(() => _multiplePerDay = value),
                      title: const Text('Log more than once a day'),
                      subtitle: const Text('Each log can have its own time or duration.'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: Insets.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _save,
            child: Text(widget.existing == null ? 'Add activity' : 'Save'),
          ),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Give the activity a name.');
      return;
    }
    final targetText = _targetController.text.trim();
    final target = targetText.isEmpty ? null : double.tryParse(targetText);
    if (targetText.isNotEmpty && target == null) {
      showSnack(context, 'The target must be a number.');
      return;
    }
    final existing = widget.existing;
    final tracker = TrackerDefinition(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      type: _type,
      createdAt: existing?.createdAt ?? DateTime.now(),
      icon: _icon,
      colorValue: _color,
      category: _categoryController.text.trim().isEmpty
          ? 'Personal'
          : _categoryController.text.trim(),
      unit: _unitController.text.trim(),
      target: _type == TrackerType.boolean && target != null ? 1 : target,
      active: true,
      multiplePerDay: _multiplePerDay,
      sortOrder: existing?.sortOrder ?? 0,
    );
    Navigator.of(context).pop(tracker);
  }
}
