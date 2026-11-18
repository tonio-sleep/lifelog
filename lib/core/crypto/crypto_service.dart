import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Loads the archive's root key from platform secure storage. On desktop
/// systems without a usable secure store, a local key file is used as a
/// documented fallback so the archive remains usable.
class KeyVault {
  KeyVault({required this.directory, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const secureKeyName = 'lifelog.master_key.v1';
  static const _fallbackFileName = 'master.key';

  final Directory directory;
  final FlutterSecureStorage _storage;

  /// True when the key is read from or written to the local fallback file
  /// because platform secure storage was unavailable.
  bool usedFallback = false;

  File get fallbackFile => File(p.join(directory.path, _fallbackFileName));

  Future<SecretKey> loadOrCreate() async {
    await directory.create(recursive: true);

    final fromSecure = await _readSecure();
    if (fromSecure != null) return fromSecure;

    final file = fallbackFile;
    if (await file.exists()) {
      final encoded = (await file.readAsString()).trim();
      if (encoded.isNotEmpty) {
        try {
          final bytes = base64Decode(encoded);
          if (bytes.length == 32) {
            usedFallback = true;
            return SecretKey(bytes);
          }
        } on FormatException {
          // Fall through and create a new key; a corrupt fallback key means the
          // existing archive cannot be decrypted and the UI will explain that.
        }
      }
    }

    final algorithm = AesGcm.with256bits();
    final key = await algorithm.newSecretKey();
    final bytes = await key.extractBytes();
    final encoded = base64Encode(bytes);

    final secureStored = await _writeSecure(encoded);
    if (!secureStored) {
      usedFallback = true;
      await file.writeAsString(encoded, flush: true);
    }
    return SecretKey(bytes);
  }

  Future<SecretKey?> _readSecure() async {
    try {
      final encoded = await _storage.read(key: secureKeyName);
      if (encoded == null || encoded.isEmpty) return null;
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) return null;
      return SecretKey(bytes);
    } catch (_) {
      return null;
    }
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
