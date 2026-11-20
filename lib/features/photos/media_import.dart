import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import 'photo_widgets.dart';

/// Outcome of one batch import. Counts are derived from the final state of
/// each item, never from how many files were picked.
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

/// Imports picked media with visible per-item progress.
///
/// Details are collected first, one file at a time, and only then is the
/// modal progress dialog opened for the actual read/encrypt/save pass. Keeping
/// one modal surface on screen at a time avoids the previous failure where the
/// details sheet could be hidden behind the progress dialog and never return
/// an Add result.
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

  void setItem(int index, _ItemState state, [String detail = '']) {
    final current = List<_ItemProgress>.from(items.value);
    current[index] = _ItemProgress(
      current[index].name,
      _ItemProgressState(state, detail),
    );
    items.value = current;
  }

  void markSkipped(int index, [String detail = 'Skipped']) {
    if (_isDone(items.value[index].state.state)) return;
    setItem(index, _ItemState.skipped, detail);
  }

  void markAllActiveSkipped() {
    for (var i = 0; i < items.value.length; i++) {
      if (_isActive(items.value[i].state.state)) {
        markSkipped(i);
      }
    }
  }

  // Captions and tags are collected in pass 1 and consumed in pass 2.
  final captions = <int, String>{};
  final tags = <int, List<String>>{};

  // ---------------------------------------------------------------------------
  // Pass 1: collect caption/tags or an explicit Skip/Cancel for every file.
  // ---------------------------------------------------------------------------
  var stopDetails = false;
  for (var i = 0; i < files.length; i++) {
    if (stopDetails || !context.mounted) break;
    final file = files[i];
    setItem(i, _ItemState.details, 'Waiting for details');
    final details = await askMediaDetails(
      context,
      fileName: file.name,
      index: i + 1,
      total: total,
    );
    if (!context.mounted) {
      stopDetails = true;
      break;
    }
    if (details == null) {
      markSkipped(i, 'Skipped');
      continue;
    }
    switch (details.action) {
      case MediaDetailsAction.add:
        captions[i] = details.caption;
        tags[i] = details.tags;
        // Reset to pending so the save pass reports real progress for it.
        setItem(i, _ItemState.pending);
        break;
      case MediaDetailsAction.skip:
        markSkipped(i);
        break;
      case MediaDetailsAction.skipAll:
        markSkipped(i);
        markAllActiveSkipped();
        stopDetails = true;
        break;
      case MediaDetailsAction.cancel:
        markSkipped(i, 'Import cancelled');
        markAllActiveSkipped();
        stopDetails = true;
        break;
    }
  }

  if (stopDetails || !context.mounted) markAllActiveSkipped();

  final accepted = <int>[
    for (var i = 0; i < items.value.length; i++)
      if (items.value[i].state.state == _ItemState.pending) i,
  ];

  // ---------------------------------------------------------------------------
  // Pass 2: read, encrypt and save each accepted file with honest progress.
  // ---------------------------------------------------------------------------
  if (accepted.isNotEmpty && context.mounted) {
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    var skipAll = false;
    var cancelAll = false;
    var saveInFlight = false;

    void closeDialogIfIdle() {
      if (!dialogOpen || saveInFlight) return;
      dialogOpen = false;
      navigator.pop();
    }

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, _) {
          // A back gesture closes the progress UI and stops the import instead
          // of letting it continue invisibly. The explicit Cancel button does
          // the same thing without popping.
          if (didPop) dialogOpen = false;
        },
        child: AlertDialog(
          content: ValueListenableBuilder<List<_ItemProgress>>(
            valueListenable: items,
            builder: (context, progress, _) {
              final done = progress
                  .where((p) => _isDone(p.state.state))
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
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
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
                            markAllActiveSkipped();
                            closeDialogIfIdle();
                          },
                          child: const Text('Skip all'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            cancelAll = true;
                            markAllActiveSkipped();
                            // Nothing is being written: stop the UI now rather
                            // than waiting for the next loop iteration.
                            closeDialogIfIdle();
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
      for (final i in accepted) {
        if (!dialogOpen || skipAll || cancelAll || !context.mounted) break;
        if (_isDone(items.value[i].state.state)) continue;

        final file = files[i];
        setItem(i, _ItemState.reading, 'Reading');
        Uint8List bytes;
        try {
          // Copy the bytes so a platform-side buffer cannot be reused while
          // the details sheet/keyboard work finishes.
          bytes = Uint8List.fromList(await file.readAsBytes());
        } catch (e) {
          setItem(i, _ItemState.failed, 'Could not read: $e');
          continue;
        }
        if (!context.mounted) break;
        if (skipAll || cancelAll) {
          setItem(i, _ItemState.skipped, 'Skipped');
          continue;
        }

        setItem(i, _ItemState.saving, 'Encrypting and saving');
        saveInFlight = true;
        try {
          await ref.read(archiveProvider.notifier).importMedia(
                bytes: bytes,
                fileName: file.name,
                mimeType: file.mimeType,
                caption: (captions[i] ?? '').trim(),
                tags: tags[i] ?? const [],
                journalEntryId: journalEntryId,
                createdAt: createdAt,
              );
          // Cancel/skip can arrive while the encrypted write is in flight.
          // The bytes really were stored, so keep the honest "added" count but
          // explain why the loop stopped.
          final interrupted = cancelAll || skipAll || !dialogOpen;
          final detail = interrupted
              ? 'Added before ${cancelAll ? 'cancel' : 'skip'}'
              : 'Added';
          setItem(i, _ItemState.added, detail);
        } catch (e) {
          setItem(i, _ItemState.failed, 'Could not save: $e');
        } finally {
          saveInFlight = false;
          // If a cancel arrived mid-write, close as soon as it is safe.
          if (cancelAll || skipAll) closeDialogIfIdle();
        }
      }
    } finally {
      markAllActiveSkipped();
      if (dialogOpen) {
        dialogOpen = false;
        navigator.pop();
      }
      // Wait for the route to leave the tree before disposing the notifier it
      // is listening to; otherwise the exit animation can use a dead notifier.
      await dialogFuture;
    }
  }

  final states = items.value.map((item) => item.state.state).toList();
  final summary = MediaImportSummary(
    total: total,
    added: states.where((state) => state == _ItemState.added).length,
    skipped: states.where((state) => state == _ItemState.skipped).length,
    failed: states.where((state) => state == _ItemState.failed).length,
  );
  items.dispose();
  if (context.mounted) showSnack(context, summary.message);
  return summary;
}

bool _isActive(_ItemState state) =>
    state == _ItemState.pending ||
    state == _ItemState.reading ||
    state == _ItemState.details ||
    state == _ItemState.saving;

bool _isDone(_ItemState state) =>
    state == _ItemState.added ||
    state == _ItemState.skipped ||
    state == _ItemState.failed;

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
