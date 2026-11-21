import 'dart:async';
import 'dart:convert';
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

  test('timeouts are explained by phase without claiming false progress', () {
    final timeout = TimeoutException('late');
    expect(
      friendlyCloudflareSyncError(
        timeout,
        operation: CloudSyncOperation.account,
      ),
      contains('signing in'),
    );
    expect(
      friendlyCloudflareSyncError(
        timeout,
        operation: CloudSyncOperation.backupUpload,
      ),
      contains('Confirmed parts are saved'),
    );
    expect(
      friendlyCloudflareSyncError(
        timeout,
        operation: CloudSyncOperation.download,
      ),
      contains('Nothing on this device was replaced'),
    );
    for (final operation in CloudSyncOperation.values) {
      expect(
        friendlyCloudflareSyncError(timeout, operation: operation),
        isNot('The sync server took too long to respond. '
            'Check your connection and try again.'),
      );
    }
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
    'upload progress tracks every confirmed kind with bounded totals',
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

      controller.plan([
        const CloudUploadRow(
          kind: CloudUploadKind.backup,
          totalBytes: 100,
          itemsTotal: 1,
        ),
        const CloudUploadRow(
          kind: CloudUploadKind.audio,
          totalBytes: 50,
          itemsTotal: 2,
        ),
      ]);
      expect(container.read(backupUploadProvider).bytesTotal, 150);

      controller.confirmBytes(CloudUploadKind.audio, 25,
          itemLabel: 'Voice memo 1');
      controller.confirmBytes(
        CloudUploadKind.audio,
        50,
        itemLabel: 'Voice memo 1',
        itemComplete: true,
      );
      var state = container.read(backupUploadProvider);
      expect(state.byteFraction, 50 / 150);
      expect(state.currentItem, 'Voice memo 1');
      expect(
        state.rows.singleWhere((r) => r.kind == CloudUploadKind.audio).itemsDone,
        1,
      );

      controller.uploading(100, 100);
      controller.finish();
      state = container.read(backupUploadProvider);
      expect(state.stage, BackupUploadStage.done);
      expect(state.active, isFalse);
      expect(state.bytesSent, state.bytesTotal);
      expect(state.rows.every((row) => row.complete), isTrue);

      controller.fail('Upload failed');
      state = container.read(backupUploadProvider);
      expect(state.stage, BackupUploadStage.failed);
      expect(state.error, 'Upload failed');
      // A failed run keeps the last truthful byte counts visible.
      expect(state.bytesSent, state.bytesTotal);
    },
  );

  test(
    'chunked upload confirms each part and only advances after a 2xx',
    () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(150000, (index) => index % 251),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final paths = <String>[];
      final parts = <Uint8List>[];
      final authHeaders = <String?>[];

      server.listen((request) async {
        paths.add('${request.method} ${request.uri.path}');
        authHeaders.add(request.headers.value('authorization'));
        switch (request.uri.path) {
          case '/api/uploads/begin':
            await utf8.decoder.bind(request).join();
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'ok': true,
                'uploadId': 'upload-1',
                'partSize': 8 * 1024 * 1024,
                'partCount': 1,
                'size': bytes.length,
              }));
          case '/api/uploads/upload-1/parts/1':
            final chunks = await request.toList();
            parts.add(Uint8List.fromList(chunks.expand((c) => c).toList()));
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'ok': true,
                'partNumber': 1,
                'confirmedBytes': bytes.length,
                'totalBytes': bytes.length,
                'complete': true,
              }));
          case '/api/uploads/upload-1/complete':
            await utf8.decoder.bind(request).join();
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'ok': true, 'size': bytes.length}));
          default:
            request.response.statusCode = 404;
        }
        await request.response.close();
      });

      final progress = <(int, int)>[];
      await CloudflareSyncService(appKey: 'test-app-key').uploadBackup(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'session-token',
        bytes: bytes,
        onByteProgress: (sent, total) => progress.add((sent, total)),
      );

      expect(paths, [
        'POST /api/uploads/begin',
        'PUT /api/uploads/upload-1/parts/1',
        'POST /api/uploads/upload-1/complete',
      ]);
      expect(authHeaders, everyElement(equals('Bearer session-token')));
      expect(parts, hasLength(1));
      expect(parts.single, bytes);
      expect(progress.first.$1, 0);
      expect(progress.last, (bytes.length, bytes.length));
      for (final (sent, total) in progress) {
        expect(sent, greaterThanOrEqualTo(0));
        expect(sent, lessThanOrEqualTo(total));
      }
    },
  );

  test('legacy Worker without resumable uploads still receives the bytes',
      () async {
    final bytes = Uint8List.fromList(
      List<int>.generate(4096, (index) => index % 241),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final paths = <String>[];
    Uint8List? received;

    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      if (request.uri.path == '/api/uploads/begin') {
        await request.drain<void>();
        request.response.statusCode = 404;
      } else {
        final chunks = await request.toList();
        received = Uint8List.fromList(chunks.expand((c) => c).toList());
        request.response.statusCode = 200;
      }
      await request.response.close();
    });

    final progress = <(int, int)>[];
    await CloudflareSyncService(appKey: 'test-app-key').uploadBackup(
      baseUrl: 'http://127.0.0.1:${server.port}',
      token: 'session-token',
      bytes: bytes,
      onByteProgress: (sent, total) => progress.add((sent, total)),
    );

    expect(paths, ['POST /api/uploads/begin', 'PUT /api/backup']);
    expect(received, bytes);
    expect(progress, [
      (bytes.length, bytes.length),
    ]);
  });
}
