import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

enum SecureKeyStatus { found, absent, unavailable }

class SecureKeyLookup {
  const SecureKeyLookup(this.status, {this.key, this.error});

  final SecureKeyStatus status;
  final SecretKey? key;
  final Object? error;
}

class KeyUnavailableException implements Exception {
  KeyUnavailableException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message Cause: $cause';
}

/// Loads the archive's root key from platform secure storage. On systems
/// without a usable secure store, a local key file is used as a documented
/// fallback so the archive remains usable.
class KeyVault {
  KeyVault({required this.directory, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const secureKeyName = 'lifelog.master_key.v1';
  static const fallbackFileName = 'master.key';
  static const fallbackTempSuffix = '.tmp';
  static const fallbackBackupSuffix = '.bak';
  static const _fallbackFileName = fallbackFileName;
  static const _tempSuffix = fallbackTempSuffix;
  static const _backupSuffix = fallbackBackupSuffix;

  final Directory directory;
  final FlutterSecureStorage _storage;

  /// True when the key is read from or written to the local fallback file
  /// because platform secure storage was unavailable.
  bool usedFallback = false;

  /// Non-null when a degraded path was used at startup, for example a
  /// temporarily unavailable secure store recovered from the local key file.
  String? lastWarning;

  File get fallbackFile => File(p.join(directory.path, _fallbackFileName));

  /// [archiveExists] must be supplied by the caller. A brand new install can
  /// safely create a key; doing so while an archive is present would silently
  /// orphan every existing entry.
  Future<SecretKey> loadOrCreate({bool archiveExists = false}) async {
    await directory.create(recursive: true);

    final secure = await _readSecure();
    if (secure.status == SecureKeyStatus.found) {
      usedFallback = false;
      return secure.key!;
    }

    final fallback = await _readFallback();
    if (fallback != null) {
      usedFallback = true;
      if (secure.status == SecureKeyStatus.unavailable) {
        lastWarning =
            'Platform secure storage was temporarily unavailable; the local '
            'key file was used instead.';
      }
      return SecretKey(fallback);
    }

    if (archiveExists) {
      // Never create a new key when an archive is already on disk. A transient
      // platform failure must not look like a fresh install.
      throw KeyUnavailableException(
        secure.status == SecureKeyStatus.unavailable
            ? 'The secure key store is temporarily unavailable and no local '
                'key is present. A new key was not created because an existing '
                'archive was found.'
            : 'No archive key was found. A new key was not created because an '
                'existing archive was found; restore from a backup instead.',
        secure.error,
      );
    }

    final key = await AesGcm.with256bits().newSecretKey();
    final bytes = await key.extractBytes();
    final encoded = base64Encode(bytes);

    if (await _writeSecure(encoded)) {
      usedFallback = false;
      return key;
    }

    usedFallback = true;
    lastWarning = 'Platform secure storage was unavailable; the archive key '
        'was stored in a local file.';
    await _writeFallback(bytes);
    return key;
  }

  /// Distinguishes "no key stored" from "could not talk to the key store".
  /// Both look like null to the caller of FlutterSecureStorage.read, but only
  /// the former permits creating a new key.
  Future<SecureKeyLookup> _readSecure() async {
    String? encoded;
    try {
      encoded = await _storage.read(key: secureKeyName);
    } catch (error) {
      return SecureKeyLookup(SecureKeyStatus.unavailable, error: error);
    }
    if (encoded == null || encoded.isEmpty) {
      return const SecureKeyLookup(SecureKeyStatus.absent);
    }
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) {
        return SecureKeyLookup(
          SecureKeyStatus.unavailable,
          error: const FormatException('Stored key is not 32 bytes'),
        );
      }
      return SecureKeyLookup(SecureKeyStatus.found, key: SecretKey(bytes));
    } catch (error) {
      return SecureKeyLookup(SecureKeyStatus.unavailable, error: error);
    }
  }

