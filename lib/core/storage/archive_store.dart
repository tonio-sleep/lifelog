import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/archive.dart';
import '../crypto/crypto_service.dart';

class ArchiveStore {
  ArchiveStore({required this.directory, required this.crypto});

  static const _aad = 'lifelog-archive-v1';
  static const _fileName = 'archive.lifelog';

  final Directory directory;
  final CryptoService crypto;

  File get file => File(p.join(directory.path, _fileName));

  Future<Archive?> load() async {
    final archiveFile = file;
    if (!await archiveFile.exists()) return null;
    try {
      final envelope = await archiveFile.readAsBytes();
      final clear = await crypto.decryptBytes(envelope, aad: _aad);
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Archive root is not an object');
      }
      return Archive.fromJson(decoded);
    } catch (error) {
      throw ArchiveLoadException(
        'The encrypted archive could not be opened. It may have been '
        'written with a different key, or the file may be damaged.',
        error,
      );
    }
  }

  Future<void> save(Archive archive) async {
    await directory.create(recursive: true);
    final clear = utf8.encode(jsonEncode(archive.toJson()));
    final envelope = await crypto.encryptBytes(clear, aad: _aad);

    final target = file;
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(envelope, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}

class ArchiveLoadException implements Exception {
  ArchiveLoadException(this.message, this.cause);
  final String message;
  final Object cause;

  @override
  String toString() => message;
}
