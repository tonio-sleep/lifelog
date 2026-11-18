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
  final savedId = (existing.googleClientId ?? '').trim();
  final savedSecret = (existing.googleClientSecret ?? '').trim();

  final config = await _showGoogleConnectSheet(
    context,
    initialId: savedId,
    initialSecret: savedSecret,
    hasSavedConfig: savedId.isNotEmpty,
  );
  if (config == null || !context.mounted) return;

  final clientId = config.clientId.trim();
  final clientSecret = config.clientSecret.trim();
  if (clientId.isEmpty) {
    showSnack(context, 'Google sign-in is not configured yet.');
    return;
  }

  await guard(
    context,
    ref.read(settingsProvider.notifier).setGoogleClientConfig(
          clientId: clientId,
          clientSecret: clientSecret,
        ),
    errorPrefix: 'Could not save Google settings',
  );
  if (!context.mounted) return;

  final services = ref.read(appServicesProvider);
  final result = await guard(
    context,
    signInWithGoogle(
      context,
      service: services.googleDrive,
      clientId: clientId,
      clientSecret: clientSecret,
    ),
    errorPrefix: 'Could not sign in with Google',
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

  final settingsNow = ref.read(settingsProvider);
  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null || !context.mounted) return;
  final remote = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settingsNow.googleClientId ?? clientId,
      clientSecret: settingsNow.googleClientSecret ?? clientSecret,
      authJson: authJson,
      onRefreshed: (j) =>
          ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
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
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Disconnect'),
        ),
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
  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Sync passphrase',
    confirm: true,
  );
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
    if (context.mounted) {
      showSnack(context, 'Google session missing. Please sign in again.');
    }
    return;
  }

  String? fileId = settings.googleDriveFileId;
  final existing = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: authJson,
      onRefreshed: (j) =>
          ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not access Google Drive',
  );
  fileId = existing?.id ?? fileId;

  final latestAuth =
      await ref.read(settingsProvider.notifier).googleAuthJson() ?? authJson;
  final uploaded = await guard(
    context,
    services.googleDrive.uploadBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: latestAuth,
      bytes: bytes,
      existingFileId: fileId,
      onRefreshed: (j) =>
          ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
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
    showSnack(
      context,
      'Synced to Google Drive. Keep your sync passphrase safe.',
    );
  }
}

Future<void> restoreFromGoogleDrive(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  if (!settings.googleDriveConnected) {
    showSnack(context, 'Connect Google Drive first.');
    return;
  }
  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Enter sync passphrase',
    confirm: false,
  );
  if (passphrase == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null) {
    if (context.mounted) {
      showSnack(context, 'Google session missing. Please sign in again.');
    }
    return;
  }

  final remote = await guard(
    context,
    services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: authJson,
      onRefreshed: (j) =>
          ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    ),
    errorPrefix: 'Could not find backup in Google Drive',
  );
  if (remote == null) {
    if (context.mounted) {
      showSnack(context, 'No synced backup found in Google Drive.');
    }
    return;
  }
  if (!context.mounted) return;

  final latestAuth =
      await ref.read(settingsProvider.notifier).googleAuthJson() ?? authJson;
  final bytes = await guard<Uint8List>(
    context,
    services.googleDrive.downloadBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: latestAuth,
      fileId: remote.id,
      onRefreshed: (j) =>
          ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
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
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  await guard(
    context,
    ref.read(archiveProvider.notifier).restoreArchive(contents.archive),
    errorPrefix: 'Could not restore archive',
  );
  await ref.read(settingsProvider.notifier).recordGoogleSync(
        DateTime.now(),
        driveFileId: remote.id,
      );
  if (context.mounted) {
    showSnack(context, 'Restored data from Google Drive.');
  }
}

class _GoogleConnectConfig {
  const _GoogleConnectConfig({
    required this.clientId,
    required this.clientSecret,
  });
  final String clientId;
  final String clientSecret;
}

Future<_GoogleConnectConfig?> _showGoogleConnectSheet(
  BuildContext context, {
  String initialId = '',
  String initialSecret = '',
  bool hasSavedConfig = false,
}) async {
  final idController = TextEditingController(text: initialId);
  final secretController = TextEditingController(text: initialSecret);
  var showAdvanced = false;
  return showLifelogSheet<_GoogleConnectConfig>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final palette = ctx.palette;
        final text = ctx.text;
        final clientId = idController.text.trim();
        final canSignIn = clientId.isNotEmpty;
        if (hasSavedConfig && clientId.isNotEmpty) {
          // keep advanced collapsed by default when already configured
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle(
              title: 'Sign in with Google',
              subtitle:
                  'Back up and sync your encrypted data with Google Drive',
            ),
            _InfoLine(
              icon: Icons.lock_outline_rounded,
              text:
                  'Backups are encrypted before upload. Cloud sync does not include media file bytes.',
            ),
            const SizedBox(height: Insets.sm),
            _InfoLine(
              icon: Icons.open_in_new_rounded,
              text:
                  'A secure Google sign-in screen will open so you can choose your account and approve access.',
            ),
            const SizedBox(height: Insets.lg),
            if (canSignIn)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(
                    _GoogleConnectConfig(
                      clientId: idController.text,
                      clientSecret: secretController.text,
                    ),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Continue to Google sign-in'),
                ),
              )
            else
              QuietCard(
                color: palette.subtle.withValues(alpha: 0.7),
                padding: const EdgeInsets.all(Insets.md),
                child: Text(
                  'One-time setup is required before the secure Google sign-in screen can open on this device. '
                  'Open Setup details to add your app\'s Google OAuth client ID.',
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
              ),
            const SizedBox(height: Insets.sm),
            TextButton.icon(
              onPressed: () => setState(() => showAdvanced = !showAdvanced),
              icon: Icon(
                showAdvanced
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              label: Text(showAdvanced ? 'Hide setup details' : 'Setup details'),
            ),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.out,
              child: !showAdvanced
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'If this build is not preconfigured for Google sign-in, enter the OAuth client ID for this app. '
                          'This is saved on your device so future sign-ins can open directly.',
                          style: text.bodySmall
                              ?.copyWith(color: palette.mutedText),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: idController,
                          decoration: const InputDecoration(
                            labelText: 'Google OAuth Client ID',
                            hintText: 'xxxx.apps.googleusercontent.com',
                          ),
                          autocorrect: false,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Insets.sm),
                        TextField(
                          controller: secretController,
                          decoration: const InputDecoration(
                            labelText: 'Client secret (if provided)',
                          ),
                          obscureText: true,
                          autocorrect: false,
                        ),
                        const SizedBox(height: Insets.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: idController.text.trim().isEmpty
                                ? null
                                : () => Navigator.of(ctx).pop(
                                      _GoogleConnectConfig(
                                        clientId: idController.text,
                                        clientSecret: secretController.text,
                                      ),
                                    ),
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('Continue to Google sign-in'),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: Insets.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.mutedText),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(color: palette.mutedText),
          ),
        ),
      ],
    );
  }
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
              decoration:
                  InputDecoration(labelText: 'Passphrase', errorText: error),
              autofocus: true,
            ),
            if (confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: p2,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm passphrase'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
