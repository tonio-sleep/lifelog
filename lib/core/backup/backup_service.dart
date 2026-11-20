import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/models/archive.dart';
import '../crypto/crypto_service.dart';
import '../storage/media_store.dart';

/// Phases reported while an encrypted backup is assembled. This is local
/// progress only — the wire format and encryption are unchanged.
enum BackupPackStage { preparing, media, packing, encrypting, done }

typedef BackupProgressCallback = void Function(
  BackupPackStage stage,
  int current,
  int total,
  String label,
);

class BackupException implements Exception {
  BackupException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class BackupMediaFile {
  BackupMediaFile({
    required this.id,
    required this.originalBytes,
    this.thumbnailBytes,
  });

  final String id;
  final Uint8List originalBytes;
  final Uint8List? thumbnailBytes;
}

class BackupContents {
  BackupContents({
    required this.archive,
    required this.createdAt,
    required this.includesMedia,
    this.mediaFiles = const [],
  });

  final Archive archive;
  final DateTime createdAt;
  final bool includesMedia;
  final List<BackupMediaFile> mediaFiles;

  Map<String, int> get counts => {
    'journalEntries': archive.entries.length,
    'photos': archive.media.length,
    'trackers': archive.trackers.length,
    'trackerRecords': archive.trackerRecords.length,
    'timelineEvents': archive.events.length,
    'places': archive.places.length,
    'visits': archive.visits.length,
    'scrobbles': archive.scrobbles.length,
    'locationSamples': archive.locationSamples.length,
    'meals': archive.meals.length,
  };
}

String _packLabel(String key) => switch (key) {
      'journalEntries' => 'Organizing journal entries',
      'photos' => 'Organizing media',
      'trackers' => 'Organizing habits',
      'trackerRecords' => 'Organizing habit records',
      'timelineEvents' => 'Organizing timeline events',
      'places' => 'Organizing places',
      'visits' => 'Organizing visits',
      'scrobbles' => 'Organizing music',
      'locationSamples' => 'Organizing location history',
      'meals' => 'Organizing meals and drinks',
      _ => 'Organizing records',
    };

/// Versioned, passphrase-encrypted archive exports.
/// The archive (and included media bytes, when present) is encrypted with a key
/// derived using Argon2id and AES-256-GCM. Media bytes are decrypted on-device
/// before being packed into the encrypted backup so restores work across devices
/// using only the backup passphrase.
class BackupService {
  const BackupService();

  static const format = 'lifelog-backup';
  static const version = 2;
  static const _aadV1 = 'lifelog-backup-v1';
  static const _aadV2 = 'lifelog-backup-v2';

  static Uint8List _secureSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  static int? _boundedKdfValue(Object? value, int min, int max) {
    final parsed = (value as num?)?.toInt();
    if (parsed == null || parsed < min || parsed > max) return null;
    return parsed;
  }

  Future<Uint8List> createBackup({
    required Archive archive,
    required String passphrase,
    MediaStore? mediaStore,
    BackupProgressCallback? onProgress,
  }) async {
    if (passphrase.trim().length < 8) {
      throw BackupException('Use a backup passphrase of at least 8 characters.');
    }

    onProgress?.call(
      BackupPackStage.preparing,
      0,
      1,
      'Preparing encrypted backup',
    );
    final salt = _secureSalt();
    final key = await CryptoService.deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
    );
    final crypto = CryptoService(key);

    final mediaFiles = <Map<String, dynamic>>[];
    final mediaTotal = archive.media.length;
    if (mediaStore != null && archive.media.isNotEmpty) {
      for (var i = 0; i < mediaTotal; i++) {
        final item = archive.media[i];
        onProgress?.call(
          BackupPackStage.media,
          i + 1,
          mediaTotal,
          'Including media ${i + 1} of $mediaTotal',
        );
        try {
          final original = await mediaStore.readOriginal(item);
          final thumb = await mediaStore.readThumbnailBytesIfExists(item);
          mediaFiles.add({
            'id': item.id,
            'original': base64Encode(original),
            'thumb': thumb == null ? null : base64Encode(thumb),
          });
        } on MediaUnavailableException {
          // Skip missing vault files but keep metadata in archive.
        }
      }
    }
    final includesMedia = mediaFiles.isNotEmpty;

    final counts = BackupContents(
      archive: archive,
      createdAt: DateTime.now(),
      includesMedia: includesMedia,
      mediaFiles: const [],
    ).counts;
    final totalItems = counts.values.fold<int>(0, (sum, value) => sum + value);
    var packed = 0;
    for (final entry in counts.entries) {
      packed += entry.value;
      onProgress?.call(
        BackupPackStage.packing,
        packed,
        totalItems,
        _packLabel(entry.key),
      );
    }

