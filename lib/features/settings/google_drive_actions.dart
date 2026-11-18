import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import 'google_sign_in_flow.dart';

Future<void> connectGoogleDrive(BuildContext context, WidgetRef ref) async {
  final existing = ref.read(settingsProvider);
  String clientId = (existing.googleClientId ?? '').trim();
  String clientSecret = (existing.googleClientSecret ?? '').trim();

  if (clientId.isEmpty) {
    final config = await _askGoogleClientConfig(
      context,
      initialId: clientId,
      initialSecret: clientSecret,
    );
    if (config == null) return;
    clientId = config.$1;
    clientSecret = config.$2;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).setGoogleClientConfig(
            clientId: clientId,
            clientSecret: clientSecret,
          ),
      errorPrefix: 'Could not save Google settings',
    );
    if (!context.mounted) return;
  }

  final services = ref.read(appServicesProvider);
  final result = await signInWithGoogle(
    context,
    service: services.googleDrive,
    clientId: clientId,
    clientSecret: clientSecret,
  );
  if (result == null || !context.mounted) return;

  await guard(
    context,
    ref.read(settingsProvider.notifier).saveGoogleAuth(
          accountEmail: result.accountEmail,
          authJson: result.authJson,
        ),
    errorPrefix: 'Could not save Google account',
  );
  if (!context.mounted) return;

  showSnack(context, 'Connected as ${result.accountEmail}.');

  final settings = ref.read(settingsProvider);
  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null || !context.mounted) return;
  final remote = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? clientId,
      clientSecret: settings.googleClientSecret ?? clientSecret,
      authJson: authJson,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not check Google Drive',
  );
  if (remote != null && context.mounted) {
    final doRestore = await showLifelogSheet<bool>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Backup found in Google Drive',
            subtitle: 'Restore your data to this device?',
          ),
          Text(
            remote.modifiedTime != null
                ? 'A synced backup was found (updated ${formatDayLong(remote.modifiedTime!)} ${formatTime(remote.modifiedTime!)}). Restoring replaces local data on this device with the cloud backup.'
                : 'A synced backup was found in your Google Drive. Restoring replaces local data on this device with the cloud backup.',
            style: ctx.text.bodyMedium?.copyWith(color: ctx.palette.mutedText),
          ),
          const SizedBox(height: Insets.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Restore'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (doRestore == true && context.mounted) {
      await restoreFromGoogleDrive(context, ref);
    }
  }
}

Future<void> disconnectGoogleDrive(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Disconnect Google Drive?'),
      content: const Text(
        'This removes the Google account connection from this device. '
        'Your backup in Google Drive is not deleted.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await guard(
    context,
    ref.read(settingsProvider.notifier).disconnectGoogleDrive(),
    errorPrefix: 'Could not disconnect',
  );
  if (context.mounted) showSnack(context, 'Google Drive disconnected.');
}

Future<void> syncToGoogleDrive(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  if (!settings.googleDriveConnected) {
    showSnack(context, 'Connect Google Drive first.');
    return;
  }
  final passphrase = await _askSyncPassphrase(context, title: 'Sync passphrase', confirm: true);
  if (passphrase == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final bytes = await guard<Uint8List>(
    context,
    services.backup.createBackup(
      archive: ref.read(archiveProvider),
      passphrase: passphrase,
    ),
    errorPrefix: 'Could not create backup',
  );
  if (bytes == null || !context.mounted) return;

  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null) {
    if (context.mounted) showSnack(context, 'Google session missing. Please sign in again.');
    return;
  }

  // find existing to update, or use stored id
  String? fileId = settings.googleDriveFileId;
  final existing = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: authJson,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not access Google Drive',
  );
  fileId = existing?.id ?? fileId;

  final latestAuth = await ref.read(settingsProvider.notifier).googleAuthJson() ?? authJson;
  final uploaded = await guard(
    context,
    services.googleDrive.uploadBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: latestAuth,
      bytes: bytes,
      existingFileId: fileId,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not upload to Google Drive',
  );
  if (uploaded == null || !context.mounted) return;

  await ref.read(settingsProvider.notifier).recordGoogleSync(
        DateTime.now(),
        driveFileId: uploaded.id,
      );
  await ref.read(settingsProvider.notifier).markBackup(DateTime.now());
  if (context.mounted) {
    showSnack(context, 'Synced to Google Drive. Keep your sync passphrase safe.');
  }
}

