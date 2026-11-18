import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';
import '../../domain/models/music.dart';

Future<void> showManualScrobbleDialog(
  BuildContext context,
  WidgetRef ref, {
  DateTime? day,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ManualScrobbleDialog(day: day ?? DateTime.now()),
  );
}

class _ManualScrobbleDialog extends ConsumerStatefulWidget {
  const _ManualScrobbleDialog({required this.day});
  final DateTime day;

  @override
  ConsumerState<_ManualScrobbleDialog> createState() =>
      _ManualScrobbleDialogState();
}

class _ManualScrobbleDialogState extends ConsumerState<_ManualScrobbleDialog> {
  late final TextEditingController _artist;
  late final TextEditingController _title;
  late final TextEditingController _album;
  late DateTime _at;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _at = sameDay(widget.day, now)
        ? now
        : DateTime(widget.day.year, widget.day.month, widget.day.day, 12);
    _artist = TextEditingController();
    _title = TextEditingController();
    _album = TextEditingController();
  }

  @override
  void dispose() {
    _artist.dispose();
    _title.dispose();
    _album.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: const Text('Add a track'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _artist,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Artist'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Track title'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _album,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Album (optional)',
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
              Text(
                'Use this for a track you remember listening to. It stays in '
                'the encrypted archive just like imported scrobbles.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Add track'),
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

  Future<void> _save() async {
    final artist = _artist.text.trim();
    final title = _title.text.trim();
    if (artist.isEmpty || title.isEmpty) {
      showSnack(context, 'Enter both an artist and a track title.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(archiveProvider.notifier).addManualScrobble(
        MusicScrobble.manual(
          artist: artist,
          title: title,
          album: _album.text.trim(),
          playedAt: _at,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Could not save track: $error');
        setState(() => _busy = false);
      }
    }
  }
}
