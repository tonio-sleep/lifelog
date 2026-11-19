import 'dart:convert';

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
import '../settings/cloudflare_sync_actions.dart';

/// Required sign-in/sign-up screen for Cloudflare sync.
///
/// Shown when the user must be signed in to continue. This screen never deletes
/// or modifies local journal/archive data.
class CloudflareRequiredAuthScreen extends ConsumerStatefulWidget {
  const CloudflareRequiredAuthScreen({super.key, this.embedded = false});

  /// When true, renders as page content (for onboarding) without its own Scaffold.
  final bool embedded;

  @override
  ConsumerState<CloudflareRequiredAuthScreen> createState() =>
      _CloudflareRequiredAuthScreenState();
}

class _CloudflareRequiredAuthScreenState
    extends ConsumerState<CloudflareRequiredAuthScreen> {
  late final TextEditingController _url;
  late final TextEditingController _username;
  final TextEditingController _password = TextEditingController();
  bool _createAccount = false;
  bool _obscure = true;
  bool _advanced = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final initialUrl = (settings.cloudflareWorkerUrl ?? '').trim().isEmpty
        ? AppSettings.defaultCloudflareWorkerUrl
        : settings.cloudflareWorkerUrl!.trim();
    _url = TextEditingController(text: initialUrl);
    _username = TextEditingController(text: settings.cloudflareUsername ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    final username = _username.text.trim().toLowerCase();
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

    setState(() {
      _loading = true;
      _error = null;
    });

    final services = ref.read(appServicesProvider);
    final baseUrl = CloudflareSyncService.normalizeBaseUrl(url);
    try {
      CloudflareSession session;
      if (_createAccount) {
        try {
          await services.cloudflareSync.register(
            baseUrl: baseUrl,
            username: username,
            password: password,
          );
        } on CloudflareSyncException catch (e) {
          final msg = e.message.toLowerCase();
          if (!msg.contains('already') && !msg.contains('exists')) {
            rethrow;
          }
        }
      }
      session = await services.cloudflareSync.login(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );

      await ref.read(settingsProvider.notifier).saveCloudflareSession(
            workerUrl: baseUrl,
            username: session.username,
            sessionJson: jsonEncode(session.toJson()),
          );

      if (!mounted) return;
      showSnack(
        context,
        _createAccount
            ? 'Account ready. You are signed in.'
            : 'Signed in to Cloudflare sync.',
      );

      // If local archive is empty, offer to restore from cloud (explicit confirmation).
      final archive = ref.read(archiveProvider);
      if (archive.isEmpty && mounted) {
        try {
          final meta = await services.cloudflareSync.getBackupMeta(
            baseUrl: baseUrl,
            token: session.token,
          );
          if (meta.exists && mounted) {
            final when = meta.modifiedAt ?? meta.uploadedAt;
            final doRestore = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
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
            if (doRestore == true && mounted) {
              await restoreFromCloudflare(context, ref);
            }
          }
        } catch (_) {
          // ignore after successful sign-in
        }
      }
    } on CloudflareSyncException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final scheme = context.scheme;
    final isDefault =
        _url.text.trim() == AppSettings.defaultCloudflareWorkerUrl ||
            _url.text.trim().isEmpty;

    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Insets.xl,
            widget.embedded ? Insets.md : Insets.xl,
            Insets.xl,
            Insets.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.embedded) ...[
                const SizedBox(height: Insets.lg),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(Radii.xl),
                    ),
                    child: Icon(
                      Icons.cloud_sync_rounded,
                      size: 34,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: Insets.lg),
                Text(
                  'Sign in to continue',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  'A Cloudflare sync account is required to use this app. Sign in or create an account to continue. Your local data is safe on this device.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: palette.mutedText),
                ),
                const SizedBox(height: Insets.xl),
              ],
              QuietCard(
                padding: const EdgeInsets.all(Insets.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedPills<bool>(
                      values: const [false, true],
                      selected: _createAccount,
                      labelFor: (v) => v ? 'Create account' : 'Sign in',
                      onChanged: _loading
                          ? (_) {}
                          : (v) => setState(() {
                                _createAccount = v;
                                _error = null;
                              }),
                    ),
                    const SizedBox(height: Insets.md),
                    _InfoRow(
                      icon: Icons.lock_outline_rounded,
                      text:
                          'End-to-end encrypted: entries, notes, vocab, photos, videos, habits, places, and music are encrypted on this device before upload.',
                    ),
                    const SizedBox(height: Insets.sm),
                    _InfoRow(
                      icon: Icons.shield_outlined,
                      text:
                          'Your session stays on this device. Signing in never deletes your local data.',
                    ),
                    const SizedBox(height: Insets.md),
                    TextField(
                      controller: _username,
                      enabled: !_loading,
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
                      enabled: !_loading,
                      decoration: InputDecoration(
                        labelText:
                            _createAccount ? 'Account password' : 'Password',
                        prefixIcon: const Icon(Icons.key_outlined),
                        helperText: _createAccount
                            ? 'At least 10 characters. Backup encryption uses a separate passphrase.'
                            : 'Your Cloudflare sync account password.',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      onSubmitted: (_) => _loading ? null : _submit(),
                    ),
                    const SizedBox(height: Insets.sm),
                    InkWell(
                      onTap: _loading
                          ? null
                          : () => setState(() => _advanced = !_advanced),
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: Insets.xs),
                        child: Row(
                          children: [
                            Icon(
                              _advanced
                                  ? Icons.expand_less_rounded
                                  : Icons.tune_rounded,
                              size: 18,
                              color: palette.mutedText,
                            ),
                            const SizedBox(width: Insets.xs),
                            Text(
                              _advanced
                                  ? 'Hide advanced'
                                  : 'Advanced (Worker URL)',
                              style: text.labelMedium
                                  ?.copyWith(color: palette.mutedText),
                            ),
                            if (!_advanced && isDefault) ...[
                              const SizedBox(width: Insets.sm),
                              Text(
                                'Using default',
                                style: text.labelSmall
                                    ?.copyWith(color: scheme.primary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(
                          top: Insets.xs,
                          bottom: Insets.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _url,
                              enabled: !_loading,
                              decoration: InputDecoration(
                                labelText: 'Worker URL',
                                hintText:
                                    AppSettings.defaultCloudflareWorkerUrl,
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
                                onPressed: _loading
                                    ? null
                                    : () => setState(() {
                                          _url.text = AppSettings
                                              .defaultCloudflareWorkerUrl;
                                        }),
                                icon: const Icon(Icons.restart_alt_rounded,
                                    size: 16),
                                label: const Text('Use default Worker'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      crossFadeState: _advanced
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
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
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Icon(
                              _createAccount
                                  ? Icons.person_add_alt_1_rounded
                                  : Icons.login_rounded,
                              size: 18,
                            ),
                      label: Text(
                        _loading
                            ? 'Please wait...'
                            : (_createAccount
                                ? 'Create account & sign in'
                                : 'Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.md),
              Text(
                'Cloud sync is required. Your journal stays on this device, and backups can sync everything to your Cloudflare Worker when you choose.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: palette.dimText),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) return form;
    return Scaffold(
      body: SafeArea(child: form),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
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
