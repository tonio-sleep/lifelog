import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/settings.dart';

class SettingsStore {
  SettingsStore({required this.directory});

  static const _fileName = 'settings.json';

  final Directory directory;

  File get file => File(p.join(directory.path, _fileName));

  Future<AppSettings> load() async {
    try {
      if (!await file.exists()) return const AppSettings();
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const AppSettings();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
