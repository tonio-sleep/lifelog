// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import '../../core/backup/backup_service.dart';
import '../../core/storage/media_store.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/media.dart';
import 'backup_upload_progress.dart';
import 'cloudflare_sync_service.dart';

void _noCloudSyncProgress(CloudSyncProgressEvent event) {}

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
    void Function(CloudSyncProgressEvent event)? onProgress,
  }) : _api = api,
       _backup = backup,
       _mediaStore = mediaStore,
       _credentials = credentials,
       _archive = archive,
       _recordSync = recordSync,
       _onProgress = onProgress ?? _noCloudSyncProgress {
    _mediaStore.remoteSource = this;
  }

  final CloudflareSyncService _api;
  final BackupService _backup;
  final MediaStore _mediaStore;
  final Future<CloudSyncCredentials?> Function() _credentials;
  final Future<Archive> Function() _archive;
  final Future<void> Function(DateTime at) _recordSync;
  final void Function(CloudSyncProgressEvent event) _onProgress;

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

    _onProgress(CloudSyncProgressEvent.begin());
    var operation = CloudSyncOperation.backupUpload;
    try {
      final archive = await _archive();
      // Cloud backups deliberately omit media bytes. Media lives in R2 as
      // encrypted objects and is fetched on demand into the local cache.
      final encrypted = await _backup.createBackup(
        archive: archive,
        passphrase: credentials.passphrase,
        onProgress: (stage, current, total, label) {
          _onProgress(
            CloudSyncProgressEvent.packed(stage, current, total, label),
          );
        },
      );
      final plan = await _buildUploadPlan(encrypted.length, archive);
      _onProgress(CloudSyncProgressEvent.plan(plan));

      await _api.uploadBackup(
        baseUrl: credentials.workerUrl,
        token: credentials.token,
        bytes: encrypted,
        onByteProgress: (sent, total) {
          _onProgress(
            CloudSyncProgressEvent.bytes(
              CloudUploadKind.backup,
              sent,
              itemLabel: 'Encrypted backup',
            ),
          );
        },
      );
      _onProgress(
        CloudSyncProgressEvent.bytes(
          CloudUploadKind.backup,
          encrypted.length,
          itemLabel: 'Encrypted backup',
          itemComplete: true,
        ),
      );

      operation = CloudSyncOperation.mediaUpload;
      await _syncMedia(credentials, archive);
      await _recordSync(DateTime.now());
      _onProgress(CloudSyncProgressEvent.done());
    } catch (error) {
      _onProgress(
        CloudSyncProgressEvent.failed(
          friendlyCloudflareSyncError(error, operation: operation),
        ),
      );
      rethrow;
    }
  }

  /// Plan exact ciphertext sizes so the progress bar cannot drift when an
  /// envelope is larger than the original media metadata.
  Future<List<CloudUploadRow>> _buildUploadPlan(
    int backupBytes,
    Archive archive,
  ) async {
    final totals = <CloudUploadKind, int>{
      CloudUploadKind.backup: backupBytes,
    };
    final counts = <CloudUploadKind, int>{
      CloudUploadKind.backup: 1,
    };

    void add(CloudUploadKind kind, int bytes) {
      totals[kind] = (totals[kind] ?? 0) + bytes;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }

    for (final item in archive.media) {
      final originalSize = await _mediaStore.encryptedSizeIfExists(
        item.id,
        MediaFileKind.original,
      );
      if (originalSize != null) {
        add(_uploadKind(item, false), originalSize);
      }
      if (item.hasThumbnail) {
        final thumbSize = await _mediaStore.encryptedSizeIfExists(
          item.id,
          MediaFileKind.thumb,
        );
        if (thumbSize != null) add(CloudUploadKind.thumbnail, thumbSize);
      }
    }

    return [
      for (final kind in CloudUploadKind.values)
        if ((totals[kind] ?? 0) > 0)
          CloudUploadRow(
            kind: kind,
            totalBytes: totals[kind]!,
            itemsTotal: counts[kind] ?? 0,
          ),
    ];
  }

  Future<void> _syncMedia(
    CloudSyncCredentials credentials,
    Archive archive,
  ) async {
    var index = 0;
    for (final item in archive.media) {
      index++;
      await _syncOne(
        credentials,
        item,
        MediaFileKind.original,
        _uploadKind(item, false),
        '${item.kindLabel} $index',
        await _mediaStore.readEncryptedOriginalIfExists(item),
      );
      if (item.hasThumbnail) {
        await _syncOne(
          credentials,
          item,
          MediaFileKind.thumb,
          CloudUploadKind.thumbnail,
          '${item.kindLabel} $index thumbnail',
          await _mediaStore.readEncryptedThumbnailIfExists(item),
        );
      }
    }
  }

  Future<void> _syncOne(
    CloudSyncCredentials credentials,
    MediaItem item,
    MediaFileKind fileKind,
    CloudUploadKind kind,
    String label,
    Uint8List? encrypted,
  ) async {
    // A missing local file is not an error on a new device: the object may
    // already be online, and on-demand reads will cache it when needed.
    if (encrypted == null || encrypted.isEmpty) return;
    final target = fileKind == MediaFileKind.thumb
        ? CloudflareMediaKind.thumb
        : CloudflareMediaKind.original;
    final remoteSize = await _api.mediaSize(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: item.id,
      kind: target,
    );
    if (remoteSize == encrypted.length) {
      // The Worker confirmed this exact byte length. Advance the row so the
      // run still completes when nothing new needed uploading.
      _onProgress(
        CloudSyncProgressEvent.bytes(
          kind,
          encrypted.length,
          itemLabel: '$label verified on server',
          itemComplete: true,
        ),
      );
      return;
    }
    await _api.uploadMedia(
      baseUrl: credentials.workerUrl,
      token: credentials.token,
      id: item.id,
      kind: target,
      bytes: encrypted,
      onByteProgress: (sent, total) {
        _onProgress(
          CloudSyncProgressEvent.bytes(kind, sent, itemLabel: label),
        );
      },
    );
    _onProgress(
      CloudSyncProgressEvent.bytes(
        kind,
        encrypted.length,
        itemLabel: label,
        itemComplete: true,
      ),
    );
  }

  CloudUploadKind _uploadKind(MediaItem item, bool thumbnail) {
    if (thumbnail) return CloudUploadKind.thumbnail;
    if (item.isAudio) return CloudUploadKind.audio;
    if (item.isVideo) return CloudUploadKind.video;
    if (item.isImage) return CloudUploadKind.photo;
    return CloudUploadKind.otherMedia;
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
