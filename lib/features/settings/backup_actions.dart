import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';

const _backupTypes = <XTypeGroup>[
  XTypeGroup(label: 'Lifelog backup', extensions: <String>['lifelog']),
];

/// Creates a passphrase-encrypted backup (including media) and lets the user choose\n/// where to save it. Everything in the backup is encrypted with the passphrase.
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  final services = ref.read(appServicesProvider);
  final passphrase = await _askBackupPassphrase(context);
  if (passphrase == null) return;
  if (!context.mounted) return;

  final bytes = await guard(
    context,
    services.backup.createBackup(\n      archive: ref.read(archiveProvider),\n      passphrase: passphrase,\n      mediaStore: services.mediaStore,\n    ),
    errorPrefix: 'Could not create the backup',
  );
  if (bytes == null) return;

  final suggestedName = 'lifelog-backup-${dayKey(DateTime.now())}.lifelog';
  String? savedPath;

  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    // Save to app Documents so it is visible in the Files app / device storage.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Backups'));
    await dir.create(recursive: true);
    savedPath = p.join(dir.path, suggestedName);
    if (!context.mounted) return;
    final written = await guard(
      context,
      File(savedPath).writeAsBytes(bytes, flush: true),
      errorPrefix: 'Could not write the backup file',
    );
    if (written == null) return;
  } else {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: _backupTypes,
    );
    if (location == null) return;
    if (!context.mounted) return;
    savedPath = location.path;
    final written = await guard(
      context,
      File(savedPath).writeAsBytes(bytes, flush: true),
      errorPrefix: 'Could not write the backup file',
    );
    if (written == null) return;
  }

  await ref.read(settingsProvider.notifier).markBackup(DateTime.now());
  if (!context.mounted) return;

  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    final share = await confirm(
      context,
      title: 'Backup saved',
      message:
          'Encrypted backup saved and visible in the Files app (On My iPhone/iPad > Lifelog > Backups).\n\n$savedPath\n\nShare it now? Keep the passphrase safe: it cannot be recovered.',
      confirmLabel: 'Share',
      cancelLabel: 'Done',
    );
    if (share) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(savedPath)],
          text: 'Lifelog encrypted backup',
        ),
      );
    }
  } else {
    showSnack(
      context,
      'Encrypted backup written. Keep the passphrase safe: it cannot be recovered.',
    );
  }
}

/// Links a folder (e.g. a synced or cloud folder) for saving backups.
Future<void> linkBackupFolder(BuildContext context, WidgetRef ref) async {
  String? path;
  if (!kIsWeb && Platform.isIOS) {
    // On iOS, default to the app's visible Documents/Backups folder (Files app).
    final visible = await visibleExportsFolderPath();
    if (!context.mounted) return;
    final useVisible = await confirm(
      context,
      title: 'Backup folder',
      message:
          'Use the app\'s folder visible in the Files app?\n\n$visible\n\nChoose "Pick another" to select a different folder.',
      confirmLabel: 'Use this folder',
      cancelLabel: 'Pick another',
    );
    if (!context.mounted) return;
    if (useVisible) {
      path = visible;
    } else {
      path = await getDirectoryPath(confirmButtonText: 'Use this folder');
    }
  } else {
    path = await getDirectoryPath(confirmButtonText: 'Use this folder');
  }
  if (path == null) return;
  if (!context.mounted) return;
  await guard(
    context,
    ref.read(settingsProvider.notifier).setBackupFolderPath(path),
    errorPrefix: 'Could not link folder',
  );
  if (context.mounted) {
    showSnack(context, 'Linked backup folder: $path');
  }
}

