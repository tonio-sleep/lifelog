import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:lifelog/app/app_services.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/archive_store.dart';
import 'package:lifelog/core/storage/media_store.dart';
import 'package:lifelog/core/storage/settings_store.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/settings.dart';
import 'package:lifelog/integrations/cloudflare/cloudflare_sync_service.dart';
import 'package:lifelog/integrations/health/health_steps_service.dart';
import 'package:lifelog/integrations/lastfm/lastfm_service.dart';
import 'package:path/path.dart' as p;

/// Minimal, offline [AppServices] for widget tests. Nothing here touches real
/// user storage or the network, but every screen sees real provider types.
AppServices createWidgetTestServices({
  required Directory directory,
  Archive? archive,
  AppSettings settings = const AppSettings(onboardingComplete: true),
}) {
  final crypto = CryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 1)),
  );
  return AppServices(
    rootDirectory: directory,
    crypto: crypto,
    archiveStore: ArchiveStore(directory: directory, crypto: crypto),
    mediaStore: MediaStore(
      directory: Directory(p.join(directory.path, 'media')),
      crypto: crypto,
    ),
    settingsStore: SettingsStore(
      directory: Directory(p.join(directory.path, 'settings')),
    ),
    lastfm: LastfmService(),
    backup: const BackupService(),
    cloudflareSync: CloudflareSyncService(appKey: 'test-app-key'),
    healthSteps: HealthStepsService(),
    archive: archive ?? Archive.empty(),
    settings: settings,
    keySource: 'test',
  );
}
