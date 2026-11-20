import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import 'photo_widgets.dart';

/// Outcome of one batch import. Counts are based on what was actually written,
/// never on how many files were picked.
class MediaImportSummary {
  const MediaImportSummary({
    required this.total,
    required this.added,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int added;
  final int skipped;
  final int failed;

  bool get isEmpty => added == 0 && skipped == 0 && failed == 0;

  String get message {
    final parts = <String>[];
    if (added > 0) parts.add('$added ${added == 1 ? 'item' : 'items'} added');
    if (skipped > 0) parts.add('$skipped skipped');
    if (failed > 0) parts.add('$failed failed');
    if (parts.isEmpty) return 'Nothing imported.';
    return '${parts.join(', ')}.';
  }
}

enum _ItemState { pending, reading, details, saving, added, skipped, failed }

class _ItemProgress {
  const _ItemProgress(this.name, this.state);
  final String name;
  final _ItemProgressState state;
}

class _ItemProgressState {
  const _ItemProgressState(this.state, [this.detail = '']);
  final _ItemState state;
  final String detail;
}

/// Imports picked media one at a time with a visible per-item list, plus real
/// Skip all / Cancel controls. Works for both day-scoped and entry-scoped adds.
Future<MediaImportSummary> importPickedMedia(
  BuildContext context,
  WidgetRef ref,
  List<XFile> files, {
  String? journalEntryId,
  DateTime? createdAt,
}) async {
  final total = files.length;
  final items = ValueNotifier<List<_ItemProgress>>([
    for (final file in files)
      _ItemProgress(file.name, const _ItemProgressState(_ItemState.pending)),
  ]);
  var dialogOpen = true;
  var skipAll = false;
  var cancelAll = false;
  var added = 0;
  var skipped = 0;
  var failed = 0;

  void setItem(int index, _ItemState state, [String detail = '']) {
    final current = List<_ItemProgress>.from(items.value);
    current[index] = _ItemProgress(current[index].name, _ItemProgressState(state, detail));
    items.value = current;
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<List<_ItemProgress>>(
          valueListenable: items,
          builder: (context, progress, _) {
            final done = progress
                .where((p) => p.state.state == _ItemState.added ||
                    p.state.state == _ItemState.skipped ||
                    p.state.state == _ItemState.failed)
                .length;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Adding media', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '$done of $total complete',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: total == 0 ? null : (done / total).clamp(0.0, 1.0),
                ),
                const SizedBox(height: Insets.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < progress.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StateIcon(state: progress[i].state.state),
                                const SizedBox(width: Insets.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        progress[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      if (progress[i].state.detail.isNotEmpty)
                                        Text(
                                          progress[i].state.detail,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          skipAll = true;
                          for (var i = 0; i < items.value.length; i++) {
                            if (_isActive(items.value[i].state.state)) {
                              setItem(i, _ItemState.skipped, 'Skipped');
                            }
                          }
                        },
                        child: const Text('Skip all'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          cancelAll = true;
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  try {
    for (var i = 0; i < files.length; i++) {
      if (skipAll || cancelAll) break;
      final file = files[i];
      setItem(i, _ItemState.reading, 'Reading');
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        failed++;
        setItem(i, _ItemState.failed, 'Could not read: $e');
        continue;
      }
      if (skipAll || cancelAll || !context.mounted) break;

      setItem(i, _ItemState.details, 'Waiting for details');
      final details = await askMediaDetails(context, fileName: file.name);
      if (details == null || !context.mounted) {
        skipped++;
        setItem(i, _ItemState.skipped, 'Skipped');
        continue;
      }
      switch (details.action) {
        case MediaDetailsAction.skipAll:
          skipAll = true;
          skipped++;
          setItem(i, _ItemState.skipped, 'Skipped');
          continue;
        case MediaDetailsAction.cancel:
          cancelAll = true;
          skipped++;
          setItem(i, _ItemState.skipped, 'Skipped');
          continue;
        case MediaDetailsAction.skip:
          skipped++;
          setItem(i, _ItemState.skipped, 'Skipped');
          continue;
        case MediaDetailsAction.add:
          break;
      }

      setItem(i, _ItemState.saving, 'Encrypting and saving');
      try {
        await ref.read(archiveProvider.notifier).importMedia(
              bytes: bytes,
              fileName: file.name,
              caption: details.caption,
              tags: details.tags,
              journalEntryId: journalEntryId,
              createdAt: createdAt,
            );
        added++;
        setItem(i, _ItemState.added, 'Added');
      } catch (e) {
        failed++;
        setItem(i, _ItemState.failed, 'Could not save: $e');
      }
    }
  } finally {
    if (dialogOpen) navigator.pop();
    dialogOpen = false;
    items.dispose();
  }

  final summary = MediaImportSummary(
    total: total,
    added: added,
    skipped: skipped,
    failed: failed,
  );
  if (context.mounted) showSnack(context, summary.message);
  return summary;
}

bool _isActive(_ItemState state) =>
    state == _ItemState.pending ||
    state == _ItemState.reading ||
    state == _ItemState.details ||
    state == _ItemState.saving;

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});
  final _ItemState state;

  @override
  Widget build(BuildContext context) {
    final size = const SizedBox(width: 18, height: 18);
    return switch (state) {
      _ItemState.added => SizedBox(
          width: 18,
          height: 18,
          child: Icon(Icons.check_circle_rounded,
              size: 18, color: Theme.of(context).colorScheme.primary),
        ),
      _ItemState.failed => SizedBox(
          width: 18,
          height: 18,
          child: Icon(Icons.error_outline_rounded,
              size: 18, color: Theme.of(context).colorScheme.error),
        ),
      _ItemState.skipped => SizedBox(
          width: 18,
          height: 18,
          child: Icon(Icons.remove_circle_outline,
              size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      _ItemState.saving ||
      _ItemState.reading ||
      _ItemState.details =>
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      _ItemState.pending => size,
    };
  }
}
