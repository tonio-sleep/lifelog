// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import '../../core/backup/backup_service.dart';
import '../../core/storage/media_store.dart';
import '../../domain/models/archive.dart';
import 'cloudflare_sync_service.dart';

/// Everything needed to talk to the cloud without putting credentials in the
/// media vault or sending the backup passphrase to the server.
class CloudSyncCredentials {
  const CloudSyncCredentials({
    required this.workerUrl,
    required this.token,
    required this.passphrase,
  });

  final String workerUrl;
  final String token;
  final String passphrase;

  bool get isValid =>
      workerUrl.trim().isNotEmpty && token.isNotEmpty && passphrase.isNotEmpty;
}

/// Cloud-primary sync engine. The Worker/R2 archive is the source of truth;
/// local archive and media files are encrypted caches that can be rebuilt.
class CloudSyncEngine implements MediaRemoteSource {
  CloudSyncEngine({
    required CloudflareSyncService api,
    required BackupService backup,
    required MediaStore mediaStore,
    required Future<CloudSyncCredentials?> Function() credentials,
    required Future<Archive> Function() archive,
    required Future<void> Function(DateTime at) recordSync,
  }) : _api = api,
       _backup = backup,
       _mediaStore = mediaStore,
       _credentials = credentials,
       _archive = archive,
       _recordSync = recordSync {
    _mediaStore.remoteSource = this;
  }

  final CloudflareSyncService _api;
  final BackupService _backup;
  final MediaStore _mediaStore;
  final Future<CloudSyncCredentials?> Function() _credentials;
  final Future<Archive> Function() _archive;
  final Future<void> Function(DateTime at) _recordSync;

  Future<void>? _inFlight;

  /// Coalesces concurrent saves into one upload. Callers can await this to
  /// observe the real completion state; failures are not swallowed.
  Future<void> syncNow() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final task = _sync();
    _inFlight = task;
    return task.whenComplete(() {
      if (identical(_inFlight, task)) _inFlight = null;
    });
  }

  Future<void> _sync() async {
    final credentials = await _credentials();
    if (credentials == null || !credentials.isValid) return;

    final archive = await _archive();
    // Cloud backups deliberately omit media bytes. Media lives in R2 as
    // encrypted objects and is fetched on demand into the local cache.
    final encrypted = await _backup.createBackup(
      archive: archive,
      passphrase: credentials.passphrase,
    );
    await _api.uploadBackup(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      bytes: encrypted,
    );
    await _syncMedia(credentials, archive);
    await _recordSync(DateTime.now());
  }

  Future<void> _syncMedia(
    CloudSyncCredentials credentials,
    Archive archive,
  ) async {
    for (final item in archive.media) {
      await _syncOne(
        credentials,
        item.id,
        CloudflareMediaKind.original,
        await _mediaStore.readEncryptedOriginalIfExists(item),
      );
      if (item.hasThumbnail) {
        await _syncOne(
          credentials,
          item.id,
          CloudflareMediaKind.thumb,
          await _mediaStore.readEncryptedThumbnailIfExists(item),
        );
      }
    }
  }

  Future<void> _syncOne(
    CloudSyncCredentials credentials,
    String id,
    CloudflareMediaKind kind,
    Uint8List? encrypted,
  ) async {
    // A missing local file is not an error on a new device: the object may
    // already be online, and on-demand reads will cache it when needed.
    if (encrypted == null || encrypted.isEmpty) return;
    final remoteSize = await _api.mediaSize(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: id,
      kind: kind,
    );
    if (remoteSize == encrypted.length) return;
    await _api.uploadMedia(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: id,
      kind: kind,
      bytes: encrypted,
    );
  }

  @override
  Future<Uint8List> readEncrypted(String id, MediaFileKind kind) async {
    final credentials = await _requireCredentials();
    return _api.downloadMedia(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: id,
      kind: _kind(kind),
    );
  }

  @override
  Future<void> writeEncrypted(
    String id,
    MediaFileKind kind,
    Uint8List envelope,
  ) async {
    final credentials = await _requireCredentials();
    await _api.uploadMedia(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: id,
      kind: _kind(kind),
      bytes: envelope,
    );
  }

  @override
  Future<void> remove(String id, MediaFileKind kind) async {
    final credentials = await _requireCredentials();
    await _api.deleteMedia(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: id,
      kind: _kind(kind),
    );
  }

  Future<CloudSyncCredentials> _requireCredentials() async {
    final credentials = await _credentials();
    if (credentials == null || !credentials.isValid) {
      throw CloudflareSyncException(
        'Sign in and save your backup passphrase to fetch cloud media.',
      );
    }
    return credentials;
  }

  CloudflareMediaKind _kind(MediaFileKind kind) => switch (kind) {
    MediaFileKind.original => CloudflareMediaKind.original,
    MediaFileKind.thumb => CloudflareMediaKind.thumb,
  };
}
