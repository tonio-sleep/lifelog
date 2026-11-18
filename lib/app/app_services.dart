import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/models/archive.dart';
import '../domain/models/settings.dart';
import '../integrations/lastfm/lastfm_service.dart';
import '../integrations/google_drive/google_drive_service.dart';
import '../integrations/health/health_steps_service.dart';
import '../core/backup/backup_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/storage/archive_store.dart';
import '../core/storage/media_store.dart';
import '../core/storage/settings_store.dart';

/// Application assembly. Everything is wired once during bootstrap so screens
/// never create databases, keys or API clients themselves.
class AppServices {
  AppServices({
    required this.rootDirectory,
    required this.crypto,
    required this.archiveStore,
    required this.mediaStore,
    required this.settingsStore,
    required this.lastfm,
    required this.backup,
    required this.googleDrive,
    required this.healthSteps,
    required this.archive,
    required this.settings,
    required this.keySource,
  });

  final Directory rootDirectory;
  final CryptoService crypto;
  final ArchiveStore archiveStore;
  final MediaStore mediaStore;
  final SettingsStore settingsStore;
  final LastfmService lastfm;
  final BackupService backup;
  final GoogleDriveService googleDrive;
  final HealthStepsService healthSteps;
  final Archive archive;
  final AppSettings settings;
  final String keySource;

  Directory get mediaDirectory => mediaStore.directory;

  static Future<AppServices> bootstrap() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'lifelog'));
    await root.create(recursive: true);

    // Ensure a visible Backups folder exists in the Files app on mobile.
    try {
      final docs = await getApplicationDocumentsDirectory();
      final backups = Directory(p.join(docs.path, 'Backups'));
      await backups.create(recursive: true);
    } catch (_) {}

    final vault = KeyVault(directory: root);
    final key = await vault.loadOrCreate();
    final crypto = CryptoService(key);
    final keySource = vault.usedFallback
        ? 'Local key file (platform secure storage unavailable)'
        : 'Platform secure storage';

    final archiveStore = ArchiveStore(directory: root, crypto: crypto);
    final mediaStore = MediaStore(
      directory: Directory(p.join(root.path, 'media')),
      crypto: crypto,
    );
    final settingsStore = SettingsStore(directory: root);
    final settings = await settingsStore.load();
    final archive = await archiveStore.load() ?? Archive.empty();

    return AppServices(
      rootDirectory: root,
      crypto: crypto,
      archiveStore: archiveStore,
      mediaStore: mediaStore,
      settingsStore: settingsStore,
      lastfm: LastfmService(),
      backup: const BackupService(),
      googleDrive: GoogleDriveService(),
      healthSteps: HealthStepsService(),
      archive: archive,
      settings: settings,
      keySource: keySource,
    );
  }
}
