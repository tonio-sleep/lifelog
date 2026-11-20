import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';
import '../../domain/models/timeline.dart';

Future<TimelineEvent?> showTimelineEventEditor(
  BuildContext context,
  WidgetRef ref, {
  TimelineEvent? existing,
  DateTime? initialDate,
  String dialogTitle = 'Add to timeline',
  String titleLabel = 'What happened?',
  String titleHint = 'Met a friend, finished a book, went for a walk...',
  String? prefillTitle,
}) async {
  final saved = await showDialog<TimelineEvent>(
    context: context,
    builder: (_) => _TimelineEventDialog(
      existing: existing,
      initialDate: initialDate,
      dialogTitle: dialogTitle,
      titleLabel: titleLabel,
      titleHint: titleHint,
      prefillTitle: prefillTitle,
    ),
  );
  if (saved == null) return null;
  if (!context.mounted) return saved;
  final savedOk = await guard<int>(
    context,
    ref.read(archiveProvider.notifier).saveEvent(saved).then((_) => 1),
    errorPrefix: 'Could not save event',
  );
  return savedOk == null ? null : saved;
}

class _TimelineEventDialog extends ConsumerStatefulWidget {
  const _TimelineEventDialog({
    this.existing,
    this.initialDate,
    this.dialogTitle = 'Add to timeline',
    this.titleLabel = 'What happened?',
    this.titleHint = 'Met a friend, finished a book, went for a walk...',
    this.prefillTitle,
  });
  final TimelineEvent? existing;
  final DateTime? initialDate;
  final String dialogTitle;
  final String titleLabel;
  final String titleHint;
  final String? prefillTitle;

  @override
  ConsumerState<_TimelineEventDialog> createState() =>
      _TimelineEventDialogState();
}

class _TimelineEventDialogState extends ConsumerState<_TimelineEventDialog> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _at;
  late bool _hidden;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = DateTime.now();
    final base = widget.initialDate ?? now;
    _at = existing?.occurredAt ??
        (sameDay(base, now)
            ? DateTime(base.year, base.month, base.day, now.hour, now.minute)
            : DateTime(base.year, base.month, base.day, 12));
    _title = TextEditingController(text: existing?.title ?? widget.prefillTitle ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _hidden = existing?.hidden ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? widget.dialogTitle : 'Edit event'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: widget.titleLabel,
                  hintText: widget.titleHint,
                ),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _notes,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onEditingComplete: () =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: Insets.md),
              InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: _pickTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: palette.mutedText,
                      ),
                      const SizedBox(width: Insets.sm),
                      Text(
                        '${formatDayLong(_at)} · ${formatTime(_at)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        'Change',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Insets.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _hidden,
                onChanged: (value) => setState(() => _hidden = value),
                title: const Text('Hide from the timeline'),
                subtitle: Text(
                  'The event stays in your archive but is not shown by default.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) {
              showSnack(context, 'Give the event a short title.');
              return;
            }
            final existing = widget.existing;
            Navigator.of(context).pop(
              TimelineEvent(
                id: existing?.id ?? TimelineEvent.blank(_at).id,
                title: title,
                occurredAt: _at,
                notes: _notes.text.trim(),
                hidden: _hidden,
              ),
            );
          },
          child: const Text('Save event'),
        ),
      ],
    );
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (!mounted) return;
    setState(() {
      _at = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _at.hour,
        time?.minute ?? _at.minute,
      );
    });
  }
}
