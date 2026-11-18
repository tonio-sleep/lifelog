import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../integrations/google_drive/google_drive_service.dart';
import 'google_webview_sign_in.dart';

/// Platform-aware Google sign-in.
/// - iOS/Android/macOS: native Google Sign-In (avoids blocked loopback redirect flow).
/// - Windows: in-app WebView flow.
/// - Other desktop platforms: browser-based flow (may require compatible OAuth client setup).
Future<GoogleDriveAuthResult?> signInWithGoogle(
  BuildContext context, {
  required GoogleDriveService service,
  required String clientId,
  required String clientSecret,
}) async {
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
    return service.signInNative(clientId: clientId);
  }
  if (!kIsWeb && Platform.isWindows) {
    return showGoogleWebViewSignIn(
      context,
      service: service,
      clientId: clientId,
      clientSecret: clientSecret,
    );
  }
  // Fallback: browser-based flow.
  return service.signIn(clientId: clientId, clientSecret: clientSecret);
}
