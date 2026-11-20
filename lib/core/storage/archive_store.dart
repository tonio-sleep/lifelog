import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/archive.dart';
import '../crypto/crypto_service.dart';

class ArchiveStore {
  ArchiveStore({required this.directory, required this.crypto});

  static const _aad = 'lifelog-archive-v1';

  /// Kept public so bootstrap can check for an existing archive before the
  /// encryption key is loaded. Do not change this name: it is part of the
  /// on-disk format.
  static const fileName = 'archive.lifelog';

  static const _tempSuffix = '.tmp';
  static const _backupSuffix = '.bak';
  static const _quarantinePrefix = 'archive.lifelog.corrupt-';

  final Directory directory;
  final CryptoService crypto;

  File get file => File(p.join(directory.path, fileName));

  /// Loads the newest readable copy. A completed write always leaves the
  /// primary file intact, but a crash or a damaged disk can still make it
  /// unreadable, so the temp and backup copies are tried as well.
  Future<Archive?> load() async {
    final candidates = <File>[
      file,
      File('${file.path}$_tempSuffix'),
      File('${file.path}$_backupSuffix'),
    ];
    final causes = <Object>[];

    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        final envelope = await candidate.readAsBytes();
        final clear = await crypto.decryptBytes(envelope, aad: _aad);
        final decoded = jsonDecode(utf8.decode(clear));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Archive root is not an object');
        }
        return Archive.fromJson(decoded);
      } catch (error) {
        causes.add(error);
        // Do not leave a damaged file in the primary slot where every launch
        // will trip over it again. IO failures are transient and never moved.
        if (error is! FileSystemException) await _quarantine(candidate);
      }
    }

    if (causes.isEmpty) return null;
    throw ArchiveLoadException(
      'The encrypted archive could not be opened. It may have been '
      'written with a different key, or the file may be damaged.',
      causes.first,
      causes: causes,
    );
  }

  /// Writes a complete copy first, keeps the previous good copy as a backup,
  /// then replaces the primary file in one rename. The original is never
  /// deleted before the replacement exists.
  Future<void> save(Archive archive) async {
    await directory.create(recursive: true);
    final clear = utf8.encode(jsonEncode(archive.toJson()));
    final envelope = await crypto.encryptBytes(clear, aad: _aad);
    await _writeAtomically(file, envelope);
  }

  Future<void> _writeAtomically(File target, List<int> bytes) async {
    final temp = File('${target.path}$_tempSuffix');
    final backup = File('${target.path}$_backupSuffix');

    await temp.writeAsBytes(bytes, flush: true);

    if (await target.exists()) {
      try {
        await backup.writeAsBytes(await target.readAsBytes(), flush: true);
      } catch (_) {
        // A failed backup is not fatal: the current target is still intact and
        // the temp copy is already complete.
      }
    }

    // File.rename replaces an existing file atomically on the same filesystem.
    // On failure the old target and the completed temp file are both left in
    // place, so load() can still recover.
    await temp.rename(target.path);
  }

  Future<void> _quarantine(File candidate) async {
    try {
      if (!await candidate.exists()) return;
      final target = File(
        '${candidate.parent.path}'
        '${p.separator}$_quarantinePrefix'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await candidate.rename(target.path);
    } catch (_) {
      // Quarantining is best effort; the load error still reports the cause.
    }
  }

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}

class ArchiveLoadException implements Exception {
  ArchiveLoadException(this.message, this.cause, {List<Object>? causes})
    : causes = causes ?? <Object>[cause];

  final String message;
  final Object cause;

  /// Every copy that was tried, in order. Useful for diagnosing whether a
  /// backup is recoverable or the key itself is wrong.
  final List<Object> causes;

  @override
  String toString() => '$message Cause: $cause';
}
