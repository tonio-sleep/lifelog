import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import 'cloudflare_sync_service.dart';
import 'sync_status.dart';

/// A lightweight "git status" for the single encrypted cloud backup.
/// Reads the remote metadata only when the app is signed in.
final cloudRemoteMetaProvider = FutureProvider<CloudflareBackupMeta?>((ref) async {
  final signedIn = ref.watch(
    settingsProvider.select((s) => s.cloudflareConnected),
  );
  final workerUrl = ref.watch(
    settingsProvider.select((s) => s.cloudflareWorkerUrl),
  );
  // Re-read metadata whenever credentials or the account change, so it never
  // belongs to the previous Cloudflare user.
  ref.watch(
    settingsProvider.select((s) => (
      s.cloudflareSessionCipher,
      s.cloudflareUsername,
      s.cloudflareConnectedAt,
    )),
  );
  ref.watch(syncSessionRejectedProvider);
  if (!signedIn || workerUrl == null || workerUrl.trim().isEmpty) return null;

  final json = await ref
      .read(settingsProvider.notifier)
      .cloudflareSessionJson();
  if (json == null) return null;
  final session = CloudflareSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
  if (session.token.isEmpty) return null;
  try {
    return await ref.read(appServicesProvider).cloudflareSync.getBackupMeta(
          baseUrl: workerUrl,
          token: session.token,
        );
  } on CloudflareSyncException {
    rethrow;
  }
});
