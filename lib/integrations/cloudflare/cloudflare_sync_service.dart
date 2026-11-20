import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Reports bytes confirmed by the server. It is only called after a 2xx
/// response, so a caller can present the value as actually uploaded.
typedef UploadByteProgress = void Function(int sent, int total);

const Duration _syncTimeout = Duration(seconds: 30);

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

String friendlyCloudflareSyncError(Object error) {
  if (error is TimeoutException) {
    return 'The sync server took too long to respond. Check your connection and try again.';
  }
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

/// Client for the Lifelog Cloudflare Worker sync API.
/// The Worker stores only client-side encrypted backup blobs and auth metadata.
class CloudflareSyncService {
  CloudflareSyncService({http.Client? httpClient}) : _http = httpClient ?? http.Client();
  final http.Client _http;

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

  Map<String, String> _authHeaders(String token, {Map<String, String>? extra}) {
    return {
      'Authorization': 'Bearer $token',
      ...?extra,
    };
  }

  Future<void> checkHealth(String baseUrl) async {
    final resp = await _http
        .get(_uri(baseUrl, '/api/health'))
        .timeout(_syncTimeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_friendlyHttpError(resp, fallback: 'Could not reach the sync server.'));
    }
  }

  Future<CloudflareSession> register({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _http
        .post(
          _uri(baseUrl, '/api/auth/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(_syncTimeout);
    final data = _decodeJson(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not create account.'));
    }
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
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username.trim(), 'password': password}),
        )
        .timeout(_syncTimeout);
    final data = _decodeJson(resp);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not sign in.'));
    }
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
        .get(
          _uri(baseUrl, '/api/backup/meta'),
          headers: _authHeaders(token),
        )
        .timeout(_syncTimeout);
    final data = _decodeJson(resp);
    if (resp.statusCode == 401) {
      throw CloudflareSyncException('Session expired. Please sign in again.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not check cloud backup.'));
    }
    final rawExists = data['exists'];
    if (rawExists is! bool) {
      // Missing/unknown metadata must never be read as "no remote backup".
      throw CloudflareSyncException('Could not confirm the cloud backup state.');
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
  }) async {
    final request = http.StreamedRequest(
      'PUT',
      _uri(baseUrl, '/api/backup'),
    );
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

    // Stream the exact same bytes as the old single PUT; Workers read the
    // body with arrayBuffer(), so chunked transfer stays wire-compatible.
    // Writing to the sink only queues bytes locally: never report them as sent
    // before the Worker answers.
    try {
      const chunkSize = 64 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = offset + chunkSize < bytes.length
            ? offset + chunkSize
            : bytes.length;
        request.sink.add(Uint8List.sublistView(bytes, offset, end));
      }
    } finally {
      await request.sink.close().timeout(_syncTimeout);
    }

    final streamed = await response.timeout(_syncTimeout);
    final resp = await http.Response
        .fromStream(streamed)
        .timeout(_syncTimeout);
    if (resp.statusCode == 401) {
      throw CloudflareSyncException('Session expired. Please sign in again.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final data = _decodeJson(resp);
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not upload backup.'));
    }
    // The Worker accepted the whole body. Only now is byte progress truthful.
    onByteProgress?.call(bytes.length, bytes.length);
  }

  Future<Uint8List> downloadBackup({
    required String baseUrl,
    required String token,
  }) async {
    final resp = await _http
        .get(
          _uri(baseUrl, '/api/backup'),
          headers: _authHeaders(token),
        )
        .timeout(_syncTimeout);
    if (resp.statusCode == 401) {
      throw CloudflareSyncException('Session expired. Please sign in again.');
    }
    if (resp.statusCode == 404) {
      throw CloudflareSyncException('No cloud backup found.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final data = _decodeJson(resp);
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not download backup.'));
    }
    return resp.bodyBytes;
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
    if (resp.statusCode == 404) return 'Not found.';
    if (resp.statusCode >= 500) return 'Sync server error. Please try again later.';
    return fallback;
  }
}
