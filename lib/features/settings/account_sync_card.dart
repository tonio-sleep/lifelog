import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/surfaces.dart';
import '../../core/util/dates.dart';
import '../../integrations/cloudflare/backup_upload_progress.dart';
import '../../integrations/cloudflare/cloud_remote_state.dart';
import '../../integrations/cloudflare/sync_status.dart';
import 'cloudflare_sync_actions.dart';

enum _AccountAction { account, forgetPassphrase, signOut }

/// The optional cloud account, in one place.
///
/// States, in order of what the person needs next:
///  - signed out: explains the offer and that local use is unaffected
///  - session expired: says so plainly, offers one button, and repeats that
///    nothing on this device changed
///  - signed in: last backup time, one primary action, restore beside it, and
///    account actions tucked into a menu
class AccountSyncCard extends ConsumerWidget {
  const AccountSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = watchSyncStatus(ref);
    final upload = ref.watch(backupUploadProvider);
    final palette = context.palette;
    final text = context.text;
    final phase = status.phase;

    var (label, tone) = switch (phase) {
      SyncPhase.signedOut => ('Not signed in', StatusTone.neutral),
      SyncPhase.active => ('Signed in', StatusTone.positive),
      SyncPhase.expiresSoon => (_expiresLabel(status), StatusTone.attention),
      SyncPhase.expired => ('Session expired', StatusTone.attention),
    };
    if (upload.active) {
      label = 'Uploading…';
      tone = StatusTone.accent;
    }

    final title = status.signedIn
        ? (status.username ?? 'Cloud sync')
        : 'Cloud sync';
    final subtitle = status.signedIn
        ? (status.host ?? 'Cloudflare Worker')
        : 'Sign in to back up and sync your data.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Account and backup'),
        QuietCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.lg,
                  Insets.sm,
                  Insets.lg,
                ),
                child: Row(
                  children: [
                    _StatusGlyph(phase: phase),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: palette.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    StatusPill(
                      label: label,
                      tone: tone,
                      pulse: upload.active,
                    ),
                    if (status.signedIn)
                      PopupMenuButton<_AccountAction>(
                        tooltip: 'Account options',
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: palette.mutedText,
                        ),
                        onSelected: (action) => switch (action) {
                          _AccountAction.account => connectCloudflareSync(
                            context,
                            ref,
                          ),
                          _AccountAction.forgetPassphrase =>
                            forgetCloudflareBackupPassphrase(context, ref),
                          _AccountAction.signOut => signOutCloudflareSync(
                            context,
                            ref,
                          ),
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _AccountAction.account,
                            child: Text('Account details'),
                          ),
                          const PopupMenuItem(
                            value: _AccountAction.forgetPassphrase,
                            child: Text('Forget saved passphrase'),
                          ),
                          PopupMenuItem(
                            value: _AccountAction.signOut,
                            child: Text(
                              'Sign out',
                              style: TextStyle(color: context.scheme.error),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: Insets.sm),
                  ],
                ),
              ),
              Divider(color: palette.border),
              Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: switch (phase) {
                  SyncPhase.signedOut => _SignedOutBody(),
                  SyncPhase.expired => _ExpiredBody(),
                  SyncPhase.active ||
                  SyncPhase.expiresSoon => _SignedInBody(status: status),
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.xs, Insets.sm, Insets.xs, 0),
          child: Text(
            'Backups are encrypted on this device with your backup passphrase '
            'before upload. Signing out never removes anything from this device.',
            style: text.bodySmall?.copyWith(color: palette.dimText),
          ),
        ),
      ],
    );
  }

  String _expiresLabel(SyncStatus status) {
    final days = status.daysLeft;
    if (days == null || days <= 1) return 'Expires today';
    return 'Expires in $days days';
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.phase});
  final SyncPhase phase;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final icon = switch (phase) {
      SyncPhase.signedOut => Icons.cloud_outlined,
      SyncPhase.active => Icons.cloud_done_outlined,
      SyncPhase.expiresSoon || SyncPhase.expired => Icons.cloud_off_outlined,
    };
    final color = switch (phase) {
      SyncPhase.signedOut => palette.mutedText,
      SyncPhase.active => palette.success,
      SyncPhase.expiresSoon || SyncPhase.expired => palette.warning,
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: palette.subtle,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

class _SignedOutBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Back up and sync all your data — journal entries, notes, vocab, photos, videos, habits, places, music, and timeline — encrypted on your device before upload. Restore everything on a new device anytime.',
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.mutedText,
          ),
        ),
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: () => connectCloudflareSync(context, ref),
          child: const Text('Sign in'),
        ),
        const SizedBox(height: Insets.xs),
        TextButton(
          onPressed: () =>
              connectCloudflareSync(context, ref, initialCreateAccount: true),
          child: const Text('Create an account'),
        ),
      ],
    );
  }
}

