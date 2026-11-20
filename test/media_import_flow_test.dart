import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lifelog/app/app_services.dart';
import 'package:lifelog/app/providers/providers.dart';
import 'package:lifelog/app/theme/app_theme.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/archive_store.dart';
import 'package:lifelog/core/storage/media_store.dart';
import 'package:lifelog/core/storage/settings_store.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/settings.dart';
import 'package:lifelog/features/photos/media_import.dart';
import 'package:lifelog/integrations/cloudflare/cloudflare_sync_service.dart';
import 'package:lifelog/integrations/health/health_steps_service.dart';
import 'package:lifelog/integrations/lastfm/lastfm_service.dart';
import 'package:path/path.dart' as p;

Uint8List samplePng() {
  final image = img.Image(width: 4, height: 3);
  image.setPixel(0, 0, img.ColorRgb8(220, 30, 40));
  return Uint8List.fromList(img.encodePng(image));
}

AppServices makeServices(Directory root) {
  final crypto = CryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 1)),
  );
  final archiveStore = ArchiveStore(directory: root, crypto: crypto);
  final mediaStore = MediaStore(
    directory: Directory(p.join(root.path, 'media')),
    crypto: crypto,
  );
  final settingsStore = SettingsStore(directory: root);
  const settings = AppSettings();
  return AppServices(
    rootDirectory: root,
    crypto: crypto,
    archiveStore: archiveStore,
    mediaStore: mediaStore,
    settingsStore: settingsStore,
    lastfm: LastfmService(),
    backup: const BackupService(),
    cloudflareSync: CloudflareSyncService(),
    healthSteps: HealthStepsService(),
    archive: Archive.empty(),
    settings: settings,
    keySource: 'test',
  );
}

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

void main() {
  test('imported image bytes survive encryption and archive reload', () async {
    final root = createTestDir('lifelog-media-store');
    addTearDown(() => root.deleteSync(recursive: true));
    final services = makeServices(root);
    final bytes = samplePng();

    final item = await services.mediaStore.importBytes(
      bytes: bytes,
      fileName: 'photo.png',
      caption: 'At the park',
    );

    expect(item.isImage, isTrue);
    expect(item.hasThumbnail, isTrue);
    expect(item.width, 4);
    expect(item.height, 3);
    expect(await services.mediaStore.readOriginal(item), equals(bytes));
    expect(await services.mediaStore.readThumbnail(item), isNotEmpty);

    await services.archiveStore.save(Archive(media: [item]));
    final reloaded = await services.archiveStore.load();
    expect(reloaded, isNotNull);
    expect(reloaded!.media, hasLength(1));
    expect(reloaded.media.single.caption, 'At the park');
    // The display path decrypts from the vault using reloaded metadata.
    expect(
      await services.mediaStore.readOriginal(reloaded.media.single),
      equals(bytes),
    );
  });

  testWidgets('Add in the details sheet saves the image and reports it',
      (tester) async {
    final root = createTestDir('lifelog-media-import');
    addTearDown(() => root.deleteSync(recursive: true));
    final services = makeServices(root);
    final bytes = samplePng();
    final picked = XFile.fromData(
      bytes,
      path: p.join(root.path, 'picked.png'),
      mimeType: 'image/png',
    );
    MediaImportSummary? summary;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () async {
                  summary = await importPickedMedia(
                    context,
                    ref,
                    [picked],
                    createdAt: DateTime(2026, 1, 2, 12),
                  );
                },
                child: const Text('Import'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Add to your archive'), findsOneWidget);
    expect(find.textContaining('picked.png'), findsWidgets);
    await tester.tap(find.text('Add'));

    for (var attempt = 0; attempt < 100 && summary == null; attempt++) {
      // let real disk I/O complete, then give Flutter a frame to close the
      // progress dialog and deliver the snack bar.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(summary, isNotNull);
    final result = summary!;
    expect(result.total, 1);
    expect(result.added, 1);
    expect(result.skipped, 0);
    expect(result.failed, 0);
    expect(find.text('1 item added.'), findsOneWidget);

    final saved = await tester.runAsync(() => services.archiveStore.load());
    expect(saved, isNotNull);
    expect(saved!.media, hasLength(1));
    expect(saved.media.single.originalName, 'picked.png');
    expect(saved.media.single.createdAt, DateTime(2026, 1, 2, 12));
    final decrypted = await tester.runAsync(
      () => services.mediaStore.readOriginal(saved.media.single),
    );
    expect(decrypted, equals(bytes));

    // askMediaDetails disposes its controllers after a short delay.
    await tester.pump(const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(seconds: 20)));
}
