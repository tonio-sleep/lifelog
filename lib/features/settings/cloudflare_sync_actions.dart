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
import '../../domain/models/settings.dart';
import '../../integrations/cloudflare/cloudflare_sync_service.dart';
import '../../integrations/cloudflare/sync_status.dart';

bool _isSessionExpired(CloudflareSyncException e) {
  final m = e.message.toLowerCase();
  return m.contains('session expired') ||
      m.contains('unauthorized') ||
      m.contains('sign in again');
}

Future<void> _handleAuthFailure(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  // Keep the account, Worker URL and last-sync time. Only the token is no
  // longer accepted. Local data is untouched.
  ref.read(syncSessionRejectedProvider.notifier).reject();
  showSnack(context, 'Your sync session ended. Sign in again to continue.');
  await connectCloudflareSync(context, ref, initialCreateAccount: false);
}

/// Open the sign-in / create-account flow.
Future<void> connectCloudflareSync(
  BuildContext context,
  WidgetRef ref, {
  bool initialCreateAccount = false,
}) async {
  final settings = ref.read(settingsProvider);
  final initialUrl = (settings.cloudflareWorkerUrl ?? '').trim().isEmpty
      ? AppSettings.defaultCloudflareWorkerUrl
      : settings.cloudflareWorkerUrl!.trim();
  final result = await showLifelogSheet<_CloudflareAuthResult>(
    context,
    builder: (_) => _CloudflareConnectSheet(
      initialUrl: initialUrl,
      initialUsername: settings.cloudflareUsername ?? '',
      initialCreateAccount: initialCreateAccount,
      alreadySignedIn: settings.cloudflareConnected,
      signedInAs: settings.cloudflareUsername,
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
        try {
          await services.cloudflareSync.register(
            baseUrl: baseUrl,
            username: username,
            password: password,
          );
        } on CloudflareSyncException catch (e) {
          // If first-user setup already happened, fall through to login.
          final msg = e.message.toLowerCase();
          if (!msg.contains('already') && !msg.contains('exists')) {
            rethrow;
          }
        }
      }
      return services.cloudflareSync.login(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
    }(),
    errorPrefix: result.createAccount
        ? 'Could not create account'
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
    errorPrefix: 'Could not save session',
  );
  if (!context.mounted) return;

  showSnack(
    context,
    result.createAccount
        ? 'Account ready. You are signed in to Cloudflare sync.'
        : 'Signed in to Cloudflare sync.',
  );

  // After sign-in, offer to restore if a cloud backup exists and local archive is empty.
  final archive = ref.read(archiveProvider);
  if (archive.isEmpty && context.mounted) {
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
                  ? 'A synced backup was found (updated ${formatDayLong(when)} ${formatTime(when)}). Restore it to this device now?'
                  : 'A synced backup was found. Restore it to this device now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        );
        if (doRestore == true && context.mounted) {
          await restoreFromCloudflare(context, ref);
        }
      }
    } catch (_) {
      // ignore after successful sign-in
    }
  }
}

/// Signs out of Cloudflare sync on this device (keeps Worker URL for easy sign-in).
Future<void> signOutCloudflareSync(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final username = settings.cloudflareUsername ?? 'your account';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: Text(
        'Sign out of $username on this device. Your encrypted cloud backup stays on your Worker, and you can sign in again anytime to sync or restore.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await guard(
    context,
    ref.read(settingsProvider.notifier).disconnectCloudflareSync(),
    errorPrefix: 'Could not sign out',
  );
  if (context.mounted) showSnack(context, 'Signed out of Cloudflare sync.');
}

/// Legacy name kept for compatibility with older call sites.
Future<void> disconnectCloudflareSync(BuildContext context, WidgetRef ref) =>
    signOutCloudflareSync(context, ref);

Future<void> backupToCloudflare(BuildContext context, WidgetRef ref) async {
  final auth = await _requireCloudflareSession(context, ref, promptSignIn: true);
  if (auth == null || !context.mounted) return;

  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Backup passphrase',
    subtitle:
        'Choose a strong passphrase to encrypt your cloud backup. This is separate from your Cloudflare account password and is never sent to the server. You will need it to restore.',
    confirm: true,
  );
  if (passphrase == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);
  final data = await guard<Uint8List>(
    context,
    services.backup.createBackup(
      archive: ref.read(archiveProvider),
      passphrase: passphrase,
      mediaStore: services.mediaStore,
    ),
    errorPrefix: 'Could not create encrypted backup',
  );
  if (data == null || !context.mounted) return;

  bool uploaded = false;
  try {
    await services.cloudflareSync.uploadBackup(
      baseUrl: auth.workerUrl,
      token: auth.token,
      bytes: data,
    );
    uploaded = true;
  } on CloudflareSyncException catch (e) {
    if (!context.mounted) return;
    if (_isSessionExpired(e)) {
      await _handleAuthFailure(context, ref);
      return;
    }
    showSnack(context, 'Could not upload backup: ${e.message}');
    return;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not upload backup: $e');
    return;
  }

  if (!uploaded) return;
  await ref.read(settingsProvider.notifier).recordCloudflareSync(DateTime.now());
  if (context.mounted) {
    showSnack(
      context,
      'Encrypted backup synced to Cloudflare. Keep your backup passphrase safe.',
    );
  }
}

