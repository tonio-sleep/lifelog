import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/backup/backup_service.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/integrations/cloudflare/backup_upload_progress.dart';
import 'package:lifelog/integrations/cloudflare/cloudflare_sync_service.dart';

void main() {
  test('worker URLs require HTTPS except explicit loopback', () {
    expect(
      () => CloudflareSyncService.normalizeBaseUrl('http://example.com/worker'),
      throwsA(isA<CloudflareSyncException>()),
    );
    expect(
      CloudflareSyncService.normalizeBaseUrl('worker.example.com'),
      'https://worker.example.com',
    );
    expect(
      CloudflareSyncService.normalizeBaseUrl('http://127.0.0.1:8787'),
      'http://127.0.0.1:8787',
    );
    expect(
      CloudflareSyncService.workerUrlWarning('http://example.com'),
      isNotNull,
    );
  });

  test('backup packing reports each stage with bounded counts', () async {
    final stages = <(BackupPackStage, int, int)>[];
    final archive = Archive(entries: const []);
    final bytes = await const BackupService().createBackup(
      archive: archive,
      passphrase: 'correct horse battery',
      onProgress: (stage, current, total, label) {
        stages.add((stage, current, total));
      },
    );

    expect(bytes.isNotEmpty, isTrue);
    expect(stages.first.$1, BackupPackStage.preparing);
    expect(
      stages.map((event) => event.$1),
      containsAll([
        BackupPackStage.packing,
        BackupPackStage.encrypting,
        BackupPackStage.done,
      ]),
    );
    expect(stages.last.$1, BackupPackStage.done);
    for (final (_, current, total) in stages) {
      expect(current, lessThanOrEqualTo(total));
    }
  });

  test(
    'upload progress controller tracks items, bytes and terminal states',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(backupUploadProvider.notifier);

      expect(
        container.read(backupUploadProvider).stage,
        BackupUploadStage.idle,
      );
      controller.begin();
      expect(container.read(backupUploadProvider).active, isTrue);

      controller.packed(BackupPackStage.media, 1, 2, 'Including photo 1 of 2');
      expect(
        container.read(backupUploadProvider).stage,
        BackupUploadStage.media,
      );
      expect(container.read(backupUploadProvider).itemFraction, 0.5);

      controller.uploading(50, 100);
      expect(
        container.read(backupUploadProvider).stage,
        BackupUploadStage.uploading,
      );
      expect(container.read(backupUploadProvider).byteFraction, 0.5);

      controller.finish();
      var state = container.read(backupUploadProvider);
      expect(state.stage, BackupUploadStage.done);
      expect(state.active, isFalse);
      expect(state.bytesSent, state.bytesTotal);

      controller.fail('Upload failed');
      state = container.read(backupUploadProvider);
      expect(state.stage, BackupUploadStage.failed);
      expect(state.error, 'Upload failed');
    },
  );

  test(
    'streamed upload sends the exact encrypted bytes and reports progress',
    () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(150000, (index) => index % 251),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final receivedBody = Completer<Uint8List>();
      HttpRequest? receivedRequest;
      server.listen((request) async {
        receivedRequest = request;
        final chunks = await request.toList();
        receivedBody.complete(
          Uint8List.fromList(chunks.expand((chunk) => chunk).toList()),
        );
        request.response.statusCode = 200;
        await request.response.close();
      });
      final progress = <(int, int)>[];

      await CloudflareSyncService(appKey: 'test-app-key').uploadBackup(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'session-token',
        bytes: bytes,
        onByteProgress: (sent, total) => progress.add((sent, total)),
      );

      final sentBody = await receivedBody.future.timeout(
        const Duration(seconds: 5),
      );
      expect(receivedRequest, isNotNull);
      expect(receivedRequest!.method, 'PUT');
      expect(receivedRequest!.uri.path, '/api/backup');
      expect(
        receivedRequest!.headers.value('authorization'),
        'Bearer session-token',
      );
      expect(
        receivedRequest!.headers.value('x-lifelog-app-key'),
        'test-app-key',
      );
      expect(
        receivedRequest!.headers.value('content-type'),
        'application/octet-stream',
      );
      expect(sentBody, bytes);
      // Queued chunks are not reported as sent: the only progress event is the
      // confirmation after the Worker accepted the full body.
      expect(progress, hasLength(1));
      expect(progress.single.$1, bytes.length);
      expect(progress.single.$2, bytes.length);
    },
  );
}
