import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/media_store.dart';
import 'package:lifelog/domain/models/media.dart';
import 'package:path/path.dart' as p;

class _FakeRemote implements MediaRemoteSource {
  _FakeRemote(this.envelope);
  final Uint8List envelope;
  int reads = 0;

  @override
  Future<Uint8List> readEncrypted(String id, MediaFileKind kind) async {
    reads++;
    return envelope;
  }

  @override
  Future<void> writeEncrypted(
    String id,
    MediaFileKind kind,
    Uint8List envelope,
  ) async {}

  @override
  Future<void> remove(String id, MediaFileKind kind) async {}
}

void main() {
  test('missing local media is fetched online then cached encrypted', () async {
    final root = Directory(
      p.join(
        Directory.systemTemp.path,
        'lifelog-cloud-media-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() => root.deleteSync(recursive: true));

    final crypto = CryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    final original = Uint8List.fromList([9, 8, 7, 6, 5]);
    final envelope = await crypto.encryptBytes(
      original,
      aad: 'lifelog-media-v1',
    );
    final remote = _FakeRemote(envelope);
    final store = MediaStore(
      directory: Directory(p.join(root.path, 'media')),
      crypto: crypto,
    )..remoteSource = remote;

    final item = MediaItem(
      id: 'media-1',
      createdAt: DateTime.now(),
      mimeType: 'audio/mp4',
      bytes: original.length,
    );

    expect(await store.readOriginal(item), original);
    expect(remote.reads, 1);

    // Cold store with no online source: only the encrypted local cache exists.
    final cached = MediaStore(directory: store.directory, crypto: crypto);
    expect(await cached.readOriginal(item), original);
    expect(remote.reads, 1);
  });
}
