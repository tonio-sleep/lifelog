import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/surfaces.dart';
import '../../core/util/dates.dart';
import '../../integrations/cloudflare/sync_status.dart';
import 'cloudflare_sync_actions.dart';

enum _AccountAction { account, signOut }

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
    final palette = context.palette;
    final text = context.text;
    final phase = status.phase;

    final (label, tone) = switch (phase) {
      SyncPhase.signedOut => ('Not signed in', StatusTone.neutral),
      SyncPhase.active => ('Signed in', StatusTone.positive),
      SyncPhase.expiresSoon => (_expiresLabel(status), StatusTone.attention),
      SyncPhase.expired => ('Session expired', StatusTone.attention),
    };

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
                    StatusPill(label: label, tone: tone),
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
          'Includes entries, notes, vocab, photos/videos, habits, places, music, and timeline.',
          style: text.bodySmall?.copyWith(color: palette.mutedText),
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: () => backupToCloudflare(context, ref),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Sync now'),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: () => restoreFromCloudflare(context, ref),
                child: const Text('Restore'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
