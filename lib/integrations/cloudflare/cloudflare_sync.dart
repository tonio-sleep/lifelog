import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import '../../features/settings/cloudflare_sync_actions.dart';
import 'cloudflare_sync_service.dart';

/// On startup, if Cloudflare sync is connected and local archive is empty,
/// prompt to restore from cloud so users can retrieve their data on a new device.
Future<void> maybePromptCloudflareRestore(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  if (!settings.cloudflareConnected) return;
  final archive = ref.read(archiveProvider);
  if (!archive.isEmpty) return;

  final services = ref.read(appServicesProvider);
  final sessionJson =
      await ref.read(settingsProvider.notifier).cloudflareSessionJson();
  if (sessionJson == null) {
    await ref.read(settingsProvider.notifier).disconnectCloudflareSync();
    return;
  }
  try {
    final sessionMap = jsonDecode(sessionJson) as Map<String, dynamic>;
    final token = sessionMap['token'] as String? ?? '';
    final workerUrl = settings.cloudflareWorkerUrl ?? '';
    if (token.isEmpty || workerUrl.trim().isEmpty) {
      await ref.read(settingsProvider.notifier).disconnectCloudflareSync();
      return;
    }
    final meta = await services.cloudflareSync.getBackupMeta(
      baseUrl: workerUrl,
      token: token,
    );
    if (!meta.exists || !context.mounted) return;
    final when = meta.modifiedAt ?? meta.uploadedAt;
    final doRestore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Cloudflare sync?'),
        content: Text(
          when != null
              ? 'A cloud backup was found (updated ${formatDayLong(when)} ${formatTime(when)}). Sign in if needed and restore your data to this device.'
              : 'A cloud backup was found. Sign in if needed and restore your data to this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (doRestore == true && context.mounted) {
      await restoreFromCloudflare(context, ref);
    }
  } on CloudflareSyncException catch (e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('session expired') ||
        msg.contains('unauthorized') ||
        msg.contains('sign in again')) {
      await ref.read(settingsProvider.notifier).disconnectCloudflareSync();
    }
    // silent on startup for other errors
  } catch (_) {
    // silent on startup
  }
}
