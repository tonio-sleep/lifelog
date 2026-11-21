import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Reports bytes the Worker has positively confirmed, never bytes merely queued
/// into a local socket. It is called with 0 when a resumable upload starts.
typedef UploadByteProgress = void Function(int confirmed, int total);

/// Distinguishes timeout wording so a failed sign-in is never described as a
/// failed upload, and vice versa.
enum CloudSyncOperation {
  connection,
  account,
  metadata,
  download,
  backupUpload,
  mediaUpload,
}

const Duration _controlTimeout = Duration(seconds: 30);
const Duration _partTimeout = Duration(seconds: 90);
const Duration _legacyUploadTimeout = Duration(seconds: 180);
const int _maxAcceptedPartSize = 100 * 1024 * 1024;

/// Compiled into every build with `--dart-define=LIFELOG_API_KEY=...`.
/// An empty value makes the client fail closed instead of sending a request
/// the Worker will reject.
const String lifelogCompiledAppKey = String.fromEnvironment('LIFELOG_API_KEY');

/// The Worker sends `expiresIn`; older builds of this app stored
/// `expiresInSeconds`. Both may arrive as a number or a numeric string.
int? _sessionExpirySeconds(Map<String, dynamic> json) {
  final value = json['expiresIn'] ?? json['expiresInSeconds'];
  final parsed = switch (value) {
    final num number => number,
    final String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  final seconds = parsed.toInt();
  return seconds >= 0 ? seconds : null;
}

/// Plain HTTP is only acceptable for an explicitly local Worker.
bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

String _timeoutMessage(CloudSyncOperation operation) => switch (operation) {
      CloudSyncOperation.connection =>
        'The sync server did not respond while checking the connection. '
            'Nothing was uploaded. Check your connection and try again.',
      CloudSyncOperation.account =>
        'The sync server did not respond while signing in. No data on this '
            'device was changed. Check your connection and try again.',
      CloudSyncOperation.metadata =>
        'The sync server did not respond while checking cloud status. '
            'Nothing was uploaded or changed. Try again.',
      CloudSyncOperation.download =>
        'The sync server did not respond while downloading. Nothing on this '
            'device was replaced. Check your connection and try again.',
      CloudSyncOperation.backupUpload =>
        'The sync server did not respond while confirming an encrypted backup '
            'part. Confirmed parts are saved; retry will use them.',
      CloudSyncOperation.mediaUpload =>
        'The sync server did not respond while confirming an encrypted media '
            'part. Confirmed parts are saved; retry will use them.',
    };

String friendlyCloudflareSyncError(
  Object error, {
  CloudSyncOperation operation = CloudSyncOperation.connection,
}) {
  if (error is TimeoutException) return _timeoutMessage(operation);
  if (error is CloudflareSyncException) return error.message;
  return '$error';
}

class CloudflareSyncException implements Exception {
  CloudflareSyncException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

class CloudflareBackupMeta {
  CloudflareBackupMeta({
    required this.exists,
    this.size,
    this.uploadedAt,
    this.modifiedAt,
    this.etag,
  });
  final bool exists;
  final int? size;
  final DateTime? uploadedAt;
  final DateTime? modifiedAt;
  final String? etag;
}

enum CloudflareMediaKind {
  original('original'),
  thumb('thumb');

  const CloudflareMediaKind(this.pathSegment);
  final String pathSegment;
}

class CloudflareSession {
  CloudflareSession({
    required this.token,
    required this.username,
    this.expiresInSeconds,
    this.obtainedAt,
  });
  final String token;
  final String username;
  final int? expiresInSeconds;
  final DateTime? obtainedAt;

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'expiresInSeconds': expiresInSeconds,
        'obtainedAt': (obtainedAt ?? DateTime.now()).toIso8601String(),
      };

  factory CloudflareSession.fromJson(Map<String, dynamic> json) {
    return CloudflareSession(
      token: json['token'] as String? ?? '',
      username: json['username'] as String? ?? '',
      expiresInSeconds: _sessionExpirySeconds(json),
      obtainedAt: DateTime.tryParse(json['obtainedAt'] as String? ?? ''),
    );
  }
}

class _StartedUpload {
  const _StartedUpload({
    required this.uploadId,
    required this.partSize,
    required this.partCount,
  });

  final String uploadId;
  final int partSize;
  final int partCount;
}

/// Client for the Lifelog Cloudflare Worker sync API.
/// The Worker stores only client-side encrypted backup blobs and auth metadata.
class CloudflareSyncService {
  CloudflareSyncService({http.Client? httpClient, String? appKey})
    : _http = httpClient ?? http.Client(),
      _appKey = appKey ?? lifelogCompiledAppKey;
  final http.Client _http;
  final String _appKey;

  static String normalizeBaseUrl(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!v.contains('://')) v = 'https://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    final warning = workerUrlWarning(v);
    if (warning != null) throw CloudflareSyncException(warning);
    return v;
  }

  /// Non-blocking validation for the advanced Worker URL fields. Mirrors
  /// [normalizeBaseUrl] so the form can warn before a request is attempted.
  static String? workerUrlWarning(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return null;
    if (!v.contains('://')) v = 'https://$v';
    final uri = Uri.tryParse(v);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return 'Enter a valid Worker URL.';
    }
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _isLoopbackHost(uri.host)) return null;
    return 'Use an HTTPS Worker URL. Plain HTTP is only allowed for localhost.';
  }

  Uri _uri(String baseUrl, String path) {
    final base = normalizeBaseUrl(baseUrl);
    if (base.isEmpty) throw CloudflareSyncException('Worker URL is required.');
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({Map<String, String>? extra}) {
    if (_appKey.trim().isEmpty) {
      throw CloudflareSyncException(
        'This build is missing its app key. Reinstall the app from the current build.',
      );
    }
    return {'X-Lifelog-App-Key': _appKey, ...?extra};
  }

  Map<String, String> _authHeaders(String token, {Map<String, String>? extra}) {
    return _headers(extra: {'Authorization': 'Bearer $token', ...?extra});
  }

  Future<void> checkHealth(String baseUrl) async {
    final resp = await _http
        .get(_uri(baseUrl, '/api/health'), headers: _headers())
        .timeout(_controlTimeout);
    _throwForResponse(resp, fallback: 'Could not reach the sync server.');
  }

  Future<CloudflareSession> register({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _http
        .post(
          _uri(baseUrl, '/api/auth/register'),
          headers: _headers(extra: const {'Content-Type': 'application/json'}),
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(_controlTimeout);
    final data = _decodeJson(resp);
    _throwForResponse(
      resp,
      data: data,
      fallback: 'Could not create account.',
      keepNotFound: true,
    );
    final token = data['token'] as String?;
    final user = (data['username'] as String?)?.trim();
    if (token == null || token.isEmpty || user == null || user.isEmpty) {
      throw CloudflareSyncException('Invalid response from sync server.');
    }
    return CloudflareSession(
      token: token,
      username: user,
      expiresInSeconds: _sessionExpirySeconds(data),
      obtainedAt: DateTime.now(),
    );
  }

  Future<CloudflareSession> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _http
        .post(
          _uri(baseUrl, '/api/auth/login'),
          headers: _headers(extra: const {'Content-Type': 'application/json'}),
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(_controlTimeout);
    final data = _decodeJson(resp);
    _throwForResponse(
      resp,
      data: data,
      fallback: 'Could not sign in.',
      keepNotFound: true,
    );
    final token = data['token'] as String?;
    final user = (data['username'] as String?)?.trim();
    if (token == null || token.isEmpty || user == null || user.isEmpty) {
      throw CloudflareSyncException('Invalid response from sync server.');
    }
    return CloudflareSession(
      token: token,
      username: user,
      expiresInSeconds: _sessionExpirySeconds(data),
      obtainedAt: DateTime.now(),
    );
  }

  Future<CloudflareBackupMeta> getBackupMeta({
    required String baseUrl,
    required String token,
  }) async {
    final resp = await _http
        .get(_uri(baseUrl, '/api/backup/meta'), headers: _authHeaders(token))
        .timeout(_controlTimeout);
    final data = _decodeJson(resp);
    _throwForResponse(
      resp,
      data: data,
      fallback: 'Could not check cloud backup.',
      keepNotFound: true,
    );
    final rawExists = data['exists'];
    if (rawExists is! bool) {
      // Missing/unknown metadata must never be read as "no remote backup".
      throw CloudflareSyncException(
        'Could not confirm the cloud backup state.',
      );
    }
    if (!rawExists) return CloudflareBackupMeta(exists: false);
    return CloudflareBackupMeta(
      exists: true,
      size: (data['size'] as num?)?.toInt(),
      uploadedAt: DateTime.tryParse(data['uploadedAt'] as String? ?? ''),
      modifiedAt: DateTime.tryParse(data['modifiedAt'] as String? ?? ''),
      etag: data['etag'] as String?,
    );
  }

  Future<void> uploadBackup({
    required String baseUrl,
    required String token,
    required Uint8List bytes,
    UploadByteProgress? onByteProgress,
  }) {
    return _uploadBytes(
      baseUrl: baseUrl,
      token: token,
      bytes: bytes,
      target: 'backup',
      uri: _uri(baseUrl, '/api/backup'),
      fallback: 'Could not upload backup.',
      operation: CloudSyncOperation.backupUpload,
      onByteProgress: onByteProgress,
    );
  }

  Future<Uint8List> downloadBackup({
    required String baseUrl,
    required String token,
  }) async {
    final resp = await _http
        .get(_uri(baseUrl, '/api/backup'), headers: _authHeaders(token))
        .timeout(_controlTimeout);
    _throwForResponse(
      resp,
      fallback: 'Could not download backup.',
      keepNotFound: true,
    );
    if (resp.statusCode == 404) {
      throw CloudflareSyncException('No cloud backup found.');
    }
    return resp.bodyBytes;
  }

  Uri _mediaUri(String baseUrl, String id, CloudflareMediaKind kind) => _uri(
        baseUrl,
        '/api/media/${Uri.encodeComponent(id)}/${kind.pathSegment}',
      );

  Future<Uint8List> downloadMedia({
    required String baseUrl,
    required String token,
    required String id,
    required CloudflareMediaKind kind,
  }) async {
    final resp = await _http
        .get(_mediaUri(baseUrl, id, kind), headers: _authHeaders(token))
        .timeout(_controlTimeout);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      final data = _decodeJson(resp);
      throw CloudflareSyncException(_messageFrom(data) ?? 'Access denied.');
    }
    if (resp.statusCode == 404) {
      throw CloudflareSyncException('Media is not available in the cloud yet.');
    }
    _throwForResponse(
      resp,
      fallback: 'Could not download media.',
      keepNotFound: true,
    );
    return resp.bodyBytes;
  }

  /// Returns the stored encrypted byte length, or null when the object is
  /// absent. Used to avoid re-uploading unchanged media on every archive sync.
  Future<int?> mediaSize({
    required String baseUrl,
    required String token,
    required String id,
    required CloudflareMediaKind kind,
  }) async {
    final request = http.Request('HEAD', _mediaUri(baseUrl, id, kind))
      ..headers.addAll(_authHeaders(token));
    final streamed = await _http.send(request).timeout(_controlTimeout);
    final resp = await http.Response.fromStream(streamed)
        .timeout(_controlTimeout);
    if (resp.statusCode == 404) return null;
    _throwForResponse(
      resp,
      fallback: 'Could not check cloud media.',
      keepNotFound: true,
    );
    return int.tryParse(resp.headers['content-length'] ?? '');
  }

  Future<void> uploadMedia({
    required String baseUrl,
    required String token,
    required String id,
    required CloudflareMediaKind kind,
    required Uint8List bytes,
    UploadByteProgress? onByteProgress,
  }) {
    return _uploadBytes(
      baseUrl: baseUrl,
      token: token,
      bytes: bytes,
      target: 'media',
      mediaId: id,
      mediaKind: kind.pathSegment,
      uri: _mediaUri(baseUrl, id, kind),
      fallback: 'Could not upload media.',
      operation: CloudSyncOperation.mediaUpload,
      onByteProgress: onByteProgress,
    );
  }

  Future<void> deleteMedia({
    required String baseUrl,
    required String token,
    required String id,
    required CloudflareMediaKind kind,
  }) async {
    final request = http.Request('DELETE', _mediaUri(baseUrl, id, kind))
      ..headers.addAll(_authHeaders(token));
    final streamed = await _http.send(request).timeout(_controlTimeout);
    final resp = await http.Response.fromStream(streamed)
        .timeout(_controlTimeout);
    _throwForResponse(
      resp,
      fallback: 'Could not delete cloud media.',
      keepNotFound: true,
    );
  }

  /// Prefers the resumable Worker protocol. A Worker that does not implement it
  /// answers 404/405 and the original single PUT is used unchanged.
  Future<void> _uploadBytes({
    required String baseUrl,
    required String token,
    required Uint8List bytes,
    required String target,
    required Uri uri,
    required String fallback,
    required CloudSyncOperation operation,
    required UploadByteProgress? onByteProgress,
    String? mediaId,
    String? mediaKind,
  }) async {
    if (bytes.isEmpty) {
      onByteProgress?.call(0, 0);
      return;
    }

    final started = await _beginUpload(
      baseUrl: baseUrl,
      token: token,
      bytes: bytes,
      target: target,
      mediaId: mediaId,
      mediaKind: mediaKind,
      fallback: fallback,
    );
    if (started == null) {
      await _uploadLegacy(
        uri: uri,
        token: token,
        bytes: bytes,
        fallback: fallback,
        onByteProgress: onByteProgress,
      );
      return;
    }

    onByteProgress?.call(0, bytes.length);
    try {
      for (var part = 1; part <= started.partCount; part++) {
        final start = (part - 1) * started.partSize;
        final end = part == started.partCount
            ? bytes.length
            : (start + started.partSize).clamp(0, bytes.length);
        final resp = await _http
            .put(
              _uri(
                baseUrl,
                '/api/uploads/${Uri.encodeComponent(started.uploadId)}/parts/$part',
              ),
              headers: _authHeaders(
                token,
                extra: const {'Content-Type': 'application/octet-stream'},
              ),
              body: Uint8List.sublistView(bytes, start, end),
            )
            .timeout(_partTimeout);
        _throwForResponse(resp, fallback: 'Could not store upload part.');
        final data = _decodeJson(resp);
        final confirmed = (data['confirmedBytes'] as num?)?.toInt();
        final total = (data['totalBytes'] as num?)?.toInt() ?? bytes.length;
        // The Worker only reports bytes after R2 accepts the part. Trust its
        // cumulative count, but never let a bad response overstate progress.
        final safeConfirmed = confirmed == null
            ? end
            : confirmed.clamp(0, bytes.length);
        onByteProgress?.call(safeConfirmed, total.clamp(0, bytes.length));
      }

      final complete = await _http
          .post(
            _uri(
              baseUrl,
              '/api/uploads/${Uri.encodeComponent(started.uploadId)}/complete',
            ),
            headers: _authHeaders(
              token,
              extra: const {'Content-Type': 'application/json'},
            ),
            body: '{}',
          )
          .timeout(_controlTimeout);
      _throwForResponse(complete, fallback: 'Could not finish upload.');
      onByteProgress?.call(bytes.length, bytes.length);
    } catch (error) {
      // Best effort: a failed upload should not leave an open R2 multipart
      // session. Do not let cleanup hide the original error.
      unawaited(
        _abortUpload(baseUrl, token, started.uploadId).catchError((_) {}),
      );
      rethrow;
    }
  }

  Future<_StartedUpload?> _beginUpload({
    required String baseUrl,
    required String token,
    required Uint8List bytes,
    required String target,
    required String fallback,
    String? mediaId,
    String? mediaKind,
  }) async {
    final body = <String, dynamic>{
      'target': target,
      'size': bytes.length,
      if (target == 'media') ...{
        'id': mediaId,
        'mediaKind': mediaKind,
      },
    };
    final resp = await _http
        .post(
          _uri(baseUrl, '/api/uploads/begin'),
          headers: _authHeaders(
            token,
            extra: const {'Content-Type': 'application/json'},
          ),
          body: jsonEncode(body),
        )
        .timeout(_controlTimeout);
    final data = _decodeJson(resp);
    if (resp.statusCode == 404 || resp.statusCode == 405) return null;
    _throwForResponse(resp, data: data, fallback: fallback);

    final uploadId = data['uploadId'] as String?;
    final partSize = (data['partSize'] as num?)?.toInt();
    final partCount = (data['partCount'] as num?)?.toInt();
    if (uploadId == null ||
        uploadId.isEmpty ||
        partSize == null ||
        partSize <= 0 ||
        partSize > _maxAcceptedPartSize ||
        partCount == null ||
        partCount < 1) {
      // A 2xx without a usable protocol description is treated as an older
      // Worker; the legacy PUT below still carries exactly the same bytes.
      return null;
    }
    return _StartedUpload(
      uploadId: uploadId,
      partSize: partSize,
      partCount: partCount,
    );
  }

  Future<void> _abortUpload(
    String baseUrl,
    String token,
    String uploadId,
  ) async {
    final request = http.Request(
      'DELETE',
      _uri(baseUrl, '/api/uploads/${Uri.encodeComponent(uploadId)}'),
    )..headers.addAll(_authHeaders(token));
    final streamed = await _http.send(request).timeout(_controlTimeout);
    await http.Response.fromStream(streamed).timeout(_controlTimeout);
  }

  Future<void> _uploadLegacy({
    required Uri uri,
    required String token,
    required Uint8List bytes,
    required String fallback,
    required UploadByteProgress? onByteProgress,
  }) async {
    final request = http.StreamedRequest('PUT', uri);
    request.headers.addAll(
      _authHeaders(
        token,
        extra: const {'Content-Type': 'application/octet-stream'},
      ),
    );

    // Start the send first so the HTTP client attaches to the request body
    // stream before bytes are written. Closing the sink earlier can leave a
    // synchronous StreamController with no listener and hang the PUT.
    final response = _http.send(request);
    try {
      const chunkSize = 64 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = offset + chunkSize < bytes.length
            ? offset + chunkSize
            : bytes.length;
        request.sink.add(Uint8List.sublistView(bytes, offset, end));
      }
    } finally {
      await request.sink.close().timeout(_legacyUploadTimeout);
    }

    final streamed = await response.timeout(_legacyUploadTimeout);
    final resp = await http.Response.fromStream(streamed)
        .timeout(_legacyUploadTimeout);
    _throwForResponse(resp, fallback: fallback);
    // Only now has the Worker accepted the whole body.
    onByteProgress?.call(bytes.length, bytes.length);
  }

  Map<String, dynamic> _decodeJson(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  String? _messageFrom(Map<String, dynamic> data) {
    final msg = data['error'] ?? data['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg.trim();
    return null;
  }

  String _friendlyHttpError(http.Response resp, {required String fallback}) {
    if (resp.statusCode == 401) return 'Session expired. Please sign in again.';
    if (resp.statusCode == 403) return 'Access denied.';
    if (resp.statusCode >= 500) {
      return 'Sync server error. Please try again later.';
    }
    return fallback;
  }

  void _throwForResponse(
    http.Response resp, {
    Map<String, dynamic>? data,
    required String fallback,
    bool keepNotFound = false,
  }) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    if (resp.statusCode == 404 && keepNotFound) return;
    final decoded = data ?? _decodeJson(resp);
    throw CloudflareSyncException(
      _messageFrom(decoded) ??
          _friendlyHttpError(resp, fallback: fallback),
    );
  }
}
