import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/models/media.dart';
import '../crypto/crypto_service.dart';

class MediaUnavailableException implements Exception {
  MediaUnavailableException(this.id);
  final String id;
  @override
  String toString() => 'The encrypted media file for $id is not available.';
}

class MediaTooLargeException implements Exception {
  MediaTooLargeException(this.bytes);
  final int bytes;
  @override
  String toString() => 'This file is too large to attach.';
}

enum MediaFileKind { original, thumb }

/// Online source for encrypted media envelopes. Lifelog cloud storage keeps
/// the ciphertext; the local vault is only a cache for offline/on-demand reads.
abstract class MediaRemoteSource {
  Future<Uint8List> readEncrypted(String id, MediaFileKind kind);
  Future<void> writeEncrypted(
    String id,
    MediaFileKind kind,
    Uint8List envelope,
  );
  Future<void> remove(String id, MediaFileKind kind);
}

class MediaStore {
  MediaStore({required this.directory, required this.crypto});

  static const _aad = 'lifelog-media-v1';
  static const _thumbAad = 'lifelog-media-thumb-v1';
  static const maxBytes = 250 * 1024 * 1024;

  final Directory directory;
  final CryptoService crypto;
  final Map<String, Uint8List> _cache = {};

  /// Installed by cloud sync when an account is connected. Never stores keys;
  /// it only moves ciphertext already encrypted with this archive's key.
  MediaRemoteSource? remoteSource;

  Future<void> _ensureDirectory() => directory.create(recursive: true);

  File _originalFile(String id) => File(p.join(directory.path, '$id.bin'));
  File _thumbFile(String id) => File(p.join(directory.path, '$id.thumb.bin'));

  Future<Uint8List> _readEnvelope(String id, MediaFileKind kind) async {
    final file = kind == MediaFileKind.original
        ? _originalFile(id)
        : _thumbFile(id);
    if (await file.exists()) return file.readAsBytes();
    final remote = remoteSource;
    if (remote == null) throw MediaUnavailableException(id);
    final envelope = await remote.readEncrypted(id, kind);
    if (envelope.isEmpty) throw MediaUnavailableException(id);
    await _ensureDirectory();
    await file.writeAsBytes(envelope, flush: true);
    return envelope;
  }

  Future<void> _uploadEnvelope(
    String id,
    MediaFileKind kind,
    Uint8List envelope,
  ) async {
    final remote = remoteSource;
    if (remote == null) return;
    try {
      await remote.writeEncrypted(id, kind, envelope);
    } catch (_) {
      // The encrypted local cache remains valid; sync retries this object.
    }
  }

  Future<void> _removeRemote(String id, MediaFileKind kind) async {
    final remote = remoteSource;
    if (remote == null) return;
    try {
      await remote.remove(id, kind);
    } catch (_) {
      // Best effort: the archive no longer references the object.
    }
  }

