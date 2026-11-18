import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart' as gsi;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveException implements Exception {
  GoogleDriveException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

class GoogleDriveAuthResult {
  GoogleDriveAuthResult({
    required this.accountEmail,
    required this.authJson,
  });
  final String accountEmail;
  final String authJson; // serialized AccessCredentials JSON
}

class GoogleDriveSyncFile {
  GoogleDriveSyncFile({required this.id, this.modifiedTime});
  final String id;
  final DateTime? modifiedTime;
}

/// Handles Google OAuth (desktop loopback) and Drive appData sync for backups.
class GoogleDriveService {
  static const _scopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
    'https://www.googleapis.com/auth/userinfo.email',
    'openid',
  ];

  static const _backupFileName = 'lifelog-sync-backup.lifelog';

  auth.ClientId _clientId(String id, String secret) =>
      auth.ClientId(id.trim(), secret.trim().isEmpty ? null : secret.trim());

  Future<void> _prompt(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw GoogleDriveException(
        'Could not open the browser for Google sign-in. Open this URL manually:\n$url',
      );
    }
  }

  /// Signs in with Google via system browser and returns serialized credentials.
  /// Uses loopback on desktop where supported; on mobile platforms prefer [signInNative].
  Future<GoogleDriveAuthResult> signIn({
    required String clientId,
    required String clientSecret,
  }) async {
    if (clientId.trim().isEmpty) {
      throw GoogleDriveException('Google OAuth Client ID is required.');
    }
    final baseClient = http.Client();
    try {
      final credentials = await auth.obtainAccessCredentialsViaUserConsent(
        _clientId(clientId, clientSecret),
        _scopes,
        baseClient,
        _prompt,
      );
      return await _resultFromCredentials(baseClient, credentials);
    } on GoogleDriveException {
      rethrow;
    } catch (e) {
      final msg = '$e';
      if (msg.contains('loopback') || msg.contains('invalid_request')) {
        throw GoogleDriveException(
          'Google sign-in could not be completed with this method on this device. '
          'On iPhone/iPad/Android, use the app\'s native Google sign-in flow. '
          'On desktop, use a compatible Google OAuth client configuration.',
          e,
        );
      }
      throw GoogleDriveException('Google sign-in failed: $e', e);
    } finally {
      baseClient.close();
    }
  }

  /// Native Google sign-in (iOS/Android/macOS) using the google_sign_in plugin.
  /// Avoids loopback redirect URIs which are blocked for mobile OAuth clients.
  Future<GoogleDriveAuthResult> signInNative({
    required String clientId,
  }) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      throw GoogleDriveException('Native Google sign-in is not available on this platform.');
    }
    if (clientId.trim().isEmpty) {
      throw GoogleDriveException('Google OAuth Client ID is required.');
    }
    final signIn = gsi.GoogleSignIn.instance;
    try {
      // Initialize with the app's OAuth client ID (iOS client on iOS).
      try {
        await signIn.initialize(clientId: clientId.trim());
      } catch (_) {
        // May already be initialized; continue with existing initialization.
      }

      // Ensure a clean interactive sign-in attempt.
      try {
        await signIn.disconnect();
      } catch (_) {
        try {
          await signIn.signOut();
        } catch (_) {}
      }

      final account = await signIn.authenticate();
      // Request Drive scopes and obtain an access token.
      final authorization = await account.authorizationClient.authorizeScopes(_scopes);
      final accessToken = authorization.accessToken;
      if (accessToken.isEmpty) {
        throw GoogleDriveException('No access token returned by Google sign-in.');
      }

      String? idToken;
      try {
        idToken = account.authentication.idToken;
      } catch (_) {}

      final email = account.email.trim().isNotEmpty ? account.email.trim() : 'Google account';
      final credentials = auth.AccessCredentials(
        auth.AccessToken(
          'Bearer',
          accessToken,
          DateTime.now().toUtc().add(const Duration(minutes: 55)),
        ),
        null, // no refresh token from this native flow; reconnect if the session expires
        _scopes,
        idToken: idToken,
      );
      return GoogleDriveAuthResult(
        accountEmail: email,
        authJson: jsonEncode(_credentialsToJson(credentials)),
      );
    } on gsi.GoogleSignInException catch (e) {
      if (e.code == gsi.GoogleSignInExceptionCode.canceled) {
        throw GoogleDriveException('Google sign-in was cancelled.');
      }
      throw GoogleDriveException('Google sign-in failed: ${e.description ?? e.code.name}', e);
    } on GoogleDriveException {
      rethrow;
    } catch (e) {
      throw GoogleDriveException('Google sign-in failed: $e', e);
    }
  }

  /// Builds an OAuth authorization URL for in-app WebView sign-in.
  /// Uses loopback redirect URI; the caller should intercept navigation to
  /// [redirectUri] and pass the `code` query parameter to [exchangeAuthCode].
  ({Uri url, String redirectUri}) buildWebAuthRequest({
    required String clientId,
  }) {
    final port = 8567 + Random().nextInt(2000);
    final redirectUri = 'http://127.0.0.1:$port';
    final params = {
      'client_id': clientId.trim(),
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent select_account',
      'include_granted_scopes': 'true',
    };
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', params);
    return (url: url, redirectUri: redirectUri);
  }

  /// Exchanges an authorization code (captured from WebView redirect) for tokens.
  Future<GoogleDriveAuthResult> exchangeAuthCode({
    required String clientId,
    required String clientSecret,
    required String code,
    required String redirectUri,
  }) async {
    final baseClient = http.Client();
    try {
      final body = {
        'client_id': clientId.trim(),
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };
      if (clientSecret.trim().isNotEmpty) {
        body['client_secret'] = clientSecret.trim();
      }
      final resp = await baseClient.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (resp.statusCode != 200) {
        throw GoogleDriveException('Token exchange failed (${resp.statusCode}): ${resp.body}');
      }
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) {
        throw GoogleDriveException('Invalid token response.');
      }
      final access = data['access_token'] as String?;
      final tokenType = data['token_type'] as String? ?? 'Bearer';
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      final refresh = data['refresh_token'] as String?;
      final idToken = data['id_token'] as String?;
      if (access == null) {
        throw GoogleDriveException('No access token returned. Please try again.');
      }
      final credentials = auth.AccessCredentials(
        auth.AccessToken(
          tokenType,
          access,
          DateTime.now().toUtc().add(Duration(seconds: expiresIn - 30)),
        ),
        refresh,
        _scopes,
        idToken: idToken,
      );
      return await _resultFromCredentials(baseClient, credentials);
    } on GoogleDriveException {
      rethrow;
    } catch (e) {
      throw GoogleDriveException('Google sign-in failed: $e', e);
    } finally {
      baseClient.close();
    }
  }

  Future<GoogleDriveAuthResult> _resultFromCredentials(
    http.Client baseClient,
    auth.AccessCredentials credentials,
  ) async {
    final authJson = jsonEncode(_credentialsToJson(credentials));
    String email = 'Google account';
    try {
      final authed = auth.authenticatedClient(baseClient, credentials);
      final resp = await authed.get(Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['email'] is String) {
          email = data['email'] as String;
        }
      }
      authed.close();
    } catch (_) {}
    return GoogleDriveAuthResult(accountEmail: email, authJson: authJson);
  }

  Map<String, dynamic> _credentialsToJson(auth.AccessCredentials c) => {
        'accessToken': {
          'type': c.accessToken.type,
          'data': c.accessToken.data,
          'expiry': c.accessToken.expiry.toUtc().toIso8601String(),
        },
        'refreshToken': c.refreshToken,
        'scopes': c.scopes,
        'idToken': c.idToken,
      };

  auth.AccessCredentials _credentialsFromJson(Map<String, dynamic> json) {
    final at = json['accessToken'] as Map<String, dynamic>;
    return auth.AccessCredentials(
      auth.AccessToken(
        at['type'] as String? ?? 'Bearer',
        at['data'] as String,
        DateTime.parse(at['expiry'] as String).toUtc(),
      ),
      json['refreshToken'] as String?,
      (json['scopes'] as List?)?.whereType<String>().toList() ?? _scopes,
      idToken: json['idToken'] as String?,
    );
  }

  /// Returns an authenticated HTTP client, refreshing tokens if needed.
  /// If refreshed, [onRefreshed] is called with new auth JSON to persist.
  Future<_Authed> _authedClient({
    required String clientId,
    required String clientSecret,
    required String authJson,
    required Future<void> Function(String newAuthJson) onRefreshed,
  }) async {
    final decoded = jsonDecode(authJson);
    if (decoded is! Map<String, dynamic>) {
      throw GoogleDriveException('Stored Google credentials are invalid. Please sign in again.');
    }
    var creds = _credentialsFromJson(decoded);
    final id = _clientId(clientId, clientSecret);
    final base = http.Client();
    try {
      if (creds.accessToken.expiry.isBefore(DateTime.now().toUtc().add(const Duration(minutes: 2)))) {
        if (creds.refreshToken == null) {
          throw GoogleDriveException('Google session expired. Please reconnect your Google account and try again.');
        }
        creds = await auth.refreshCredentials(id, creds, base);
        await onRefreshed(jsonEncode(_credentialsToJson(creds)));
      }
      final client = auth.authenticatedClient(base, creds);
      return _Authed(base: base, client: client);
    } catch (e) {
      base.close();
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException('Could not authenticate with Google: $e', e);
    }
  }

  Future<GoogleDriveSyncFile?> findRemoteBackup({
    required String clientId,
    required String clientSecret,
    required String authJson,
    required Future<void> Function(String newAuthJson) onRefreshed,
  }) async {
    final authed = await _authedClient(
      clientId: clientId,
      clientSecret: clientSecret,
      authJson: authJson,
      onRefreshed: onRefreshed,
    );
    try {
      final api = drive.DriveApi(authed.client);
      final list = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_backupFileName' and trashed=false",
        $fields: 'files(id,name,modifiedTime)',
        pageSize: 5,
      );
      final files = list.files ?? const <drive.File>[];
      if (files.isEmpty) return null;
      // pick most recently modified
      files.sort((a, b) {
        final at = a.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      final f = files.first;
      return GoogleDriveSyncFile(id: f.id!, modifiedTime: f.modifiedTime);
    } finally {
      authed.close();
    }
  }

  Future<GoogleDriveSyncFile> uploadBackup({
    required String clientId,
    required String clientSecret,
    required String authJson,
    required Uint8List bytes,
    String? existingFileId,
    required Future<void> Function(String newAuthJson) onRefreshed,
  }) async {
    final authed = await _authedClient(
      clientId: clientId,
      clientSecret: clientSecret,
      authJson: authJson,
      onRefreshed: onRefreshed,
    );
    try {
      final api = drive.DriveApi(authed.client);
      final media = drive.Media(Stream.value(bytes), bytes.length);
      drive.File result;
      if (existingFileId != null && existingFileId.isNotEmpty) {
        try {
          result = await api.files.update(
            drive.File(),
            existingFileId,
            uploadMedia: media,
            $fields: 'id,modifiedTime',
          );
        } catch (_) {
          // file might be gone; create new
          result = await api.files.create(
            drive.File(name: _backupFileName, parents: const ['appDataFolder']),
            uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
            $fields: 'id,modifiedTime',
          );
        }
      } else {
        result = await api.files.create(
          drive.File(name: _backupFileName, parents: const ['appDataFolder']),
          uploadMedia: media,
          $fields: 'id,modifiedTime',
        );
      }
      return GoogleDriveSyncFile(id: result.id!, modifiedTime: result.modifiedTime);
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException('Could not upload backup to Google Drive: $e', e);
    } finally {
      authed.close();
    }
  }

  Future<Uint8List> downloadBackup({
    required String clientId,
    required String clientSecret,
    required String authJson,
    required String fileId,
    required Future<void> Function(String newAuthJson) onRefreshed,
  }) async {
    final authed = await _authedClient(
      clientId: clientId,
      clientSecret: clientSecret,
      authJson: authJson,
      onRefreshed: onRefreshed,
    );
    try {
      final api = drive.DriveApi(authed.client);
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = await media.stream.toList();
      final builder = BytesBuilder(copy: false);
      for (final c in chunks) {
        builder.add(c);
      }
      return builder.takeBytes();
    } catch (e) {
      if (e is GoogleDriveException) rethrow;
      throw GoogleDriveException('Could not download backup from Google Drive: $e', e);
    } finally {
      authed.close();
    }
  }
}

class _Authed {
  _Authed({required this.base, required this.client});
  final http.Client base;
  final http.Client client;
  void close() {
    try { client.close(); } catch (_) {}
    try { base.close(); } catch (_) {}
  }
}
