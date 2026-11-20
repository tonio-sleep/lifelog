import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/meals.dart';
import 'meal_widgets.dart' show mealAccent, mealIcon;

/// Capture a meal, drink or snack as its own record, never as a habit.
Future<void> showMealEditor(
  BuildContext context,
  WidgetRef ref,
  DateTime day, {
  MealRecord? existing,
}) async {
  await showLifelogSheet<bool>(
    context,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => _MealEditorSheet(
      sheetContext: sheetContext,
      ref: ref,
      day: dayStart(day),
      existing: existing,
    ),
  );
}

/// Full list for one day, used from the "See all" action on the compact card.
Future<void> showMealsForDay(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) async {
  await showLifelogSheet<void>(
    context,
    builder: (sheetContext) => _MealDaySheet(
      sheetContext: sheetContext,
      ref: ref,
      day: dayStart(day),
    ),
  );
}

class _MealEditorSheet extends ConsumerStatefulWidget {
  const _MealEditorSheet({
    required this.sheetContext,
    required this.ref,
    required this.day,
    this.existing,
  });

  final BuildContext sheetContext;
  final WidgetRef ref;
  final DateTime day;
  final MealRecord? existing;

  @override
  ConsumerState<_MealEditorSheet> createState() => _MealEditorSheetState();
}

class _MealEditorSheetState extends ConsumerState<_MealEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _amount;
  late final TextEditingController _unit;
  late final TextEditingController _tags;
  late MealKind _kind;
  late DateTime _at;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _amount = TextEditingController(
      text: existing?.amount == null ? '' : '${existing!.amount}',
    );
    _unit = TextEditingController(text: existing?.unit ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _kind = existing?.kind ?? MealKind.meal;
    _at = existing?.at ?? momentForDay(widget.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _amount.dispose();
    _unit.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: widget.sheetContext,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _at = DateTime(
        _at.year,
        _at.month,
        _at.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);

    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    final existing = widget.existing;
    final meal = existing == null
        ? MealRecord.create(
            at: _at,
            kind: _kind,
            name: name,
            notes: _notes.text,
            amount: amount,
            unit: _unit.text,
            tags: _tags.text.split(','),
          )
        : existing.copyWith(
            at: _at,
            kind: _kind,
            name: name,
            notes: _notes.text.trim(),
            amount: amount,
            clearAmount: amount == null,
            unit: _unit.text.trim(),
            tags: _tags.text.split(','),
          );

    await widget.ref.read(archiveProvider.notifier).saveMeal(meal);
    if (widget.sheetContext.mounted) {
      Navigator.of(widget.sheetContext).pop(true);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await confirm(
      widget.sheetContext,
      title: 'Delete this meal?',
      message: '${existing.name} will be removed from this day.',
    );
    if (!ok) return;
    await widget.ref.read(archiveProvider.notifier).deleteMeal(existing.id);
    if (widget.sheetContext.mounted) {
      Navigator.of(widget.sheetContext).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final accent = mealAccent(_kind, context.scheme, palette);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: _isEditing ? 'Edit food or drink' : 'Log food or drink',
          subtitle: relativeDayLabel(widget.day),
        ),
        Wrap(
          spacing: Insets.sm,
          children: [
            for (final kind in MealKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
            labelText: 'What did you have?',
            hintText: switch (_kind) {
              MealKind.meal => 'e.g. Oatmeal with berries and eggs',
              MealKind.drink => 'e.g. Coffee, green tea, water',
              MealKind.snack => 'e.g. Apple and almonds',
            },
            prefixIcon: Icon(mealIcon(_kind), color: accent, size: 20),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onEditingComplete: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Amount (optional)',
                  hintText: '1',
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: TextField(
                controller: _unit,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onEditingComplete: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  hintText: 'bowl, ml, glass',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Where, with whom, how it felt…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _tags,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onEditingComplete: () =>
              FocusManager.instance.primaryFocus?.unfocus(),
          decoration: const InputDecoration(
            labelText: 'Tags (optional)',
            hintText: 'home, vegetarian, takeout',
          ),
        ),
        const SizedBox(height: Insets.md),
        InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: _pickTime,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, size: 18, color: accent),
                const SizedBox(width: Insets.sm),
                Text('When', style: text.bodyMedium),
                const Spacer(),
                Text(
                  formatTime(_at),
                  style: text.labelLarge?.copyWith(
                    color: accent,
                    fontFeatures: tabularFigures,
                  ),
                ),
                const SizedBox(width: Insets.xs),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: palette.dimText),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            if (_isEditing)
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: context.scheme.error),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(widget.sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: Insets.xs),
            FilledButton(
              onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Log meal'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MealDaySheet extends ConsumerWidget {
  const _MealDaySheet({
    required this.sheetContext,
    required this.ref,
    required this.day,
  });

  final BuildContext sheetContext;
  final WidgetRef ref;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final archive = ref.watch(archiveProvider);
    final meals = archive.mealsOn(day);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: 'Meals and drinks',
          subtitle: formatDayLong(day),
        ),
        if (meals.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.lg),
            child: Text(
              'Nothing logged for this day yet.',
              style: context.text.bodyMedium?.copyWith(
                color: palette.mutedText,
              ),
            ),
          )
        else
          for (final meal in meals)
            _MealListRow(
              meal: meal,
              onTap: () => showMealEditor(
                sheetContext,
                ref,
                day,
                existing: meal,
              ),
            ),
        const SizedBox(height: Insets.md),
        FilledButton.icon(
          onPressed: () => showMealEditor(sheetContext, ref, day),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add meal, drink or snack'),
        ),
      ],
    );
  }
}

class _MealListRow extends StatelessWidget {
  const _MealListRow({required this.meal, required this.onTap});

  final MealRecord meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = mealAccent(meal.kind, context.scheme, palette);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          children: [
            IconBadge(icon: mealIcon(meal.kind), color: accent, size: 38),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      meal.kind.label,
                      meal.amountLabel,
                      if (meal.notes.trim().isNotEmpty) meal.notes.trim(),
                    ].where((value) => value.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.sm),
            Text(
              meal.timeLabel,
              style: context.text.labelSmall?.copyWith(
                color: palette.dimText,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