/// Saves an encrypted backup directly into the linked folder.
Future<void> saveBackupToLinkedFolder(BuildContext context, WidgetRef ref) async {
  var folder = ref.read(settingsProvider).backupFolderPath;
  if (folder == null || folder.trim().isEmpty) {
    if (context.mounted) {
      showSnack(context, 'Link a folder first (e.g. a synced or cloud folder).');
    }
    return;
  }
  final dir = Directory(folder);
  if (!await dir.exists()) {
    if (context.mounted) {
      showSnack(context, 'Linked folder not found. Please link it again.');
    }
    return;
  }

  final services = ref.read(appServicesProvider);
  final passphrase = await _askBackupPassphrase(context);
  if (passphrase == null) return;
  if (!context.mounted) return;

  final bytes = await guard(
    context,
    services.backup.createBackup(\n      archive: ref.read(archiveProvider),\n      passphrase: passphrase,\n      mediaStore: services.mediaStore,\n    ),
    errorPrefix: 'Could not create the backup',
  );
  if (bytes == null) return;

  final now = DateTime.now();
  final stamp = '${dayKey(now)}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  final filePath = p.join(folder, 'lifelog-backup-$stamp.lifelog');
  final written = await guard(
    context,
    File(filePath).writeAsBytes(bytes, flush: true),
    errorPrefix: 'Could not write the backup file',
  );
  if (written == null) return;

  await ref.read(settingsProvider.notifier).markBackup(DateTime.now());
  if (context.mounted) {
    showSnack(context, 'Backup saved to linked folder.');
  }
}

/// Returns the app's visible Documents folder path (shown in iOS Files app).
Future<String> visibleExportsFolderPath() async {
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Backups'));
    await dir.create(recursive: true);
    return dir.path;
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'Lifelog', 'Backups'));
  await dir.create(recursive: true);
  return dir.path;
}

/// Reads an encrypted backup, shows exactly what it contains, then replaces the
/// current archive only after an explicit confirmation.
Future<void> restoreBackup(BuildContext context, WidgetRef ref) async {
  final services = ref.read(appServicesProvider);
  final file = await openFile(acceptedTypeGroups: _backupTypes);
  if (file == null) return;
  if (!context.mounted) return;

  final passphrase = await _askPassphraseToOpen(context, fileName: file.name);
  if (passphrase == null) return;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  final contents = await guard(
    context,
    services.backup.readBackup(bytes: bytes, passphrase: passphrase),
    errorPrefix: 'Could not read the backup',
  );
  if (contents == null) return;
  if (!context.mounted) return;

  final counts = contents.counts;
  final mediaMsg = contents.includesMedia
      ? 'This backup includes encrypted media files and will restore them on this device.'
      : 'This backup does not include media files; existing media may be unavailable after restore.';
  final ok = await confirm(
    context,
    title: 'Replace this archive?',
    message:
        'The backup from ${formatDayLong(contents.createdAt)} contains '
        '${counts['journalEntries']} journal entries, '
        '${counts['photos']} media records, '
        '${counts['trackers']} trackers and '
        '${counts['scrobbles']} tracks.\n\n'
        '$mediaMsg\n\n'
        'Restoring replaces the current archive and media vault on this device. This cannot be undone.',
    confirmLabel: 'Restore backup',
  );
  if (!ok) return;
  if (!context.mounted) return;

  final restored = await guard(
    context,
    ref.read(archiveProvider.notifier).restoreArchive(
          contents.archive,
          mediaFiles: contents.mediaFiles,
        ),
    errorPrefix: 'Could not restore the archive',
  );
  if (restored == null) return;
  if (context.mounted) {
    showSnack(context, 'Archive restored from the encrypted backup.');
  }
}

Future<String?> _askBackupPassphrase(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PassphraseDialog(confirmNew: true),
  );
}

Future<String?> _askPassphraseToOpen(
  BuildContext context, {
  required String fileName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PassphraseDialog(
      confirmNew: false,
      title: 'Unlock backup',
      subtitle: 'Enter the passphrase used when $fileName was created.',
    ),
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.confirmNew,
    this.title,
    this.subtitle,
  });

  final bool confirmNew;
  final String? title;
  final String? subtitle;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pass = _pass.text;
    if (pass.trim().length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (widget.confirmNew && pass != _confirm.text) {
      setState(() => _error = 'The passphrases do not match.');
      return;
    }
    Navigator.of(context).pop(pass);
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    return AlertDialog(
      title: Text(widget.title ?? 'Backup passphrase'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle ??
                  'The backup is encrypted with Argon2id and AES-256-GCM. '
                      'There is no recovery: if you lose this passphrase, the '
                      'backup cannot be opened.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _pass,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              onSubmitted: widget.confirmNew ? null : (_) => _submit(),
            ),
            if (widget.confirmNew) ...[
              const SizedBox(height: Insets.md),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm passphrase',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmNew ? 'Create backup' : 'Open backup'),
        ),
      ],
    );
  }
}


