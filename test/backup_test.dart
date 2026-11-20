import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/archive_store.dart';
import 'package:lifelog/core/storage/media_store.dart';
import 'package:lifelog/core/storage/settings_store.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/settings.dart';
import 'package:path/path.dart' as p;

Directory createTestDir(String prefix) {
  final dir = Directory(
    p.join(
      Directory.systemTemp.path,
      '$prefix${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  dir.createSync(recursive: true);
  return dir;
}

CryptoService testCrypto() => CryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );

List<FileSystemEntity> quarantined(Directory dir, String prefix) => dir
    .listSync()
    .where((entity) => p.basename(entity.path).startsWith(prefix))
    .toList(growable: false);

void main() {
  const service = BackupService();

  Archive sampleArchive() => Archive(
        entries: [
          JournalEntry(
            id: 'e1',
            createdAt: DateTime(2026, 5, 10, 9),
            updatedAt: DateTime(2026, 5, 10, 9),
            title: 'Backed up',
            body: 'This should survive a backup round trip.',
            mood: 8,
            tags: const ['test'],
          ),
        ],
      );

  test('a backup round trip restores the structured archive', () async {
    final bytes = await service.createBackup(
      archive: sampleArchive(),
      passphrase: 'correct horse battery',
    );
    final contents = await service.readBackup(
      bytes: bytes,
      passphrase: 'correct horse battery',
    );

    expect(contents.archive.entries, hasLength(1));
    expect(contents.archive.entries.single.title, 'Backed up');
    expect(contents.archive.entries.single.mood, 8);
    expect(contents.includesMedia, isFalse);
  });

  test('the wrong passphrase cannot open a backup', () async {
    final bytes = await service.createBackup(
      archive: sampleArchive(),
      passphrase: 'correct horse battery',
    );

    expect(
      () => service.readBackup(bytes: bytes, passphrase: 'wrong passphrase'),
      throwsA(isA<BackupException>()),
    );
  });

  test('short backup passphrases are rejected', () async {
    expect(
      () => service.createBackup(archive: sampleArchive(), passphrase: 'short'),
      throwsA(isA<BackupException>()),
    );
  });

  test('unsupported algorithms and out-of-range KDF settings are rejected',
      () async {
    final bytes = await service.createBackup(
      archive: sampleArchive(),
      passphrase: 'correct horse battery',
    );

    Uint8List tamper(void Function(Map<String, dynamic>) change) {
      final container = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      change(container);
      return Uint8List.fromList(utf8.encode(jsonEncode(container)));
    }

    final badContainers = <Uint8List>[
      tamper((c) => c['cipher'] = 'aes-128-cbc'),
      tamper((c) => (c['kdf'] as Map)['name'] = 'pbkdf2'),
      tamper((c) => (c['kdf'] as Map)['memory'] = 131072),
      tamper((c) => (c['kdf'] as Map)['iterations'] = 11),
      tamper((c) => (c['kdf'] as Map)['parallelism'] = 9),
      tamper(
        (c) => (c['kdf'] as Map)['salt'] = base64Encode(Uint8List(4)),
      ),
    ];
    for (final bad in badContainers) {
      expect(
        () => service.readBackup(bytes: bad, passphrase: 'correct horse battery'),
        throwsA(isA<BackupException>()),
      );
    }
  });

  test('archive saves leave a recoverable backup and fall back to it', () async {
    final root = createTestDir('lifelog-atomic-archive-');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = ArchiveStore(directory: root, crypto: testCrypto());

    await store.save(
      Archive(entries: [
        JournalEntry(
          id: 'e1',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          title: 'first',
          body: '',
        ),
      ]),
    );
    await store.save(
      Archive(entries: [
        JournalEntry(
          id: 'e1',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          title: 'second',
          body: '',
        ),
      ]),
    );

    expect(await File('${store.file.path}.tmp').exists(), isFalse);
    expect(await File('${store.file.path}.bak').exists(), isTrue);
    expect((await store.load())!.entries.single.title, 'second');

    // Simulate a damaged primary file after a successful save.
    await store.file.writeAsBytes(const [1, 2, 3]);
    final recovered = await store.load();
    expect(recovered, isNotNull);
    expect(recovered!.entries.single.title, 'first');
    expect(
      quarantined(root, 'archive.lifelog.corrupt-'),
      isNotEmpty,
    );
  });

  test('archive load reports the cause when no copy can be opened', () async {
    final root = createTestDir('lifelog-corrupt-archive-');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = ArchiveStore(directory: root, crypto: testCrypto());
    await store.file.writeAsBytes(const [9, 9, 9]);
    await File('${store.file.path}.tmp').writeAsBytes(const [8, 8, 8]);
    await File('${store.file.path}.bak').writeAsBytes(const [7, 7, 7]);

    Object? thrown;
    try {
      await store.load();
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isA<ArchiveLoadException>());
    expect(thrown.toString(), contains('Cause:'));
    expect(quarantined(root, 'archive.lifelog.corrupt-'), hasLength(3));
  });

  test('settings saves are atomic and recover from a damaged primary',
      () async {
    final root = createTestDir('lifelog-atomic-settings-');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = SettingsStore(directory: root);

    await store.save(const AppSettings(onboardingComplete: true));
    await store.save(const AppSettings(themeMode: AppThemeMode.dark));
    expect(await File('${store.file.path}.tmp').exists(), isFalse);
    expect(await File('${store.file.path}.bak').exists(), isTrue);

    await store.file.writeAsString('{not json');
    final recovered = await store.load();
    expect(recovered.onboardingComplete, isTrue);
    expect(recovered.themeMode, AppThemeMode.system);
    expect(store.lastLoadError, isNotNull);
    expect(
      quarantined(root, 'settings.json.corrupt-'),
      isNotEmpty,
    );
    // The quarantine file keeps the damaged bytes for inspection.
    final damaged = quarantined(root, 'settings.json.corrupt-').single;
    expect(await File(damaged.path).readAsString(), '{not json');
  });

  test('backup skips media whose encrypted file is missing', () async {
    final root = createTestDir('lifelog-backup-media-');
    addTearDown(() => root.deleteSync(recursive: true));
    final crypto = testCrypto();
    final store = MediaStore(
      directory: Directory(p.join(root.path, 'media')),
      crypto: crypto,
    );
    final item = await store.importBytes(
      bytes: Uint8List.fromList(utf8.encode('a tiny photo')),
      fileName: 'photo.txt',
    );
    final archive = Archive(media: [item]);

    final withMedia = await service.createBackup(
      archive: archive,
      passphrase: 'correct horse battery',
      mediaStore: store,
    );
    final included = await service.readBackup(
      bytes: withMedia,
      passphrase: 'correct horse battery',
    );
    expect(included.mediaFiles, hasLength(1));

    await File(p.join(store.directory.path, '${item.id}.bin')).delete();
    // A fresh store has no in-memory byte cache, like a cold app start.
    final freshStore = MediaStore(directory: store.directory, crypto: crypto);
    final withoutMedia = await service.createBackup(
      archive: archive,
      passphrase: 'correct horse battery',
      mediaStore: freshStore,
    );
    final result = await service.readBackup(
      bytes: withoutMedia,
      passphrase: 'correct horse battery',
    );

    expect(result.archive.media, hasLength(1));
    expect(result.mediaFiles, isEmpty);
    expect(result.includesMedia, isFalse);
  });
}
