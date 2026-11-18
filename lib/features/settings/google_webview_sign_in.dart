import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../app/widgets/common.dart';
import '../../integrations/google_drive/google_drive_service.dart';

/// Shows an in-app WebView for Google OAuth sign-in and returns the auth result.
/// Windows-only (uses webview_windows). Use [signInWithGoogle] for platform-aware flow.
Future<GoogleDriveAuthResult?> showGoogleWebViewSignIn(
  BuildContext context, {
  required GoogleDriveService service,
  required String clientId,
  required String clientSecret,
}) async {
  if (!Platform.isWindows) {
    return service.signIn(clientId: clientId, clientSecret: clientSecret);
  }
  final req = service.buildWebAuthRequest(clientId: clientId);
  final code = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _GoogleWebViewDialog(
      authUrl: req.url.toString(),
      redirectUri: req.redirectUri,
    ),
  );
  if (code == null || code.isEmpty) return null;
  if (!context.mounted) return null;
  return guard<GoogleDriveAuthResult>(
    context,
    service.exchangeAuthCode(
      clientId: clientId,
      clientSecret: clientSecret,
      code: code,
      redirectUri: req.redirectUri,
    ),
    errorPrefix: 'Google sign-in failed',
  );
}

class _GoogleWebViewDialog extends StatefulWidget {
  const _GoogleWebViewDialog({
    required this.authUrl,
    required this.redirectUri,
  });
  final String authUrl;
  final String redirectUri;

  @override
  State<_GoogleWebViewDialog> createState() => _GoogleWebViewDialogState();
}

class _GoogleWebViewDialogState extends State<_GoogleWebViewDialog> {
  final _controller = WebviewController();
  bool _ready = false;
  bool _completing = false;
  String? _error;
  StreamSubscription? _urlSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      _urlSub = _controller.url.listen(_handleUrl);
      await _controller.setBackgroundColor(Colors.white);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.loadUrl(widget.authUrl);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open sign-in view: $e');
    }
  }

  void _handleUrl(String? url) {
    if (url == null || _completing) return;
    if (!url.startsWith(widget.redirectUri)) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final code = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];
    if (code != null && code.isNotEmpty) {
      _completing = true;
      if (mounted) Navigator.of(context).pop(code);
    } else if (error != null) {
      _completing = true;
      if (mounted) {
        showSnack(context, 'Google sign-in cancelled: $error');
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _urlSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        height: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.login_rounded, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sign in with Google',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : !_ready
                      ? const Center(child: CircularProgressIndicator())
                      : Webview(_controller),
            ),
          ],
        ),
      ),
    );
  }
}
