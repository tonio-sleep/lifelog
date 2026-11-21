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

  /// True when any on-disk archive artifact exists. Bootstrap uses this to
  /// avoid treating an unreadable install as a fresh one.
  static Future<bool> hasAnyArchiveFile(Directory directory) async {
    if (!await directory.exists()) return false;
    final base = File(p.join(directory.path, fileName));
    for (final candidate in <File>[
      base,
      File('${base.path}$_tempSuffix'),
      File('${base.path}$_backupSuffix'),
    ]) {
      if (await candidate.exists()) return true;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).startsWith(_quarantinePrefix)) {
        return true;
      }
    }
    return false;
  }

  /// Loads the newest readable copy. A completed write always leaves the
  /// primary file intact, but a crash or a damaged disk can still make it
  /// unreadable, so the temp and backup copies are tried as well.
  ///
  /// Unreadable files are never renamed or deleted here. A transient key or
  /// storage failure must not turn the next launch into a silent fresh start.
  Future<Archive?> load() async {
    final candidates = <File>[
      file,
      File('${file.path}$_tempSuffix'),
      File('${file.path}$_backupSuffix'),
    ];
    final causes = <Object>[];
    final paths = <String>[];

    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      paths.add(candidate.path);
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
      }
    }

    if (causes.isEmpty) return null;
    throw ArchiveLoadException(
      'The encrypted archive could not be opened. It may have been '
      'written with a different key, or the file may be damaged. No local '
      'files were moved or deleted.',
      causes.first,
      causes: causes,
      paths: paths,
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

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}

class ArchiveLoadException implements Exception {
  ArchiveLoadException(
    this.message,
    this.cause, {
    List<Object>? causes,
    List<String>? paths,
  })  : causes = causes ?? <Object>[cause],
        paths = paths ?? const <String>[];

  final String message;
  final Object cause;

  /// Every copy that was tried, in order. Useful for diagnosing whether a
  /// backup is recoverable or the key itself is wrong.
  final List<Object> causes;

  /// Local files that were present but unreadable. None were moved or deleted.
  final List<String> paths;

  @override
  String toString() {
    final pathText = paths.isEmpty ? '' : ' Files: ${paths.join(', ')}';
    return '$message Cause: $cause$pathText';
  }
}
