import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import '../../features/settings/google_drive_actions.dart';

/// On startup, if Google Drive is connected and local archive is empty,
/// prompt to restore from cloud so users can retrieve their data on a new device.
Future<void> maybePromptGoogleDriveRestore(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  if (!settings.googleDriveConnected) return;
  final archive = ref.read(archiveProvider);
  if (!archive.isEmpty) return;

  final services = ref.read(appServicesProvider);
  final authJson = await ref.read(settingsProvider.notifier).googleAuthJson();
  if (authJson == null) return;
  try {
    final remote = await services.googleDrive.findRemoteBackup(
      clientId: settings.googleClientId ?? '',
      clientSecret: settings.googleClientSecret ?? '',
      authJson: authJson,
      onRefreshed: (j) => ref.read(settingsProvider.notifier).updateGoogleAuthCipher(j),
    );
    if (remote == null || !context.mounted) return;
    final doRestore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: Text(
          remote.modifiedTime != null
              ? 'A cloud backup was found (updated ${formatDayLong(remote.modifiedTime!)} ${formatTime(remote.modifiedTime!)}). Restore your data to this device?'
              : 'A cloud backup was found in your Google Drive. Restore your data to this device?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (doRestore == true && context.mounted) {
      await restoreFromGoogleDrive(context, ref);
    }
  } catch (_) {
    // silent on startup
  }
}