Future<void> restoreFromGoogleDrive(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  if (!settings.googleDriveConnected) {
    showSnack(context, 'Connect Google Drive first.');
    return;
  }
  final passphrase = await _askSyncPassphrase(context, title: 'Enter sync passphrase', confirm: false);
  if (passphrase == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null) {
    if (context.mounted) showSnack(context, 'Google session missing. Please sign in again.');
    return;
  }

  final remote = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: authJson,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not find backup in Google Drive',
  );
  if (remote == null) {
    if (context.mounted) showSnack(context, 'No synced backup found in Google Drive.');
    return;
  }
  if (!context.mounted) return;

  final latestAuth = await ref.read(settingsProvider.notifier).googleAuthJson() ?? authJson;
  final bytes = await guard<Uint8List>(
    context,
    services.googleDrive.downloadBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: latestAuth,
      fileId: remote.id,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not download from Google Drive',
  );
  if (bytes == null || !context.mounted) return;

  final contents = await guard(
    context,
    services.backup.readBackup(bytes: bytes, passphrase: passphrase),
    errorPrefix: 'Could not decrypt backup',
  );
  if (contents == null || !context.mounted) return;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore from Google Drive?'),
      content: Text(
        'This will replace the current archive on this device with the cloud backup '
        '(${contents.counts['journalEntries']} entries, ${contents.counts['photos']} media items metadata). '
        'Local data not in the backup will be lost.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  await guard(
    context,
    ref.read(archiveProvider.notifier).restoreArchive(contents.archive),
    errorPrefix: 'Could not restore archive',
  );
  await ref.read(settingsProvider.notifier).recordGoogleSync(DateTime.now(), driveFileId: remote.id);
  if (context.mounted) {
    showSnack(context, 'Restored data from Google Drive.');
  }
}

Future<(String, String)?> _askGoogleClientConfig(
  BuildContext context, {
  required String initialId,
  required String initialSecret,
}) async {
  final idController = TextEditingController(text: initialId);
  final secretController = TextEditingController(text: initialSecret);
  String? error;
  return showLifelogSheet<(String, String)>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final text = ctx.text;
        final palette = ctx.palette;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle(
              title: 'Connect Google Drive',
              subtitle: 'One-time setup to sign in and sync your data',
            ),
            Text(
              'Lifelog uses Google Drive (app data) to back up and restore your encrypted data. '
              'To sign in, enter your Google OAuth Client ID once. You can create a "Desktop app" client in Google Cloud Console with the Drive API enabled.',
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: idController,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'OAuth Client ID',
                hintText: 'xxxx.apps.googleusercontent.com',
                errorText: error,
              ),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: secretController,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Client secret (optional)',
                hintText: 'If your client type provides one',
              ),
            ),
            const SizedBox(height: Insets.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final id = idController.text.trim();
                  if (id.isEmpty) {
                    setModalState(() => error = 'Enter your OAuth Client ID to continue.');
                    return;
                  }
                  Navigator.pop(ctx, (id, secretController.text.trim()));
                },
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Continue to Google'),
              ),
            ),
            const SizedBox(height: Insets.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<String?> _askSyncPassphrase(
  BuildContext context, {
  required String title,
  required bool confirm,
}) async {
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This passphrase encrypts your cloud backup. You will need it to restore on another device. '
              'Media files are not included in this sync backup (text and records are synced).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: p1,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Passphrase', errorText: error),
              autofocus: true,
            ),
            if (confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: p2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm passphrase'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final a = p1.text;
              if (a.trim().length < 8) {
                setState(() => error = 'Use at least 8 characters.');
                return;
              }
              if (confirm && a != p2.text) {
                setState(() => error = 'Passphrases do not match.');
                return;
              }
              Navigator.pop(ctx, a);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
