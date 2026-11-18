import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
      expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt(),
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
    return v;
  }

  Uri _uri(String baseUrl, String path) {
    final base = normalizeBaseUrl(baseUrl);
    if (base.isEmpty) throw CloudflareSyncException('Worker URL is required.');
    return Uri.parse('$base$path');
  }

  Map<String, String> _authHeaders(String token, {Map<String, String>? extra}) {
    return {
      'Authorization': 'Bearer $token',
      if (extra != null) ...extra,
    };
  }

  Future<void> checkHealth(String baseUrl) async {
    final resp = await _http.get(_uri(baseUrl, '/api/health'));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_friendlyHttpError(resp, fallback: 'Could not reach the sync server.'));
    }
  }

  Future<CloudflareSession> register({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _http.post(
      _uri(baseUrl, '/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username.trim(), 'password': password}),
    );
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
      expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt(),
      obtainedAt: DateTime.now(),
    );
  }

  Future<CloudflareSession> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final resp = await _http.post(
      _uri(baseUrl, '/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username.trim(), 'password': password}),
    );
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
      expiresInSeconds: (data['expiresInSeconds'] as num?)?.toInt(),
      obtainedAt: DateTime.now(),
    );
  }

  Future<CloudflareBackupMeta> getBackupMeta({
    required String baseUrl,
    required String token,
  }) async {
    final resp = await _http.get(
      _uri(baseUrl, '/api/backup/meta'),
      headers: _authHeaders(token),
    );
    final data = _decodeJson(resp);
    if (resp.statusCode == 401) {
      throw CloudflareSyncException('Session expired. Please sign in again.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not check cloud backup.'));
    }
    final exists = data['exists'] == true;
    if (!exists) return CloudflareBackupMeta(exists: false);
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
  }) async {
    final resp = await _http.put(
      _uri(baseUrl, '/api/backup'),
      headers: _authHeaders(token, extra: const {'Content-Type': 'application/octet-stream'}),
      body: bytes,
    );
    if (resp.statusCode == 401) {
      throw CloudflareSyncException('Session expired. Please sign in again.');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final data = _decodeJson(resp);
      throw CloudflareSyncException(_messageFrom(data) ?? _friendlyHttpError(resp, fallback: 'Could not upload backup.'));
    }
  }

  Future<Uint8List> downloadBackup({
    required String baseUrl,
    required String token,
  }) async {
    final resp = await _http.get(
      _uri(baseUrl, '/api/backup'),
      headers: _authHeaders(token),
    );
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