Future<void> restoreFromCloudflare(BuildContext context, WidgetRef ref) async {
  final auth = await _requireCloudflareSession(context, ref, promptSignIn: true);
  if (auth == null || !context.mounted) return;

  final services = ref.read(appServicesProvider);

  CloudflareBackupMeta? meta;
  try {
    meta = await services.cloudflareSync.getBackupMeta(
      baseUrl: auth.workerUrl,
      token: auth.token,
    );
  } on CloudflareSyncException catch (e) {
    if (!context.mounted) return;
    if (_isSessionExpired(e)) {
      await _handleAuthFailure(context, ref);
      return;
    }
    showSnack(context, 'Could not check cloud backup: ${e.message}');
    return;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not check cloud backup: $e');
    return;
  }

  if (!meta.exists) {
    if (context.mounted) {
      showSnack(context, 'No cloud backup found for this account.');
    }
    return;
  }
  if (!context.mounted) return;

  final when = meta.modifiedAt ?? meta.uploadedAt;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore from Cloudflare?'),
      content: Text(
        when != null
            ? 'This will replace the data on this device with the encrypted cloud backup from ${formatDayLong(when)} ${formatTime(when)}. Your backup passphrase is required.'
            : 'This will replace the data on this device with the encrypted cloud backup. Your backup passphrase is required.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final passphrase = await _askSyncPassphrase(
    context,
    title: 'Enter backup passphrase',
    subtitle:
        'Enter the passphrase used to encrypt this cloud backup. This is different from your Cloudflare account password.',
    confirm: false,
  );
  if (passphrase == null || !context.mounted) return;

  Uint8List? bytes;
  try {
    bytes = await services.cloudflareSync.downloadBackup(
      baseUrl: auth.workerUrl,
      token: auth.token,
    );
  } on CloudflareSyncException catch (e) {
    if (!context.mounted) return;
    if (_isSessionExpired(e)) {
      await _handleAuthFailure(context, ref);
      return;
    }
    showSnack(context, 'Could not download backup: ${e.message}');
    return;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not download backup: $e');
    return;
  }

  final contents = await guard(
    context,
    services.backup.readBackup(bytes: bytes, passphrase: passphrase),
    errorPrefix: 'Could not restore backup',
  );
  if (contents == null || !context.mounted) return;

  await guard(
    context,
    ref.read(archiveProvider.notifier).restoreArchive(
          contents.archive,
          mediaFiles: contents.mediaFiles,
        ),
    errorPrefix: 'Could not save restored data',
  );
  if (context.mounted) {
    showSnack(context, 'Backup restored from Cloudflare.');
  }
}

Future<_CloudflareAuthContext?> _requireCloudflareSession(
  BuildContext context,
  WidgetRef ref, {
  bool promptSignIn = false,
}) async {
  final settings = ref.read(settingsProvider);
  if (!settings.cloudflareConnected) {
    if (promptSignIn && context.mounted) {
      final signIn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in required'),
          content: const Text(
            'Sign in to your Cloudflare sync account to back up or restore encrypted data. Your journal stays on this device and works without signing in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      if (signIn == true && context.mounted) {
        await connectCloudflareSync(context, ref);
      }
    } else {
      showSnack(context, 'Sign in to Cloudflare sync in Settings first.');
    }
    return null;
  }
  final workerUrl = settings.cloudflareWorkerUrl?.trim() ?? '';
  final sessionJson =
      await ref.read(settingsProvider.notifier).cloudflareSessionJson();
  if (workerUrl.isEmpty || sessionJson == null) {
    if (context.mounted) {
      await ref.read(settingsProvider.notifier).disconnectCloudflareSync();
      if (context.mounted) await _handleAuthFailure(context, ref);
    }
    return null;
  }
  try {
    final map = jsonDecode(sessionJson) as Map<String, dynamic>;
    final token = map['token'] as String? ?? '';
    if (token.isEmpty) throw const FormatException('missing token');
    return _CloudflareAuthContext(workerUrl: workerUrl, token: token);
  } catch (_) {
    if (context.mounted) {
      await ref.read(settingsProvider.notifier).disconnectCloudflareSync();
      if (context.mounted) await _handleAuthFailure(context, ref);
    }
    return null;
  }
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
    this.initialCreateAccount = false,
    this.alreadySignedIn = false,
    this.signedInAs,
  });
  final String initialUrl;
  final String initialUsername;
  final bool initialCreateAccount;
  final bool alreadySignedIn;
  final String? signedInAs;

  @override
  State<_CloudflareConnectSheet> createState() => _CloudflareConnectSheetState();
}

