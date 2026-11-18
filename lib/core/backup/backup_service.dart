import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/models/archive.dart';
import '../crypto/crypto_service.dart';

class BackupException implements Exception {
  BackupException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class BackupContents {
  BackupContents({
    required this.archive,
    required this.createdAt,
    required this.includesMedia,
  });

  final Archive archive;
  final DateTime createdAt;
  final bool includesMedia;

  Map<String, int> get counts => {
    'journalEntries': archive.entries.length,
    'photos': archive.media.length,
    'trackers': archive.trackers.length,
    'trackerRecords': archive.trackerRecords.length,
    'timelineEvents': archive.events.length,
    'places': archive.places.length,
    'visits': archive.visits.length,
    'scrobbles': archive.scrobbles.length,
  };
}

/// Versioned, passphrase-encrypted archive exports. The structured archive is
/// encrypted with a key derived using Argon2id; media bytes are excluded from
/// this container in the current build and are documented separately.
class BackupService {
  const BackupService();

  static const format = 'lifelog-backup';
  static const version = 1;
  static const _aad = 'lifelog-backup-v1';

  static Uint8List _secureSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  Future<Uint8List> createBackup({
    required Archive archive,
    required String passphrase,
  }) async {
    if (passphrase.trim().length < 8) {
      throw BackupException('Use a backup passphrase of at least 8 characters.');
    }

    final salt = _secureSalt();
    final key = await CryptoService.deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
    );
    final crypto = CryptoService(key);
    final payload = {
      'format': 'lifelog-archive',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'includesMedia': false,
      'archive': archive.toJson(),
    };
    final encrypted = await crypto.encryptBytes(
      utf8.encode(jsonEncode(payload)),
      aad: _aad,
    );

    final container = {
      'format': format,
      'version': version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'includesMedia': false,
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
      if (decoded['version'] != version) {
        throw BackupException(
          'This backup uses an unsupported format version.',
        );
      }
      final kdf = decoded['kdf'];
      if (kdf is! Map) {
        throw BackupException('The backup key derivation settings are missing.');
      }
      final salt = base64Decode(kdf['salt'] as String? ?? '');
      final key = await CryptoService.deriveBackupKey(
        passphrase: passphrase,
        salt: Uint8List.fromList(salt),
        memory: (kdf['memory'] as num?)?.toInt() ?? 19456,
        iterations: (kdf['iterations'] as num?)?.toInt() ?? 2,
        parallelism: (kdf['parallelism'] as num?)?.toInt() ?? 1,
      );
      final encrypted = base64Decode(decoded['payload'] as String? ?? '');
      final clear = await CryptoService(
        key,
      ).decryptBytes(encrypted, aad: _aad);
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic>) {
        throw BackupException('The backup contents are invalid.');
      }
      final archiveJson = payload['archive'];
      if (archiveJson is! Map<String, dynamic>) {
        throw BackupException('The backup does not contain an archive.');
      }
      return BackupContents(
        archive: Archive.fromJson(archiveJson),
        createdAt:
            DateTime.tryParse(payload['createdAt'] as String? ?? '') ??
            DateTime.now(),
        includesMedia: payload['includesMedia'] as bool? ?? false,
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
