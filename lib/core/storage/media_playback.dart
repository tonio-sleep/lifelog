import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/media.dart';
import 'media_store.dart';

/// A decrypted temporary file used only by native players. It is deleted as
/// soon as the viewer is closed; the encrypted vault remains the source of
/// truth.
class PlaybackFile {
  PlaybackFile(this.file);

  final File file;

  Future<void> delete() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A temp-file cleanup failure should never block navigation.
    }
  }
}

Future<PlaybackFile> materializePlaybackFile(
  MediaStore store,
  MediaItem item,
  Directory temporaryDirectory,
) async {
  await temporaryDirectory.create(recursive: true);
  final extension = _extension(item);
  final file = File(
    p.join(temporaryDirectory.path, 'lifelog-playback-${item.id}$extension'),
  );
  final bytes = await store.readOriginal(item);
  await file.writeAsBytes(bytes, flush: true);
  return PlaybackFile(file);
}

String _extension(MediaItem item) {
  final original = p.extension(item.originalName ?? '').toLowerCase();
  if (original.isNotEmpty && original.length <= 8) return original;
  final mime = item.mimeType.toLowerCase();
  if (mime.contains('quicktime')) return '.mov';
  if (mime.contains('mp4')) return '.mp4';
  if (mime.contains('webm')) return '.webm';
  if (mime.contains('mpeg')) return '.mp3';
  if (mime.contains('wav')) return '.wav';
  if (mime.contains('ogg')) return '.ogg';
  if (mime.contains('flac')) return '.flac';
  if (mime.contains('aiff')) return '.aiff';
  if (mime.contains('image/jpeg')) return '.jpg';
  if (mime.contains('image/png')) return '.png';
  if (mime.contains('image/heic')) return '.heic';
  return '.bin';
}
