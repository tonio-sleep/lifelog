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
import '../../integrations/health/health_steps_service.dart';
import '../../integrations/location/location_tracking_controller.dart';
import '../../domain/models/settings.dart';
import '../music/lastfm_screen.dart';
import '../security/pin_dialogs.dart';
import 'account_sync_card.dart';
import 'backup_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  HealthAccessState _healthStatus = HealthAccessState.unknown;

  @override
  void initState() {
    super.initState();
    _refreshHealthStatus();
  }

  /// Read permission is not reliably observable on iOS. A confirmed readable
  /// probe is the only positive signal; a successful request stays "requested".
  Future<void> _refreshHealthStatus() async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      if (!mounted) return;
      setState(() => _healthStatus = HealthAccessState.unavailable);
      return;
    }
    final permission = await services.healthSteps.hasPermission();
    var status = HealthAccessState.unknown;
    if (permission == true) {
      status = HealthAccessState.readable;
    } else {
      final summary = await services.healthSteps.getDailySummary(DateTime.now());
      if (summary.hasData) status = HealthAccessState.readable;
    }
    if (!mounted) return;
    setState(() => _healthStatus = status);
  }

  String _healthStatusSubtitle() {
    return switch (_healthStatus) {
      HealthAccessState.readable =>
        'Health data is readable on this device. Tap for manual instructions.',
      HealthAccessState.requested =>
        'Access requested, not confirmed readable. Tap for manual instructions.',
      HealthAccessState.unavailable =>
        'Health store unavailable on this device.',
      HealthAccessState.unknown =>
        'Status unknown. Tap to read the manual instructions.',
    };
  }

  @override
  Widget build(BuildContext context) {
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
        const Padding(
          padding: EdgeInsets.only(top: Insets.lg),
          child: AccountSyncCard(),
        ),
        ListGroup(
          title: 'Reminders',
          footer:
              'In-app reminders to nudge you (for example: journal, check-in, habits, or vocab review). Enable notifications in a future update for system alerts.',
          children: [
            for (final reminder in settings.reminders)
              ListRow(
                icon: reminder.enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                iconColor:
                    reminder.enabled ? palette.tracker : palette.dimText,
                title: reminder.title,
                subtitle:
                    '${reminder.timeLabel} · ${reminder.repeat.label}${reminder.note.trim().isEmpty ? '' : ' · ${reminder.note.trim()}'}',
                trailing: Switch(
                  value: reminder.enabled,
                  onChanged: (value) => guard(
                    context,
                    ref
                        .read(settingsProvider.notifier)
                        .toggleReminder(reminder.id, value),
                    errorPrefix: 'Could not update reminder',
                  ),
                ),
                chevron: true,
                onTap: () => _editReminder(context, ref, reminder),
              ),
            ListRow(
              icon: Icons.add_alarm_rounded,
              iconColor: context.scheme.primary,
              title: 'Add reminder',
              subtitle: settings.reminders.isEmpty
                  ? 'Create a reminder for something you want to do'
                  : 'Add another reminder',
              chevron: true,
              onTap: () => _editReminder(context, ref, null),
            ),
          ],
        ),
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
          footer:
              'While Using access powers the day map and manual location fixes. For automatic background visits, turn on Background visits in Places and set Location Access to Always in iOS Settings. '
              'iOS cannot upgrade to Always from inside the app, so this row opens Settings when needed. '
              'Health access is read-only and lets Lifelog sync sleep and steps automatically. '
              'Screen Time/app usage is not available to regular iPhone apps without special Apple Family Controls entitlement and approval.',
          children: [
            ListRow(
              icon: Icons.location_on_outlined,
              iconColor: palette.place,
              title: 'Location access',
              subtitle:
                  'While Using for day tracking · Always for background visits',
              chevron: true,
              onTap: () => _requestLocationPermission(context, ref),
            ),
            if (services.healthSteps.isSupported)
              ListRow(
                icon: Icons.favorite_border_rounded,
                iconColor: palette.tracker,
                title: 'Health access',
                subtitle: _healthStatusSubtitle(),
                chevron: true,
                onTap: () => _requestHealthAccess(context, ref),
              ),
            ListRow(
              icon: Icons.hourglass_top_rounded,
              iconColor: palette.music,
              title: 'Screen Time (advanced)',
              subtitle: 'iPhone Screen Time/app usage access requires Apple Family Controls entitlement and approval',
              chevron: true,
              onTap: () => _showScreenTimeInfo(context),
            ),
          ],
        ),
        if (services.healthSteps.isSupported)
          ListGroup(
            title: 'Health sync',
            footer:
                'Sleep and steps are read from Health and saved as day health metrics (separate from check-ins). Read-only; nothing is written to Health. Requesting access is not the same as confirmed read access: on iPhone, Health does not reveal read permission status.',
            children: [
              ListRow(
                icon: Icons.sync_rounded,
                iconColor: palette.place,
                title: 'Sync today from Health',
                subtitle: 'Update today\'s sleep and steps from Health',
                chevron: true,
                onTap: () => _syncTodayFromHealth(context, ref),
              ),
            ],
          ),
        ListGroup(
          title: 'Local backups',
          footer: settings.lastBackupAt == null
              ? 'Save an encrypted backup file to this device or a folder you choose (e.g. iCloud/Drive folder). Includes all entries, media, habits, places, and music.'
              : 'Last local backup ${formatDayLong(settings.lastBackupAt!)}, ${formatTime(settings.lastBackupAt!)}. Includes all entries, media, habits, places, and music.',
          children: [
            ListRow(
              icon: Icons.folder_shared_outlined,
              title: 'Linked folder',
              subtitle: settings.backupFolderPath == null
                  ? 'Not linked (e.g. a synced/cloud folder)'
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
          footer: 'Lifelog 1.0.0. No account required and no analytics. Your data is stored locally and encrypted on this device. Cloudflare is optional: an encrypted backup copy via your own Worker.',
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

  Future<void> _requestLocationPermission(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && context.mounted) {
        showSnack(context, 'Location services are turned off. Enable Location Services in device Settings.');
      }

      // iOS only ever grants While Using from this prompt. Upgrading to Always
      // must be done by the person in Settings, so don't ask twice here.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!context.mounted) return;

      if (permission == LocationPermission.always) {
        showSnack(context, 'Location access is set to Always.');
        return;
      }
      if (permission == LocationPermission.whileInUse) {
        showSnack(context, 'While Using is on. For automatic background visits, turn on Background visits in Places, then choose Always in iOS Settings.');
        await ref.read(backgroundLocationChannelProvider).openSettings();
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        showSnack(context, 'Location permission is off. Open iOS Settings and set Lifelog to Always.');
        await ref.read(backgroundLocationChannelProvider).openSettings();
        return;
      }
      showSnack(context, 'Location access was not granted. You can allow it in iOS Settings.');
    } catch (error) {
      if (context.mounted) {
        showSnack(context, 'Could not request location access: $error');
      }
    }
  }

  Future<void> _requestHealthAccess(BuildContext context, WidgetRef ref) async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      showSnack(context, 'Health access is available on supported devices (iPhone/Apple Health or Android/Health Connect).');
      return;
    }
    final access = await guard<HealthAccessState>(
      context,
      services.healthSteps.requestAccess(),
      errorPrefix: 'Could not request Health access',
    );
    if (!context.mounted) return;
    setState(() => _healthStatus = access ?? HealthAccessState.unknown);
    switch (access) {
      case HealthAccessState.readable:
        showSnack(context, 'Health data is readable. Steps and sleep can be synced.');
      case HealthAccessState.requested:
        showSnack(
          context,
          'Access requested, not confirmed readable. Apple does not reveal read access; allow Steps and Sleep for Lifelog in Health if syncing does not work.',
        );
      case HealthAccessState.unavailable:
      case HealthAccessState.unknown:
      case null:
        await _showHealthAccessHelp(context);
    }
  }

  Future<void> _showHealthAccessHelp(BuildContext context) {
    final isApple = Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS;
    return showLifelogSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            title: 'Enable Health access',
            subtitle: 'Read-only access for sleep and steps',
          ),
          if (isApple) ...const [
            _PrivacyPoint(
              icon: Icons.health_and_safety_outlined,
              title: 'Allow in Apple Health',
              body: 'Open Health > Browse > Sleep/Steps (or Profile > Apps > Lifelog) and turn on Steps and Sleep for Lifelog. '
                  'You can also go to iPhone Settings > Privacy & Security > Health > Lifelog.',
            ),
            _PrivacyPoint(
              icon: Icons.visibility_off_outlined,
              title: 'Privacy note',
              body: 'Apple does not tell apps whether read access was granted. If sync shows no data after allowing access, check Health permissions and make sure sleep/step data exists in Health.',
            ),
          ] else ...const [
            _PrivacyPoint(
              icon: Icons.health_and_safety_outlined,
              title: 'Allow in Health Connect',
              body: 'Open Health Connect and allow Lifelog to read Steps and Sleep. Make sure Health Connect is installed/enabled on your device.',
            ),
          ],
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  void _showScreenTimeInfo(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    showLifelogSheet<void>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(
            title: 'Screen Time and app usage (advanced)',
            subtitle: isAndroid
                ? 'How Android app usage access works'
                : 'How iPhone Screen Time access works',
          ),
          const _PrivacyPoint(
            icon: Icons.phone_iphone_rounded,
            title: 'iPhone (Screen Time API)',
            body:
                'Reading Screen Time/app usage on iOS requires Apple Screen Time APIs (Family Controls, DeviceActivity, ManagedSettings). The app needs the Family Controls capability/entitlement (com.apple.developer.family-controls), Apple approval for distribution, and explicit user authorization on device. Implementations often require Screen Time extension targets (report/monitor/shield) and must follow strict Apple use-case and privacy rules. A regular journaling app cannot access Screen Time stats like Health steps without this approved setup.',
          ),
          const _PrivacyPoint(
            icon: Icons.android_rounded,
            title: 'Android (Usage Access)',
            body:
                'On Android, app usage/screen time can be read via UsageStatsManager with the special PACKAGE_USAGE_STATS permission. This cannot be granted by a normal runtime prompt: the user must enable Usage access for the app in system Settings. Once granted, apps can query aggregated usage (such as daily foreground time per app) locally. This build declares the permission; a full in-app usage stats integration may vary by device/build.',
          ),
          const _PrivacyPoint(
            icon: Icons.verified_user_outlined,
            title: 'Current status in Lifelog',
            body:
                'Automatic Screen Time/app usage import is not enabled in this build. iPhone access requires Apple Family Controls entitlement and approval that this app does not currently have.',
          ),
          const _PrivacyPoint(
            icon: Icons.lightbulb_outline_rounded,
            title: 'What you can do now',
            body:
                'iPhone: view usage in Settings > Screen Time. Android: view Digital Wellbeing or enable/check Usage access in system settings. You can manually record a daily note or tracker in Lifelog. To ship true iPhone Screen Time features, request Family Controls entitlement/approval from Apple and implement the required Screen Time authorization and extensions.',
          ),
          if (isAndroid) ...[
            const SizedBox(height: Insets.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await Geolocator.openAppSettings();
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open app settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _syncTodayFromHealth(BuildContext context, WidgetRef ref) async {
    final services = ref.read(appServicesProvider);
    if (!services.healthSteps.isSupported) {
      showSnack(
        context,
        'Health sync is available on supported devices (Apple Health / Health Connect).',
      );
      return;
    }
    final access = await guard<HealthAccessState>(
      context,
      services.healthSteps.requestAccess(),
      errorPrefix: 'Could not access Health data',
    );
    if (access == HealthAccessState.unavailable && context.mounted) {
      await _showHealthAccessHelp(context);
      return;
    }
    if (!context.mounted) return;
    final today = DateTime.now();
    final summary = await guard(
      context,
      services.healthSteps.getDailySummary(today),
      errorPrefix: 'Could not read Health data',
    );
    if (!context.mounted || summary == null) return;
    if (summary.steps == null && summary.sleepHours == null) {
      showSnack(
        context,
        'No sleep or step data found in Health for today. If access is enabled, make sure data exists in Health.',
      );
      return;
    }
    final archive = ref.read(archiveProvider);
    final metricsId = 'day-${dayKey(today)}';
    final existing =
        archive.entryById(metricsId) ?? archive.dayMetricsEntryFor(today);
    final base = existing ??
        JournalEntry(
          id: metricsId,
          createdAt: momentForDay(today),
          updatedAt: DateTime.now(),
          title: '',
          body: '',
          draft: false,
        );
    var next = base.copyWith(updatedAt: DateTime.now());
    if (summary.steps != null) next = next.copyWith(steps: summary.steps);
    if (summary.sleepHours != null) {
      next = next.copyWith(sleepHours: summary.sleepHours);
    }
    await guard(
      context,
      ref.read(archiveProvider.notifier).saveEntry(next),
      errorPrefix: 'Could not save Health data',
    );
    if (!context.mounted) return;
    final parts = <String>[];
    if (summary.sleepHours != null) {
      final v = summary.sleepHours!;
      parts.add(
        'sleep ${v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1)} hr',
      );
      if (summary.sleepSampleCount > 0) {
        parts.add('${summary.sleepSampleCount} sleep samples merged');
      }
    }
    if (summary.steps != null) parts.add('${summary.steps} steps');
    showSnack(context, 'Synced ${parts.join(' · ')} for today (Health).');
  }

  Future<void> _editReminder(
    BuildContext context,
    WidgetRef ref,
    ReminderItem? existing,
  ) async {
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final noteController = TextEditingController(text: existing?.note ?? '');
    var time = TimeOfDay(
      hour: existing?.hour ?? 20,
      minute: existing?.minute ?? 0,
    );
    var repeat = existing?.repeat ?? ReminderRepeat.daily;
    var enabled = existing?.enabled ?? true;

    final result = await showLifelogSheet<String>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(
              title: existing == null ? 'Add reminder' : 'Edit reminder',
              subtitle: 'Set a time and message to remind yourself.',
            ),
            TextField(
              controller: titleController,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reminder',
                hintText: 'e.g. Write journal, Review vocab, Evening check-in',
              ),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: noteController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Extra details',
              ),
            ),
            const SizedBox(height: Insets.md),
            ListRow(
              icon: Icons.schedule_rounded,
              title: 'Time',
              subtitle: time.format(sheetContext),
              chevron: true,
              onTap: () async {
                final picked = await showTimePicker(
                  context: sheetContext,
                  initialTime: time,
                );
                if (picked != null) setSheetState(() => time = picked);
              },
            ),
            ListRow(
              icon: Icons.repeat_rounded,
              title: 'Repeat',
              subtitle: repeat.label,
              chevron: true,
              onTap: () async {
                final picked = await showLifelogSheet<ReminderRepeat>(
                  sheetContext,
                  builder: (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SheetTitle(title: 'Repeat'),
                      for (final option in ReminderRepeat.values)
                        ListRow(
                          title: option.label,
                          trailing: option == repeat
                              ? Icon(Icons.check_rounded,
                                  color: ctx.scheme.primary)
                              : null,
                          onTap: () => Navigator.of(ctx).pop(option),
                        ),
                    ],
                  ),
                );
                if (picked != null) setSheetState(() => repeat = picked);
              },
            ),
            ListRow(
              icon: Icons.notifications_outlined,
              title: 'Enabled',
              trailing: Switch(
                value: enabled,
                onChanged: (value) => setSheetState(() => enabled = value),
              ),
              onTap: () => setSheetState(() => enabled = !enabled),
            ),
            const SizedBox(height: Insets.md),
            Row(
              children: [
                if (existing != null)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: sheetContext.scheme.error,
                        side:
                            BorderSide(color: sheetContext.scheme.error),
                      ),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop('delete'),
                      child: const Text('Delete'),
                    ),
                  ),
                if (existing != null) const SizedBox(width: Insets.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop('save'),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final title = titleController.text.trim();
    final note = noteController.text.trim();
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      () {
        titleController.dispose();
        noteController.dispose();
      },
    );

    if (result == null || !context.mounted) return;
    if (result == 'delete' && existing != null) {
      await guard(
        context,
        ref.read(settingsProvider.notifier).deleteReminder(existing.id),
        errorPrefix: 'Could not delete reminder',
      );
      if (context.mounted) showSnack(context, 'Reminder deleted.');
      return;
    }
    if (result == 'save') {
      if (title.isEmpty) {
        showSnack(context, 'Add a reminder message.');
        return;
      }
      final reminder = ReminderItem(
        id: existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        note: note,
        hour: time.hour,
        minute: time.minute,
        enabled: enabled,
        repeat: repeat,
      );
      await guard(
        context,
        ref.read(settingsProvider.notifier).saveReminder(reminder),
        errorPrefix: 'Could not save reminder',
      );
      if (context.mounted) showSnack(context, 'Reminder saved.');
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
                'Argon2id and can include your media. Everything in the backup file is encrypted and decrypted only in the app with your backup passphrase.',
          ),
          const _PrivacyPoint(
            icon: Icons.cloud_outlined,
            title: 'Network use',
            body: 'No analytics or crash reporting. Optional connections you control: Cloudflare sync (client-side encrypted backups via your Worker), '
                'read-only Last.fm import, album artwork from Last.fm when enabled, and read-only Health/Health Connect step import on supported devices.',
          ),
          const _PrivacyPoint(
            icon: Icons.folder_outlined,
            title: 'Files app (iPhone/iPad)',
            body: 'Encrypted backups saved to the app\'s Backups folder are visible in the Files app. '
                'Your main archive stays encrypted in app storage.',
          ),
          const _PrivacyPoint(
            icon: Icons.my_location_outlined,
            title: 'Location & permissions',
            body:
                'Location is used when you save places/visits and, if you enable day tracking in Places, to record where you spend time while the app is in use. '
                'Location samples stay in your encrypted local archive. '
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
          'Data is saved locally on this device. Cloudflare sync is optional and stores a client-side encrypted backup via your Worker. The backup passphrase never leaves this device.',
          'No automatic multi-device merge. Restoring from a backup replaces local data on that device.',
          'Screen Time/app usage data cannot be read by this app on iPhone without Apple Family Controls entitlement and approval (Family Controls, ManagedSettings, DeviceActivity). This is not currently available in this build.',
          'Automatic steps require Health access on supported devices. Other step sources are not imported automatically.',
          'Encrypted backups exclude media bytes. Keep an extra local copy of your media folder for recovery.',
          'Day location tracking records location while the app is in use. With Background visits on and Location Access set to Always, iOS can report places you visit while the app is closed using place monitoring, not continuous GPS. Events stay in your encrypted local archive.',
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