  Future<List<int>?> _readFallback() async {
    final file = fallbackFile;
    if (!await file.exists()) return null;
    try {
      final encoded = (await file.readAsString()).trim();
      if (encoded.isEmpty) return null;
      final bytes = base64Decode(encoded);
      if (bytes.length == 32) return bytes;
    } catch (_) {
      // A corrupt fallback key is never silently replaced while an archive
      // exists; loadOrCreate reports KeyUnavailableException in that case.
    }
    return null;
  }

  Future<bool> _writeSecure(String encoded) async {
    try {
      await _storage.write(key: secureKeyName, value: encoded);
      final check = await _storage.read(key: secureKeyName);
      return check == encoded;
    } catch (_) {
      return false;
    }
  }

  /// Verifies the complete key file before it can replace an existing one.
  Future<void> _writeFallback(List<int> bytes) async {
    final encoded = base64Encode(bytes);
    final file = fallbackFile;
    final temp = File('${file.path}$_tempSuffix');
    final backup = File('${file.path}$_backupSuffix');

    await temp.writeAsString(encoded, flush: true);
    if ((await temp.readAsString()).trim() != encoded) {
      throw StateError('The fallback key file did not verify after writing.');
    }

    if (await file.exists()) {
      try {
        await backup.writeAsString(await file.readAsString(), flush: true);
      } catch (_) {
        // Best effort: the existing key is still intact until the rename.
      }
    }

    try {
      await temp.rename(file.path);
    } catch (_) {
      if (await backup.exists()) {
        try {
          await backup.copy(file.path);
        } catch (_) {}
      }
      rethrow;
    }

    if ((await file.readAsString()).trim() != encoded) {
      throw StateError('The fallback key file did not verify after replacement.');
    }
  }
}

/// AES-256-GCM with a fresh nonce for every encryption operation. The archive
/// key never leaves the device through this application.
class CryptoService {
  CryptoService(this.key) : _cipher = AesGcm.with256bits();

  final SecretKey key;
  final AesGcm _cipher;

  static const nonceLength = 12;
  static const macLength = 16;

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<Uint8List> encryptBytes(List<int> clearText, {String aad = ''}) async {
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return box.concatenation(nonce: true, mac: true);
  }

  Future<Uint8List> decryptBytes(List<int> envelope, {String aad = ''}) async {
    final box = SecretBox.fromConcatenation(
      envelope,
      nonceLength: nonceLength,
      macLength: macLength,
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList(clear);
  }

  Future<String> encryptString(String clearText, {String aad = ''}) async {
    final bytes = await encryptBytes(utf8.encode(clearText), aad: aad);
    return base64Encode(bytes);
  }

  Future<String> decryptString(String envelope, {String aad = ''}) async {
    final bytes = await decryptBytes(base64Decode(envelope), aad: aad);
    return utf8.decode(bytes);
  }

  /// Derives a separate key from a passphrase with Argon2id. Used only for
  /// encrypted archive exports.
  static Future<SecretKey> deriveBackupKey({
    required String passphrase,
    required Uint8List salt,
    int memory = 19456,
    int iterations = 2,
    int parallelism = 1,
  }) async {
    final algorithm = Argon2id(
      parallelism: parallelism,
      memory: memory,
      iterations: iterations,
      hashLength: 32,
    );
    final derived = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return SecretKey(await derived.extractBytes());
  }

  Uint8List newSalt() => _randomBytes(16);
}

/// Salted Argon2id hash used for the optional convenience PIN. The PIN is a
/// screen lock, not a replacement for the archive key's secure storage.
class PinHasher {
  const PinHasher._();

  static Future<(String salt, String hash)> create(String pin) async {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final key = await CryptoService.deriveBackupKey(
      passphrase: pin,
      salt: salt,
    );
    final bytes = await key.extractBytes();
    return (base64Encode(salt), base64Encode(bytes));
  }

  static Future<bool> verify({
    required String pin,
    required String salt,
    required String hash,
  }) async {
    try {
      final saltBytes = base64Decode(salt);
      final key = await CryptoService.deriveBackupKey(
        passphrase: pin,
        salt: Uint8List.fromList(saltBytes),
      );
      final candidate = await key.extractBytes();
      final expected = base64Decode(hash);
      if (candidate.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < candidate.length; i++) {
        diff |= candidate[i] ^ expected[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }
}