    final archiveJson = archive.toJson();
    final payload = {
      'format': 'lifelog-archive',
      'version': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'includesMedia': includesMedia,
      'archive': archiveJson,
      'mediaFiles': mediaFiles,
    };
    onProgress?.call(
      BackupPackStage.encrypting,
      0,
      1,
      'Encrypting backup',
    );
    final encrypted = await crypto.encryptBytes(
      utf8.encode(jsonEncode(payload)),
      aad: _aadV2,
    );

    final container = {
      'format': format,
      'version': version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'includesMedia': includesMedia,
      'cipher': 'aes-256-gcm',
      'kdf': {
        'name': 'argon2id',
        'memory': 19456,
        'iterations': 2,
        'parallelism': 1,
        'salt': base64Encode(salt),
      },
      'payload': base64Encode(encrypted),
    };

    final pretty = const JsonEncoder.withIndent('  ').convert(container);
    onProgress?.call(BackupPackStage.done, 1, 1, 'Backup ready');
    return Uint8List.fromList(utf8.encode(pretty));
  }

  Future<BackupContents> readBackup({
    required Uint8List bytes,
    required String passphrase,
  }) async {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw BackupException('This file is not a Lifelog backup.');
      }
      if (decoded['format'] != format) {
        throw BackupException('This file is not a Lifelog backup.');
      }
      final containerVersion = decoded['version'];
      if (containerVersion != 1 && containerVersion != 2) {
        throw BackupException(
          'This backup uses an unsupported format version.',
        );
      }
      if (decoded['cipher'] != 'aes-256-gcm') {
        throw BackupException('This backup uses an unsupported cipher.');
      }
      final kdf = decoded['kdf'];
      if (kdf is! Map) {
        throw BackupException('The backup key derivation settings are missing.');
      }
      if (kdf['name'] != 'argon2id') {
        throw BackupException('This backup uses an unsupported key derivation.');
      }
      int bounded(Object? value, int min, int max, int fallback) {
        if (value == null) return fallback;
        final parsed = _boundedKdfValue(value, min, max);
        if (parsed == null) {
          throw BackupException('The backup key derivation settings are out of range.');
        }
        return parsed;
      }

      // Missing values keep the long-standing defaults; present values must be
      // within bounds so a hostile backup cannot request extreme KDF work.
      final memory = bounded(kdf['memory'], 1, 65536, 19456);
      final iterations = bounded(kdf['iterations'], 1, 10, 2);
      final parallelism = bounded(kdf['parallelism'], 1, 8, 1);
      final salt = base64Decode(kdf['salt'] as String? ?? '');
      if (salt.length < 8 || salt.length > 64) {
        throw BackupException('The backup salt is invalid.');
      }
      final key = await CryptoService.deriveBackupKey(
        passphrase: passphrase,
        salt: Uint8List.fromList(salt),
        memory: memory,
        iterations: iterations,
        parallelism: parallelism,
      );
      final encrypted = base64Decode(decoded['payload'] as String? ?? '');
      final aad = containerVersion == 1 ? _aadV1 : _aadV2;
      final clear = await CryptoService(key).decryptBytes(encrypted, aad: aad);
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic>) {
        throw BackupException('The backup contents are invalid.');
      }
      final archiveJson = payload['archive'];
      if (archiveJson is! Map<String, dynamic>) {
        throw BackupException('The backup does not contain an archive.');
      }

      final mediaFiles = <BackupMediaFile>[];
      final rawMedia = payload['mediaFiles'];
      if (rawMedia is List) {
        for (final entry in rawMedia) {
          if (entry is! Map) continue;
          final id = entry['id'] as String?;
          final originalB64 = entry['original'] as String?;
          if (id == null || id.isEmpty || originalB64 == null) continue;
          try {
            final thumbB64 = entry['thumb'] as String?;
            mediaFiles.add(BackupMediaFile(
              id: id,
              originalBytes: Uint8List.fromList(base64Decode(originalB64)),
              thumbnailBytes: thumbB64 == null || thumbB64.isEmpty
                  ? null
                  : Uint8List.fromList(base64Decode(thumbB64)),
            ));
          } catch (_) {
            // Skip malformed media entries; archive metadata is still restored.
          }
        }
      }

      return BackupContents(
        archive: Archive.fromJson(archiveJson),
        createdAt:
            DateTime.tryParse(payload['createdAt'] as String? ?? '') ??
            DateTime.now(),
        includesMedia:
            (payload['includesMedia'] as bool? ?? false) || mediaFiles.isNotEmpty,
        mediaFiles: mediaFiles,
      );
    } on BackupException {
      rethrow;
    } catch (error) {
      throw BackupException(
        'The backup could not be decrypted. Check the passphrase and file.',
        error,
      );
    }
  }
}
