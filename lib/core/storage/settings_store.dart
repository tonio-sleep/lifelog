import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/settings.dart';

class SettingsStore {
  SettingsStore({required this.directory});

  static const _fileName = 'settings.json';
  static const _tempSuffix = '.tmp';
  static const _backupSuffix = '.bak';
  static const _quarantinePrefix = 'settings.json.corrupt-';

  final Directory directory;

  File get file => File(p.join(directory.path, _fileName));

  /// Set when a settings file was unreadable and had to be quarantined. The
  /// bootstrap records this as a startup warning instead of silently
  /// overwriting the damaged file.
  String? lastLoadError;

  Future<AppSettings> load() async {
    final candidates = <File>[
      file,
      File('${file.path}$_tempSuffix'),
      File('${file.path}$_backupSuffix'),
    ];
    final causes = <Object>[];

    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        final text = await candidate.readAsString();
        if (text.trim().isEmpty) {
          throw const FormatException('Settings file is empty');
        }
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Settings root is not an object');
        }
        return AppSettings.fromJson(decoded);
      } catch (error) {
        causes.add(error);
        // Record the degraded load even when a later copy is readable: the
        // caller must know that a file was damaged rather than assume a clean
        // start with defaults.
        lastLoadError =
            'A settings file could not be read and was quarantined. '
            'Cause: $error';
        if (error is! FileSystemException) await _quarantine(candidate);
      }
    }

    if (causes.isEmpty) return const AppSettings();
    lastLoadError =
        'Settings could not be read (${causes.length} copy/copies damaged); '
        'defaults were loaded and the damaged files were quarantined. '
        'Cause: ${causes.first}';
    return const AppSettings();
  }

  /// Writes a complete copy first, keeps the previous good copy as a backup,
  /// then replaces the primary file in one rename.
  Future<void> save(AppSettings settings) async {
    await directory.create(recursive: true);
    final bytes = utf8.encode(jsonEncode(settings.toJson()));
    await _writeAtomically(file, bytes);
  }

  Future<void> _writeAtomically(File target, List<int> bytes) async {
    final temp = File('${target.path}$_tempSuffix');
    final backup = File('${target.path}$_backupSuffix');

    await temp.writeAsBytes(bytes, flush: true);

    if (await target.exists()) {
      try {
        await backup.writeAsBytes(await target.readAsBytes(), flush: true);
      } catch (_) {
        // Best effort only; the original target is untouched until the rename.
      }
    }

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
    } catch (_) {}
  }
}
