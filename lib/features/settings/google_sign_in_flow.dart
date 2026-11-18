import 'dart:io';

import 'package:flutter/material.dart';

import '../../integrations/google_drive/google_drive_service.dart';
import 'google_webview_sign_in.dart';

/// Platform-aware Google sign-in: in-app WebView on Windows, browser flow elsewhere.
Future<GoogleDriveAuthResult?> signInWithGoogle(
  BuildContext context, {
  required GoogleDriveService service,
  required String clientId,
  required String clientSecret,
}) async {
  if (Platform.isWindows) {
    return showGoogleWebViewSignIn(
      context,
      service: service,
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }
  // Fallback: external browser + loopback (works on iOS/macOS/Android/Linux where supported)
  return service.signIn(clientId: clientId, clientSecret: clientSecret);
}
