import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/session_provider.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/settings.dart';
import '../music/lastfm_screen.dart';
import '../security/pin_dialogs.dart';
import 'backup_actions.dart';
import 'google_drive_actions.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final archive = ref.watch(archiveProvider);
    final services = ref.watch(appServicesProvider);
    final palette = context.palette;
    final text = context.text;
    final mediaBytes = archive.media.fold<int>(0, (sum, item) => sum + item.bytes);
    final weakKey = services.keySource.contains('Local key');

    return ScreenFrame(
      title: 'Settings',
      maxWidth: 680,
      actions: [
        if (settings.lockEnabled)
          HeaderButton(
            icon: Icons.lock_outline_rounded,
            tooltip: 'Lock now',
            onPressed: () => ref.read(sessionLockProvider.notifier).lock(),
          ),
      ],
      children: [
        ListGroup(
          title: 'Appearance',
          children: [
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: Insets.md),
                  SegmentedPills<AppThemeMode>(
                    values: AppThemeMode.values,
                    selected: settings.themeMode,
                    labelFor: (mode) => mode.label,
                    onChanged: (value) => guard(
                      context,
                      ref.read(settingsProvider.notifier).setThemeMode(value),
                      errorPrefix: 'Could not change the theme',
                    ),
                  ),
                ],
              ),
            ),
            ListRow(
              icon: Icons.calendar_view_week_rounded,
              title: 'Week starts on Monday',
              trailing: Switch(
                value: settings.weekStartsMonday,
                onChanged: (value) => guard(
                  context,
                  ref.read(settingsProvider.notifier).setWeekStartsMonday(value),
                  errorPrefix: 'Could not save the setting',
                ),
              ),
              onTap: () => guard(
                context,
                ref.read(settingsProvider.notifier).setWeekStartsMonday(!settings.weekStartsMonday),
                errorPrefix: 'Could not save the setting',
              ),
            ),
          ],
        ),
        ListGroup(
          title: 'Privacy',
          children: [
            ListRow(
              icon: Icons.lock_outline_rounded,
              title: 'PIN lock',
              subtitle: settings.lockEnabled
                  ? (settings.autoLockMinutes == 0
                        ? 'Locks when you choose'
                        : 'Locks after ${settings.autoLockMinutes} min away')
                  : 'Off',
              trailing: Switch(
                value: settings.lockEnabled,
                onChanged: (value) => _toggleLock(context, ref, value),
              ),
              onTap: () => _toggleLock(context, ref, !settings.lockEnabled),
            ),
            if (settings.lockEnabled) ...[
              ListRow(
                icon: Icons.timer_outlined,
                title: 'Auto-lock',
                subtitle: settings.autoLockMinutes == 0
                    ? 'Manual only'
                    : '${settings.autoLockMinutes} ${plural(settings.autoLockMinutes, 'minute')}',
                chevron: true,
                onTap: () => _pickAutoLock(context, ref, settings.autoLockMinutes),
              ),
              ListRow(
                icon: Icons.password_rounded,
                title: 'Change PIN',
                chevron: true,
                onTap: () => _changePin(context, ref),
              ),
            ],
            ListRow(
              icon: Icons.shield_outlined,
              title: 'How your data is protected',
              subtitle: weakKey ? 'Key stored in a local file' : services.keySource,
              iconColor: weakKey ? palette.photo : null,
              chevron: true,
              onTap: () => _showPrivacyDetails(
                context,
                services.keySource,
                services.rootDirectory.path,
                '${archive.entries.length} entries, ${archive.media.length} media, ${_formatBytes(mediaBytes)}',
              ),
            ),
          ],
        ),
        ListGroup(
          title: 'Music',
          children: [
            ListRow(
              icon: Icons.graphic_eq_rounded,
              iconColor: palette.music,
              title: 'Last.fm',
              subtitle: settings.lastfmConnected
                  ? 'Connected as ${settings.lastfmUsername}'
                  : 'Not connected',
              chevron: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LastfmScreen()),
              ),
            ),
            ListRow(
              icon: Icons.image_outlined,
              iconColor: palette.music,
              title: 'Show album artwork',
              subtitle: 'Loaded from Last.fm. Off means no image requests.',
              trailing: Switch(
                value: settings.showArtwork,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setShowArtwork(value),
              ),
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .setShowArtwork(!settings.showArtwork),
            ),
          ],
        ),
        ListGroup(
          title: 'Permissions',
          footer: 'Location is used only when you choose to save a place. Health access is read-only for step counts. '
              'Screen Time data is not available on iPhone without special Apple entitlements.',
          children: [
            ListRow(
              icon: Icons.location_on_outlined,
              iconColor: palette.place,
              title: 'Location access',
              subtitle: 'Allow location when saving places or visits',
              chevron: true,
              onTap: () => _requestLocationPermission(context),
            ),
            if (services.healthSteps.isSupported)
              ListRow(
                icon: Icons.favorite_border_rounded,
                iconColor: palette.tracker,
                title: 'Health access (steps)',
                subtitle: 'Allow read-only access to daily step counts',
                chevron: true,
                onTap: () async {
                  final ok = await guard<bool>(
                    context,
                    services.healthSteps.requestPermission(),
                    errorPrefix: 'Could not connect to Health',
                  );
                  if (ok == true && context.mounted) {
                    showSnack(context, 'Health access granted.');
                  } else if (ok == false && context.mounted) {
                    showSnack(context, 'Health access was not granted.');
                  }
                },
              ),
            ListRow(
              icon: Icons.hourglass_disabled_rounded,
              iconColor: palette.mutedText,
              title: 'Screen Time',
              subtitle: 'Not available on iPhone without special Apple approval',
            ),
          ],
        ),
        if (services.healthSteps.isSupported)
          ListGroup(
            title: 'Steps',
            footer: 'Import your daily step count into your check-in. Read-only; nothing is written to Health.',
            children: [
              ListRow(
                icon: Icons.directions_walk_rounded,
                iconColor: palette.place,
                title: 'Import today\'s steps',
                subtitle: 'Save today\'s steps to your daily check-in',
                chevron: true,
                onTap: () => _importTodaySteps(context, ref),
              ),
            ],
          ),
        ListGroup(
          title: 'Google account',
          footer: settings.googleDriveConnected
              ? 'Signed in as ${settings.googleAccountEmail}. ${settings.googleLastSyncAt == null ? 'Not synced yet.' : 'Last sync ${formatDayLong(settings.googleLastSyncAt!)}, ${formatTime(settings.googleLastSyncAt!)}.'} Sync stores an encrypted backup (records and text; media files not included).'
              : 'Connect your Google account to back up and restore your encrypted data with Google Drive. Your data stays on this device unless you sync.',
          children: [
            if (!settings.googleDriveConnected)
              ListRow(
                icon: Icons.account_circle_outlined,
                iconColor: context.scheme.primary,
                title: 'Connect Google account',
                subtitle: (settings.googleClientId ?? '').trim().isEmpty
                    ? 'Sign in to sync and restore your data'
                    : 'Continue with your Google account',
                chevron: true,
                onTap: () => connectGoogleDrive(context, ref),
              ),
            if (settings.googleDriveConnected) ...[
              ListRow(
                icon: Icons.cloud_done_outlined,
                iconColor: palette.tracker,
                title: settings.googleAccountEmail ?? 'Google account',
                subtitle: 'Connected for Drive sync',
              ),
              ListRow(
                icon: Icons.cloud_upload_outlined,
                title: 'Back up now',
                subtitle: 'Upload an encrypted backup to Google Drive',
                chevron: true,
                onTap: () => syncToGoogleDrive(context, ref),
              ),
              ListRow(
                icon: Icons.cloud_download_outlined,
                title: 'Restore from cloud',
                subtitle: 'Replace this device’s data with your cloud backup',
                chevron: true,
                onTap: () => restoreFromGoogleDrive(context, ref),
              ),
              ListRow(
                icon: Icons.logout_rounded,
                title: 'Disconnect account',
                destructive: true,
                onTap: () => disconnectGoogleDrive(context, ref),
              ),
            ],
          ],
        ),
        const SizedBox(height: Insets.lg),
        ListGroup(
          title: 'Backup & sync',
          footer: settings.lastBackupAt == null
              ? 'No backup has been created from this install yet.'
              : 'Last backup ${formatDayLong(settings.lastBackupAt!)}, ${formatTime(settings.lastBackupAt!)}.',
          children: [
            ListRow(
              icon: Icons.folder_shared_outlined,
              title: 'Linked folder',
              subtitle: settings.backupFolderPath == null
                  ? 'Not linked (e.g. Google Drive folder)'
                  : settings.backupFolderPath!,
              chevron: true,
              onTap: () => linkBackupFolder(context, ref),
            ),
            if (settings.backupFolderPath != null)
              ListRow(
                icon: Icons.cloud_upload_outlined,
                title: 'Save backup to linked folder',
                subtitle: 'Creates an encrypted backup in the linked folder',
                chevron: true,
                onTap: () => saveBackupToLinkedFolder(context, ref),
              ),
            if (settings.backupFolderPath != null)
              ListRow(
                icon: Icons.link_off_rounded,
                title: 'Unlink folder',
                destructive: true,
                onTap: () async {
                  await guard(
                    context,
                    ref.read(settingsProvider.notifier).clearBackupFolderPath(),
                    errorPrefix: 'Could not unlink folder',
                  );
                  if (context.mounted) showSnack(context, 'Backup folder unlinked.');
                },
              ),
            ListRow(
              icon: Icons.download_outlined,
              title: 'Create backup (choose location)',
              chevron: true,
              onTap: () => exportBackup(context, ref),
            ),
            ListRow(
              icon: Icons.restore_rounded,
              title: 'Restore from backup',
              chevron: true,
              onTap: () => restoreBackup(context, ref),
            ),
          ],
        ),
        ListGroup(
          title: 'Data',
          children: [
            ListRow(
              icon: Icons.waving_hand_outlined,
              title: 'Show the welcome tour again',
              chevron: true,
              onTap: () => guard(
                context,
                ref.read(settingsProvider.notifier).resetOnboarding(),
                errorPrefix: 'Could not reset the tour',
              ),
            ),
            ListRow(
              icon: Icons.delete_forever_outlined,
              title: 'Delete everything',
              subtitle: 'Removes the archive and the media vault',
              destructive: true,
              onTap: () => _wipe(context, ref),
            ),
          ],
        ),
        ListGroup(
          title: 'About',
          footer: 'Lifelog 1.0.0. No account required and no analytics. Your data is stored locally and encrypted on this device.',
          children: [
            ListRow(
              icon: Icons.info_outline_rounded,
              title: 'Known limitations',
              chevron: true,
              onTap: () => showLifelogSheet<void>(
                context,
                builder: (_) => const _LimitationsSheet(),
              ),
            ),
            ListRow(
              icon: Icons.article_outlined,
              title: 'Open-source licences',
              chevron: true,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Lifelog',
                applicationVersion: '1.0.0',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAutoLock(BuildContext context, WidgetRef ref, int current) async {
    const options = <int>[0, 1, 5, 10, 15, 30, 60];
    final chosen = await showLifelogSheet<int>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(title: 'Auto-lock'),
          for (final minutes in options)
            ListRow(
              title: minutes == 0
                  ? 'Manual only'
                  : minutes == 60
                  ? '1 hour'
                  : '$minutes ${plural(minutes, 'minute')}',
              trailing: minutes == current
                  ? Icon(Icons.check_rounded, color: sheetContext.scheme.primary)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(minutes),
            ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).setAutoLockMinutes(chosen),
      errorPrefix: 'Could not save the setting',
    );
  }

  Future<void> _toggleLock(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    if (!enable) {
      final ok = await confirmCurrentPin(context, ref);
      if (!ok || !context.mounted) return;
      await guard(
        context,
        ref.read(settingsProvider.notifier).disablePin(),
        errorPrefix: 'Could not disable the PIN',
      );
      return;
    }
    final pin = await askCreatePin(context);
    if (pin == null) return;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).setPin(pin),
      errorPrefix: 'Could not set the PIN',
    );
    if (context.mounted) {
      showSnack(
        context,
        'PIN set. It will be required next time the app opens.',
      );
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final ok = await confirmCurrentPin(context, ref);
    if (!ok || !context.mounted) return;
    final pin = await askCreatePin(context, title: 'Set a new PIN');
    if (pin == null) return;
    if (!context.mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).setPin(pin),
      errorPrefix: 'Could not change the PIN',
    );
    if (context.mounted) showSnack(context, 'PIN changed.');
  }

  Future<void> _requestLocationPermission(BuildContext context) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && context.mounted) {
        showSnack(context, 'Location services are turned off. Enable them in Settings to save places with your location.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!context.mounted) return;
      if (permission == LocationPermission.deniedForever) {
        showSnack(context, 'Location permission is denied. You can enable it in your device Settings.');
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        showSnack(context, 'Location access is enabled.');
      } else {
        showSnack(context, 'Location access was not granted.');
      }
    } catch (error) {
      if (context.mounted) showSnack(context, 'Could not request location access: $error');
    }
  }

  Future<void> _importTodaySteps(BuildContext context, WidgetRef ref) async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      showSnack(context, 'Steps import is available on supported devices with Health access.');
      return;
    }
    final granted = await guard<bool>(
      context,
      services.healthSteps.requestPermission(),
      errorPrefix: 'Could not access Health data',
    );
    if (granted != true || !context.mounted) return;
    final today = DateTime.now();
    final steps = await guard<int?>(
      context,
      services.healthSteps.getStepsForDay(today),
      errorPrefix: 'Could not read steps',
    );
    if (!context.mounted || steps == null) {
      if (context.mounted) showSnack(context, 'No step data available for today.');
      return;
    }
    final archive = ref.read(archiveProvider);
    final existing = archive.dailyEntryFor(today);
    final base = existing ??
        JournalEntry(
          id: 'day-${dayKey(today)}',
          createdAt: momentForDay(today),
          updatedAt: DateTime.now(),
          title: '',
          body: '',
          draft: true,
        );
    await guard(
      context,
      ref.read(archiveProvider.notifier).saveEntry(
            base.copyWith(steps: steps, updatedAt: DateTime.now()),
          ),
      errorPrefix: 'Could not save steps',
    );
    if (context.mounted) {
      showSnack(context, 'Saved $steps steps to today\'s check-in.');
    }
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete the entire archive?',
      message:
          'This removes every journal entry, tracker, visit, event and music '
          'record, and deletes the encrypted media vault. It cannot be undone. '
          'Create a backup first if you want to keep a copy.',
      confirmLabel: 'Delete everything',
    );
    if (!ok) return;
    if (!context.mounted) return;
    final done = await guard(
      context,
      ref.read(archiveProvider.notifier).clearArchiveData(),
      errorPrefix: 'Could not delete the archive',
    );
    if (done == null) return;
    if (context.mounted) {
      showSnack(context, 'Archive and media vault deleted.');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _showPrivacyDetails(
    BuildContext context,
    String keySource,
    String folder,
    String size,
  ) {
    final palette = context.palette;
    return showLifelogSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(title: 'How your data is protected'),
          const _PrivacyPoint(
            icon: Icons.enhanced_encryption_outlined,
            title: 'Encrypted archive',
            body: 'Entries, habits, places, visits, music and events are '
                'encrypted as one document with AES-256-GCM before they are '
                'written to disk.',
          ),
          _PrivacyPoint(
            icon: Icons.key_outlined,
            title: 'Root key',
            body: 'The archive key is loaded from $keySource. A local key file '
                'is a weaker fallback: it stops casual access, not a '
                'determined attacker with file access.',
          ),
          const _PrivacyPoint(
            icon: Icons.image_outlined,
            title: 'Media',
            body: 'Originals and thumbnails are encrypted individually in a '
                'media vault.',
          ),
          const _PrivacyPoint(
            icon: Icons.backup_outlined,
            title: 'Backups',
            body: 'Backups use a separate passphrase key derived with '
                'Argon2id. Media is excluded in this build.',
          ),
          const _PrivacyPoint(
            icon: Icons.cloud_outlined,
            title: 'Network use',
            body: 'No analytics or crash reporting. Optional connections you control: Google Drive backup/sync (encrypted), '
                'read-only Last.fm import, album artwork from Last.fm when enabled, and read-only Health/Health Connect step import on supported devices.',
          ),
          const _PrivacyPoint(
            icon: Icons.folder_outlined,
            title: 'Files app (iPhone/iPad)',
            body: 'Encrypted backups saved to the app\'s Backups folder are visible in the Files app. '
                'Your main archive stays encrypted in app storage.',
          ),
          const _PrivacyPoint(
            icon: Icons.gps_off_outlined,
            title: 'Location & permissions',
            body: 'Location is only read when you choose to use it (for example, saving a place). '
                'Screen Time/usage data is not accessible on iPhone without special Apple entitlements.',
          ),
          const _PrivacyPoint(
            icon: Icons.warning_amber_rounded,
            title: 'Honest limits',
            body: 'App-level encryption does not protect an unlocked session, '
                'a compromised operating system, or a forgotten backup '
                'passphrase.',
          ),
          const Divider(),
          const SizedBox(height: Insets.sm),
          Text('On this device', style: sheetContext.text.labelMedium?.copyWith(color: palette.mutedText)),
          const SizedBox(height: Insets.xs),
          SelectableText(folder, style: sheetContext.text.bodySmall),
          const SizedBox(height: 2),
          Text(size, style: sheetContext.text.bodySmall?.copyWith(color: palette.mutedText)),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 34, iconSize: 17),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: context.text.bodySmall?.copyWith(color: context.palette.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LimitationsSheet extends StatelessWidget {
  const _LimitationsSheet();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(title: 'Known limitations'),
        for (final item in const <String>[
          'Data is saved locally on this device. Google Drive sync is optional and stores an encrypted backup (records and text; media files are not included).',
          'No automatic multi-device merge. Restoring from a backup replaces local data on that device.',
          'Screen Time data cannot be read by this app on iPhone without special Apple entitlements; this is not currently available.',
          'Automatic steps require Health access on supported devices. Other step sources are not imported automatically.',
          'Backups exclude media file bytes. Keep your media vault separately if needed.',
          'No background location tracking or automatic visit detection. Location is only used when you choose to save a place or visit.',
          'Last.fm import is optional and read-only; syncing may require an API key depending on Last.fm.',
          'The PIN is an app-level privacy screen, not a key-derivation step. A forgotten backup passphrase cannot be recovered.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 5, color: palette.mutedText),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    item,
                    style: context.text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
