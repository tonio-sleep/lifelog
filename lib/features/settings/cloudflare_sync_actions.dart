import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../integrations/cloudflare/cloudflare_sync_service.dart';

Future<void> connectCloudflareSync(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final result = await showLifelogSheet<_CloudflareAuthResult>(
    context,
    builder: (_) => _CloudflareConnectSheet(
      initialUrl: settings.cloudflareWorkerUrl ?? '',
      initialUsername: settings.cloudflareUsername ?? '',
    ),
  );
  if (result == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final baseUrl = CloudflareSyncService.normalizeBaseUrl(result.workerUrl);
  final username = result.username.trim().toLowerCase();
  final password = result.password;

  final session = await guard<CloudflareSession>(
    context,
    () async {
      if (result.createAccount) {
        return services.cloudflareSync.register(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
      } else {
        return services.cloudflareSync.login(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
      }
    }(),
    errorPrefix: result.createAccount
        ? 'Could not create sync account'
        : 'Could not sign in',
  );
  if (session == null || !context.mounted) return;

  await guard(
    context,
    ref.read(settingsProvider.notifier).saveCloudflareSession(
          workerUrl: baseUrl,
          username: session.username,
          sessionJson: jsonEncode(session.toJson()),
        ),
    errorPrefix: 'Could not save sync session',
  );
  if (!context.mounted) return;
  showSnack(
    context,
    result.createAccount
        ? 'Cloudflare sync account created.'
        : 'Signed in to Cloudflare sync.',
  );

  // If a cloud backup exists and local archive is empty, offer restore.
  final archive = ref.read(archiveProvider);
  if (archive.isEmpty) {
    try {
      final meta = await services.cloudflareSync.getBackupMeta(
        baseUrl: baseUrl,
        token: session.token,
      );
      if (meta.exists && context.mounted) {
        final when = meta.modifiedAt ?? meta.uploadedAt;
        final doRestore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cloud backup found'),
            content: Text(
              when != null
                  ? 'A synced backup was found (updated ${formatDayLong(when)} ${formatTime(when)}). Restore it to this device?'
                  : 'A synced backup was found. Restore it to this device?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
            ],
          ),
        );
        if (doRestore == true && context.mounted) {
          await restoreFromCloudflare(context, ref);
        }
      }
    } catch (_) {
      // ignore after successful connect
    }
  }
}

Future<void> disconnectCloudflareSync(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Disconnect Cloudflare sync?'),
      content: const Text(
        'This removes the sync account session from this device. '
        'Your encrypted backup stored in Cloudflare is not deleted.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await guard(
    context,
    ref.read(settingsProvider.notifier).disconnectCloudflareSync(),
    errorPrefix: 'Could not disconnect',
  );
  if (context.mounted) showSnack(context, 'Cloudflare sync disconnected.');
}

Future<_CloudflareAuthContext?> _requireCloudflareSession(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  if (!settings.cloudflareConnected) {
    showSnack(context, 'Sign in to Cloudflare sync first.');
    return null;
  }
  final sessionJson = await ref.read(settingsProvider.notifier).cloudflareSessionJson();
  if (sessionJson == null) {
    if (context.mounted) showSnack(context, 'Sync session missing. Please sign in again.');
    return null;
  }
  try {
    final map = jsonDecode(sessionJson) as Map<String, dynamic>;
    final token = (map['token'] as String?)?.trim() ?? '';
    final workerUrl = (settings.cloudflareWorkerUrl ?? '').trim();
    if (token.isEmpty || workerUrl.isEmpty) {
      if (context.mounted) showSnack(context, 'Sync session missing. Please sign in again.');
      return null;
    }
    return _CloudflareAuthContext(workerUrl: workerUrl, token: token);
  } catch (_) {
    if (context.mounted) showSnack(context, 'Sync session is invalid. Please sign in again.');
    return null;
  }
}

Future<void> syncToCloudflare(BuildContext context, WidgetRef ref) async {
  final auth = await _requireCloudflareSession(context, ref);
  if (auth == null || !context.mounted) return;

  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Backup passphrase',
    subtitle:
        'Enter the passphrase to encrypt this cloud backup (including media). This is different from your Cloudflare account password. '\n        'You will need this passphrase to restore on another device.',
    confirm: true,
  );
  if (passphrase == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final bytes = await guard<Uint8List>(
    context,
    services.backup.createBackup(\n      archive: ref.read(archiveProvider),\n      passphrase: passphrase,\n      mediaStore: services.mediaStore,\n    ),
    errorPrefix: 'Could not create backup',
  );
  if (bytes == null || !context.mounted) return;

  await guard(
    context,
    services.cloudflareSync.uploadBackup(
      baseUrl: auth.workerUrl,
      token: auth.token,
      bytes: bytes,
    ),
    errorPrefix: 'Could not upload backup',
  );
  if (!context.mounted) return;

  await ref.read(settingsProvider.notifier).recordCloudflareSync(DateTime.now());
  await ref.read(settingsProvider.notifier).markBackup(DateTime.now());
  if (context.mounted) {
    showSnack(context, 'Encrypted backup synced to Cloudflare. Keep your backup passphrase safe.');
  }
}

Future<void> restoreFromCloudflare(BuildContext context, WidgetRef ref) async {
  final auth = await _requireCloudflareSession(context, ref);
  if (auth == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final meta = await guard<CloudflareBackupMeta>(
    context,
    services.cloudflareSync.getBackupMeta(
      baseUrl: auth.workerUrl,
      token: auth.token,
    ),
    errorPrefix: 'Could not check cloud backup',
  );
  if (meta == null) return;
  if (!meta.exists) {
    if (context.mounted) showSnack(context, 'No cloud backup found.');
    return;
  }
  if (!context.mounted) return;

  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Enter backup passphrase',
    subtitle:
        'Enter the passphrase used to encrypt the cloud backup. This is different from your Cloudflare account password.',
    confirm: false,
  );
  if (passphrase == null || !context.mounted) return;

  final bytes = await guard<Uint8List>(
    context,
    services.cloudflareSync.downloadBackup(
      baseUrl: auth.workerUrl,
      token: auth.token,
    ),
    errorPrefix: 'Could not download backup',
  );
  if (bytes == null || !context.mounted) return;

  final contents = await guard(
    context,
    services.backup.readBackup(bytes: bytes, passphrase: passphrase),
    errorPrefix: 'Could not decrypt backup',
  );
  if (contents == null || !context.mounted) return;

  final mediaMsg = contents.includesMedia
      ? 'This backup includes encrypted media files.'
      : 'This backup does not include media files.';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore from Cloudflare sync?'),
      content: Text(
        'This will replace the current archive and media vault on this device with the cloud backup '
        '(${contents.counts['journalEntries']} entries, ${contents.counts['photos']} media records). '
        '$mediaMsg Local data not in the backup will be lost.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  await guard(
    context,
    ref.read(archiveProvider.notifier).restoreArchive(
          contents.archive,
          mediaFiles: contents.mediaFiles,
        ),
    errorPrefix: 'Could not restore archive',
  );
  await ref.read(settingsProvider.notifier).recordCloudflareSync(DateTime.now());
  if (context.mounted) showSnack(context, 'Restored data from Cloudflare sync.');
}

class _CloudflareAuthContext {
  const _CloudflareAuthContext({required this.workerUrl, required this.token});
  final String workerUrl;
  final String token;
}

class _CloudflareAuthResult {
  const _CloudflareAuthResult({
    required this.workerUrl,
    required this.username,
    required this.password,
    required this.createAccount,
  });
  final String workerUrl;
  final String username;
  final String password;
  final bool createAccount;
}

class _CloudflareConnectSheet extends StatefulWidget {
  const _CloudflareConnectSheet({
    required this.initialUrl,
    required this.initialUsername,
  });
  final String initialUrl;
  final String initialUsername;

  @override
  State<_CloudflareConnectSheet> createState() => _CloudflareConnectSheetState();
}

class _CloudflareConnectSheetState extends State<_CloudflareConnectSheet> {
  late final TextEditingController _url = TextEditingController(text: widget.initialUrl);
  late final TextEditingController _username = TextEditingController(text: widget.initialUsername);
  final TextEditingController _password = TextEditingController();
  bool _createAccount = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    if (url.isEmpty) {
      setState(() => _error = 'Enter your Worker URL.');
      return;
    }
    if (username.length < 2) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (password.length < 10) {
      setState(() => _error = _createAccount
          ? 'Use a password with at least 10 characters.'
          : 'Enter your password.');
      return;
    }
    Navigator.of(context).pop(_CloudflareAuthResult(
      workerUrl: url,
      username: username,
      password: password,
      createAccount: _createAccount,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title: _createAccount ? 'Create Cloudflare sync account' : 'Sign in to Cloudflare sync',
          subtitle: 'Use your own Cloudflare Worker to store encrypted backups',
        ),
        _InfoLine(
          icon: Icons.lock_outline_rounded,
          text: 'Backups are encrypted on this device with your backup passphrase before upload. The server stores encrypted data only.',
        ),
        const SizedBox(height: Insets.sm),
        _InfoLine(
          icon: Icons.shield_outlined,
          text: 'Use a strong, unique account password. Session tokens are stored encrypted on this device. HTTPS Worker URLs are required.',
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Worker URL',
            hintText: 'https://your-worker.workers.dev',
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username'),
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: _createAccount ? 'Create account password' : 'Password',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            Expanded(
              child: SegmentedPills<bool>(
                values: const [false, true],
                selected: _createAccount,
                labelFor: (v) => v ? 'Create account' : 'Sign in',
                onChanged: (v) => setState(() {
                  _createAccount = v;
                  _error = null;
                }),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.sm),
          Text(_error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: Insets.md),
        if (_createAccount)
          Text(
            'Create account works once for a new personal Worker (single-user). Your backup passphrase is asked separately when syncing/restoring.',
            style: text.bodySmall?.copyWith(color: palette.mutedText),
          ),
        const SizedBox(height: Insets.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: Icon(_createAccount ? Icons.person_add_alt_1_rounded : Icons.login_rounded, size: 18),
            label: Text(_createAccount ? 'Create account' : 'Sign in'),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.mutedText),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(text, style: context.text.bodySmall?.copyWith(color: palette.mutedText)),
        ),
      ],
    );
  }
}

Future<String?> _askSyncPassphrase(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool confirm,
}) async {
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: p1,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Backup passphrase', errorText: error),
              autofocus: true,
            ),
            if (confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: p2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm backup passphrase'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final a = p1.text;
              if (a.trim().length < 8) {
                setState(() => error = 'Use at least 8 characters.');
                return;
              }
              if (confirm && a != p2.text) {
                setState(() => error = 'Passphrases do not match.');
                return;
              }
              Navigator.pop(ctx, a);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