  Future<MediaItem> importBytes({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String caption = '',
    List<String> tags = const [],
    String? journalEntryId,
    DateTime? createdAt,
  }) async {
    if (bytes.length > maxBytes) throw MediaTooLargeException(bytes.length);
    final type = mimeType ?? mimeTypeForFileName(fileName);
    final id = const Uuid().v4();
    await _ensureDirectory();

    final envelope = await crypto.encryptBytes(bytes, aad: _aad);
    await _originalFile(id).writeAsBytes(envelope, flush: true);
    await _uploadEnvelope(id, MediaFileKind.original, envelope);

    int? width;
    int? height;
    var hasThumbnail = false;

    if (type.startsWith('image/') && bytes.length < 60 * 1024 * 1024) {
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
          final targetWidth = decoded.width > 900 ? 900 : decoded.width;
          final thumbnail = img.copyResize(
            decoded,
            width: targetWidth,
            maintainAspect: true,
            interpolation: img.Interpolation.average,
          );
          final jpeg = Uint8List.fromList(
            img.encodeJpg(thumbnail, quality: 80),
          );
          final thumbEnvelope = await crypto.encryptBytes(jpeg, aad: _thumbAad);
          await _thumbFile(id).writeAsBytes(thumbEnvelope, flush: true);
          await _uploadEnvelope(id, MediaFileKind.thumb, thumbEnvelope);
          hasThumbnail = true;
        }
      } catch (_) {
        // Some formats (HEIC, RAW) cannot be decoded by the pure-Dart codec.
        // The original file is still preserved and encrypted.
      }
    }

    return MediaItem(
      id: id,
      createdAt: createdAt ?? DateTime.now(),
      mimeType: type,
      bytes: bytes.length,
      caption: caption,
      tags: tags,
      journalEntryId: journalEntryId,
      hasThumbnail: hasThumbnail,
      width: width,
      height: height,
      originalName: fileName,
    );
  }

  Future<Uint8List> readOriginal(MediaItem item) async {
    final cacheKey = 'full:${item.id}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final envelope = await _readEnvelope(item.id, MediaFileKind.original);
    final clear = await crypto.decryptBytes(envelope, aad: _aad);
    _remember(cacheKey, clear);
    return clear;
  }

  Future<Uint8List> readThumbnail(MediaItem item) async {
    if (!item.hasThumbnail) return readOriginal(item);
    final cacheKey = 'thumb:${item.id}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    try {
      final envelope = await _readEnvelope(item.id, MediaFileKind.thumb);
      final clear = await crypto.decryptBytes(envelope, aad: _thumbAad);
      _remember(cacheKey, clear);
      return clear;
    } catch (_) {
      return readOriginal(item);
    }
  }

  Future<Uint8List> readEncryptedOriginal(MediaItem item) =>
      _readEnvelope(item.id, MediaFileKind.original);

  /// Local-cache-only read used by sync. Returns null when this device has no
  /// cached copy; the cloud copy, if any, is left untouched.
  Future<Uint8List?> readEncryptedOriginalIfExists(MediaItem item) async {
    final file = _originalFile(item.id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<Uint8List?> readEncryptedThumbnailIfExists(MediaItem item) async {
    final file = _thumbFile(item.id);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Copies the per-item ciphertext into [targetDirectory]. The copy remains
  /// encrypted and can only be opened with this archive's key.
  Future<int> exportEncryptedCopies(
    Iterable<MediaItem> items,
    Directory targetDirectory,
  ) async {
    await targetDirectory.create(recursive: true);
    var copied = 0;
    for (final item in items) {
      final file = _originalFile(item.id);
      if (!await file.exists()) continue;
      await file.copy(p.join(targetDirectory.path, '${item.id}.bin'));
      final thumb = _thumbFile(item.id);
      if (await thumb.exists()) {
        await thumb.copy(p.join(targetDirectory.path, '${item.id}.thumb.bin'));
      }
      copied++;
    }
    return copied;
  }

  Future<Uint8List?> readThumbnailBytesIfExists(MediaItem item) async {
    if (!item.hasThumbnail) return null;
    final cacheKey = 'thumb:${item.id}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    try {
      final envelope = await _readEnvelope(item.id, MediaFileKind.thumb);
      final clear = await crypto.decryptBytes(envelope, aad: _thumbAad);
      _remember(cacheKey, clear);
      return clear;
    } catch (_) {
      return null;
    }
  }

  /// Writes clear media bytes into the encrypted vault (used during backup restore).
  /// This preserves the item's id so archive metadata remains valid.
  Future<void> writeRestoredItem({
    required MediaItem item,
    required Uint8List originalBytes,
    Uint8List? thumbnailBytes,
  }) async {
    await _ensureDirectory();
    final envelope = await crypto.encryptBytes(originalBytes, aad: _aad);
    await _originalFile(item.id).writeAsBytes(envelope, flush: true);
    _cache.remove('full:${item.id}');
    _cache.remove('thumb:${item.id}');
    final thumbFile = _thumbFile(item.id);
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      final thumbEnvelope = await crypto.encryptBytes(
        thumbnailBytes,
        aad: _thumbAad,
      );
      await thumbFile.writeAsBytes(thumbEnvelope, flush: true);
    } else if (await thumbFile.exists()) {
      await thumbFile.delete();
    }
  }

  Future<void> delete(MediaItem item) async {
    _cache.remove('full:${item.id}');
    _cache.remove('thumb:${item.id}');
    final original = _originalFile(item.id);
    if (await original.exists()) await original.delete();
    final thumb = _thumbFile(item.id);
    if (await thumb.exists()) await thumb.delete();
    await _removeRemote(item.id, MediaFileKind.original);
    await _removeRemote(item.id, MediaFileKind.thumb);
  }

  Future<void> deleteAll() async {
    _cache.clear();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  void _remember(String key, Uint8List bytes) {
    if (_cache.length >= 48) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = bytes;
  }
}

String mimeTypeForFileName(String fileName) {
  final extension = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' || 'heif' => 'image/heic',
    'tif' || 'tiff' => 'image/tiff',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'avi' => 'video/x-msvideo',
    'mkv' => 'video/x-matroska',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'ogg' || 'oga' => 'audio/ogg',
    'opus' => 'audio/opus',
    'flac' => 'audio/flac',
    'aiff' || 'aif' => 'audio/aiff',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