class _CloudflareConnectSheetState extends State<_CloudflareConnectSheet> {
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl);
  late final TextEditingController _username =
      TextEditingController(text: widget.initialUsername);
  final TextEditingController _password = TextEditingController();
  late bool _createAccount = widget.initialCreateAccount;
  bool _obscure = true;
  bool _advanced = false;
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
      setState(() => _error = 'Enter a username (at least 2 characters).');
      return;
    }
    if (_createAccount && password.length < 10) {
      setState(
        () => _error = 'Use an account password with at least 10 characters.',
      );
      return;
    }
    if (!_createAccount && password.isEmpty) {
      setState(() => _error = 'Enter your password.');
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
    final scheme = context.scheme;
    final isDefault =
        _url.text.trim() == AppSettings.defaultCloudflareWorkerUrl ||
            _url.text.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          title:
              _createAccount ? 'Create sync account' : 'Sign in to Cloudflare sync',
          subtitle: _createAccount
              ? 'Set up your personal encrypted cloud backup'
              : 'Access your encrypted cloud backup and sync',
        ),
        if (widget.alreadySignedIn && widget.signedInAs != null) ...[
          QuietCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    'Currently signed in as ${widget.signedInAs}. Signing in will switch this device to the account you enter.',
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
        ],
        SegmentedPills<bool>(
          values: const [false, true],
          selected: _createAccount,
          labelFor: (v) => v ? 'Create account' : 'Sign in',
          onChanged: (v) => setState(() {
            _createAccount = v;
            _error = null;
          }),
        ),
        const SizedBox(height: Insets.md),
        QuietCard(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            children: [
              _InfoLine(
                icon: Icons.lock_outline_rounded,
                text:
                    'End-to-end encrypted: backups are encrypted on this device with your backup passphrase before upload.',
              ),
              const SizedBox(height: Insets.sm),
              _InfoLine(
                icon: Icons.cloud_outlined,
                text:
                    'Your Worker stores encrypted data only. Sign in is required to sync or restore from the cloud.',
              ),
              if (_createAccount) ...[
                const SizedBox(height: Insets.sm),
                _InfoLine(
                  icon: Icons.person_add_alt_1_rounded,
                  text:
                      'Create account is for the first-time setup of your personal Worker (single user).',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _username,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _password,
          decoration: InputDecoration(
            labelText: _createAccount ? 'Account password' : 'Password',
            prefixIcon: const Icon(Icons.key_outlined),
            helperText: _createAccount
                ? 'At least 10 characters. Backup encryption uses a separate passphrase.'
                : 'Your Cloudflare sync account password.',
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          obscureText: _obscure,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Insets.sm),
        InkWell(
          onTap: () => setState(() => _advanced = !_advanced),
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: Row(
              children: [
                Icon(
                  _advanced ? Icons.expand_less_rounded : Icons.tune_rounded,
                  size: 18,
                  color: palette.mutedText,
                ),
                const SizedBox(width: Insets.xs),
                Text(
                  _advanced ? 'Hide advanced' : 'Advanced (Worker URL)',
                  style: text.labelMedium?.copyWith(color: palette.mutedText),
                ),
                if (!_advanced && isDefault) ...[
                  const SizedBox(width: Insets.sm),
                  Text(
                    'Using default',
                    style: text.labelSmall?.copyWith(color: scheme.primary),
                  ),
                ],
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _url,
                  decoration: InputDecoration(
                    labelText: 'Worker URL',
                    hintText: AppSettings.defaultCloudflareWorkerUrl,
                    prefixIcon: const Icon(Icons.link_rounded),
                    helperText:
                        'Built-in by default. Change only if you use your own deployed Worker.',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Insets.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _url.text = AppSettings.defaultCloudflareWorkerUrl;
                    }),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Use default Worker'),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState:
              _advanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: Motion.fast,
        ),
        if (_error != null) ...[
          const SizedBox(height: Insets.sm),
          Text(
            _error!,
            style: text.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: Insets.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: Icon(
              _createAccount ? Icons.person_add_alt_1_rounded : Icons.login_rounded,
              size: 18,
            ),
            label: Text(_createAccount ? 'Create account & sign in' : 'Sign in'),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
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
          child: Text(
            text,
            style: context.text.bodySmall?.copyWith(color: palette.mutedText),
          ),
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
              decoration: InputDecoration(
                labelText: 'Backup passphrase',
                errorText: error,
              ),
              autofocus: true,
            ),
            if (confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: p2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm backup passphrase',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}