class _ExpiredBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your sync session has ended. Everything on this device is exactly '
          'as you left it; only backup and restore are paused.',
          style: context.text.bodyMedium?.copyWith(
            color: context.palette.mutedText,
          ),
        ),
        const SizedBox(height: Insets.lg),
        FilledButton(
          onPressed: () => connectCloudflareSync(context, ref),
          child: const Text('Sign in again'),
        ),
      ],
    );
  }
}

class _SignedInBody extends ConsumerWidget {
  const _SignedInBody({required this.status});
  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    final last = status.lastSyncAt;
    final lastLabel = last == null
        ? 'No cloud backup yet'
        : '${relativeDayLabel(dayStart(last))}, ${formatTime(last)}';
    final upload = ref.watch(backupUploadProvider);
    final passphraseRemembered =
        ref.watch(settingsProvider).cloudflarePassphraseCipher?.isNotEmpty ??
            false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last synced backup',
                    style: text.labelMedium?.copyWith(color: palette.mutedText),
                  ),
                  const SizedBox(height: 2),
                  Text(lastLabel, style: text.titleSmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Text(
          'Push uploads this device as one encrypted backup. Pull replaces this device with the cloud backup.',
          style: text.bodySmall?.copyWith(color: palette.mutedText),
        ),
        const SizedBox(height: Insets.sm),
        _RemoteStatusLine(),
        if (upload.stage != BackupUploadStage.idle) ...[
          const SizedBox(height: Insets.md),
          _UploadProgressBlock(progress: upload),
        ],
        if (passphraseRemembered) ...[
          const SizedBox(height: Insets.xs),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 14, color: context.scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Backup passphrase remembered on this device.',
                  style: text.labelSmall?.copyWith(color: palette.mutedText),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: upload.active
                    ? null
                    : () => backupToCloudflare(context, ref),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Push'),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: upload.active
                    ? null
                    : () => pullFromCloudflare(context, ref),
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Pull'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RemoteStatusLine extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(cloudRemoteMetaProvider);
    final palette = context.palette;
    final text = context.text;
    final value = remote.value;
    final label = switch (remote) {
      AsyncLoading() => 'Checking cloud...',
      AsyncError() => 'Could not check cloud status.',
      _ when value == null || !value.exists => 'No cloud backup yet',
      _ => 'Cloud backup: ${_formatBytes(value.size ?? 0)}'
          '${value.modifiedAt != null || value.uploadedAt != null
              ? ' · ${formatDayLong(value.modifiedAt ?? value.uploadedAt!)}'
              : ''}',
    };
    return Row(
      children: [
        Icon(Icons.cloud_outlined, size: 14, color: palette.dimText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: palette.mutedText),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Check cloud status',
          icon: const Icon(Icons.refresh_rounded, size: 16),
          onPressed: () => ref.invalidate(cloudRemoteMetaProvider),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _UploadProgressBlock extends StatelessWidget {
  const _UploadProgressBlock({required this.progress});

  final BackupUploadProgress progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final uploading = progress.stage == BackupUploadStage.uploading;
    final fraction = uploading
        ? progress.byteFraction
        : (progress.active ? progress.itemFraction : 1.0);
    final detail = uploading
        ? '${_formatBytes(progress.bytesSent)} of '
            '${_formatBytes(progress.bytesTotal)}'
        : progress.total > 0
            ? '${progress.current} of ${progress.total} items'
            : '';

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: palette.subtle,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                progress.stage == BackupUploadStage.failed
                    ? Icons.error_outline_rounded
                    : Icons.cloud_upload_outlined,
                size: 16,
                color: progress.stage == BackupUploadStage.failed
                    ? context.scheme.error
                    : context.scheme.primary,
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  progress.label.isEmpty
                      ? progress.stage.label
                      : progress.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: text.labelSmall?.copyWith(color: palette.mutedText),
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          LinearProgressIndicator(
            value: progress.stage == BackupUploadStage.failed ? null : fraction,
            minHeight: 4,
            backgroundColor: palette.border,
            color: progress.stage == BackupUploadStage.failed
                ? context.scheme.error
                : context.scheme.primary,
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'Upload details',
                style: text.labelSmall?.copyWith(color: palette.mutedText),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                _DetailRow(
                  label: 'Stage',
                  value: progress.stage.label,
                ),
                _DetailRow(
                  label: 'Items packed',
                  value: '${progress.current} / ${progress.total}',
                ),
                _DetailRow(
                  label: 'Bytes sent',
                  value: '${_formatBytes(progress.bytesSent)} / '
                      '${_formatBytes(progress.bytesTotal)}',
                ),
                if (progress.startedAt != null)
                  _DetailRow(
                    label: 'Started',
                    value: formatTime(progress.startedAt!),
                  ),
                if (progress.error != null)
                  _DetailRow(label: 'Error', value: progress.error!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.palette.dimText,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
