import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';

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
}
