import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/integrations/cloudflare/cloudflare_sync_service.dart';

void main() {
  test('a build without an app key fails closed before any request', () async {
    final service = CloudflareSyncService(appKey: '');
    expect(
      () => service.checkHealth('http://127.0.0.1:1'),
      throwsA(
        isA<CloudflareSyncException>().having(
          (error) => error.message,
          'message',
          contains('missing its app key'),
        ),
      ),
    );
  });

  test('all API request types send the compiled-in app key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final keys = <String?>[];
    final paths = <String>[];
    final baseUrl = 'http://127.0.0.1:${server.port}';

    server.listen((request) async {
      keys.add(request.headers.value('x-lifelog-app-key'));
      paths.add('${request.method} ${request.uri.path}');
      switch (request.uri.path) {
        case '/api/health':
          request.response
            ..statusCode = 200
            ..write('{"ok":true}');
        case '/api/auth/register':
          await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = 200
            ..write(
              '{"ok":true,"token":"t","username":"user","expiresIn":123}',
            );
        case '/api/backup/meta':
          request.response
            ..statusCode = 200
            ..write('{"ok":true,"exists":false}');
        case '/api/media/id/original':
          request.response
            ..statusCode = 200
            ..add(Uint8List.fromList([1, 2, 3]));
        case '/api/media/id/thumb':
          if (request.method == 'HEAD') {
            request.response
              ..statusCode = 200
              ..headers.contentLength = 3;
          } else {
            await request.drain<void>();
            request.response
              ..statusCode = 200
              ..write('{"ok":true}');
          }
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
              'size': 3,
            }));
        case '/api/uploads/upload-1/parts/1':
          await request.drain<void>();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              '{"ok":true,"confirmedBytes":3,"totalBytes":3,"complete":true}',
            );
        case '/api/uploads/upload-1/complete':
          await utf8.decoder.bind(request).join();
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"ok":true,"size":3}');
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final service = CloudflareSyncService(appKey: 'test-app-key');
    await service.checkHealth(baseUrl);
    await service.register(
      baseUrl: baseUrl,
      username: 'user',
      password: 'password-long',
    );
    await service.getBackupMeta(baseUrl: baseUrl, token: 't');
    await service.downloadMedia(
      baseUrl: baseUrl,
      token: 't',
      id: 'id',
      kind: CloudflareMediaKind.original,
    );
    await service.mediaSize(
      baseUrl: baseUrl,
      token: 't',
      id: 'id',
      kind: CloudflareMediaKind.thumb,
    );
    await service.uploadMedia(
      baseUrl: baseUrl,
      token: 't',
      id: 'id',
      kind: CloudflareMediaKind.thumb,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    await service.deleteMedia(
      baseUrl: baseUrl,
      token: 't',
      id: 'id',
      kind: CloudflareMediaKind.original,
    );

    expect(paths, [
      'GET /api/health',
      'POST /api/auth/register',
      'GET /api/backup/meta',
      'GET /api/media/id/original',
      'HEAD /api/media/id/thumb',
      'POST /api/uploads/begin',
      'PUT /api/uploads/upload-1/parts/1',
      'POST /api/uploads/upload-1/complete',
      'DELETE /api/media/id/original',
    ]);
    expect(keys, hasLength(9));
    expect(keys, everyElement(equals('test-app-key')));
  });
}
