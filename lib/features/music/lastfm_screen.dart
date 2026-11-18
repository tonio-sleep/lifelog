import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../integrations/lastfm/lastfm_service.dart';
import 'music_dialogs.dart';

class LastfmScreen extends ConsumerStatefulWidget {
  const LastfmScreen({super.key});

  @override
  ConsumerState<LastfmScreen> createState() => _LastfmScreenState();
}

class _LastfmScreenState extends ConsumerState<LastfmScreen> {
  late final TextEditingController _username;
  final _apiKey = TextEditingController();
  int _syncDays = 30;
  bool _busy = false;
  bool _editing = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _username = TextEditingController(text: settings.lastfmUsername ?? '');
  }

  @override
  void dispose() {
    _username.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final text = context.text;
    final connected = settings.lastfmConnected;
    final imported = archive.scrobbles.where((s) => s.source != 'manual').length;
    final manual = archive.scrobbles.where((s) => s.source == 'manual').length;
    final showForm = !connected || _editing;

    return ScreenFrame(
      title: 'Last.fm',
      actions: [
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'Add a track by hand',
          onPressed: () => showManualScrobbleDialog(context, ref),
        ),
      ],
      children: [
        QuietCard(
          child: Row(
            children: [
              IconBadge(
                icon: connected ? Icons.check_rounded : Icons.link_off_rounded,
                color: connected ? palette.tracker : palette.manual,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected ? settings.lastfmUsername! : 'Not connected',
                      style: text.titleMedium,
                    ),
                    Text(
                      connected
                          ? (settings.lastfmLastSync == null
                                ? 'Never synced'
                                : 'Synced ${relativeDayLabel(settings.lastfmLastSync!).toLowerCase()}, '
                                      '${formatTime(settings.lastfmLastSync!)}')
                          : 'Add your username and API key',
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                  ],
                ),
              ),
              if (connected)
                TextButton(
                  onPressed: () => setState(() => _editing = !_editing),
                  child: Text(_editing ? 'Done' : 'Edit'),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: !showForm
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Insets.md),
                  child: QuietCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _username,
                          autocorrect: false,
                          decoration: const InputDecoration(labelText: 'Username'),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _apiKey,
                          obscureText: true,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'API key',
                            hintText: connected ? 'Leave blank to keep the saved key' : null,
                          ),
                        ),
                        const SizedBox(height: Insets.sm),
                        Text(
                          'Create a free key at last.fm/api. It is stored encrypted on this device.',
                          style: text.bodySmall?.copyWith(color: palette.dimText),
                        ),
                        const SizedBox(height: Insets.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _connect,
                            child: Text(connected ? 'Save' : 'Connect'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        if (connected) ...[
          const SectionHeader(title: 'Import'),
          QuietCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fetch the last', style: text.labelMedium?.copyWith(color: palette.mutedText)),
                const SizedBox(height: Insets.sm),
                ChoicePills<int>(
                  values: const [7, 30, 90, 365],
                  selected: _syncDays,
                  labelFor: (days) => days == 365 ? '1 year' : '$days days',
                  onChanged: (value) => setState(() => _syncDays = value),
                ),
                const SizedBox(height: Insets.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(_busy ? 'Working' : 'Sync now'),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.base,
                  curve: Motion.out,
                  alignment: Alignment.topCenter,
                  child: (_status == null && _error == null)
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: Insets.md),
                          child: Text(
                            _error ?? _status!,
                            style: text.bodySmall?.copyWith(
                              color: _error != null
                                  ? context.scheme.error
                                  : palette.mutedText,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ] else if (_error != null || _status != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: Text(
              _error ?? _status!,
              style: text.bodySmall?.copyWith(
                color: _error != null ? context.scheme.error : palette.mutedText,
              ),
            ),
          ),
        ListGroup(
          title: 'Privacy',
          footer: 'Syncing makes read-only requests to Last.fm. Artwork is '
              'loaded from Last.fm image servers only while this is on.',
          children: [
            ListRow(
              icon: Icons.image_outlined,
              iconColor: palette.music,
              title: 'Show album artwork',
              subtitle: 'Off means no image requests at all',
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
          title: 'Your music data',
          children: [
            ListRow(
              icon: Icons.library_music_outlined,
              iconColor: palette.music,
              title: '$imported imported, $manual added by hand',
            ),
            ListRow(
              icon: Icons.delete_outline_rounded,
              title: 'Delete imported music',
              destructive: true,
              onTap: _deleteImported,
            ),
            if (connected)
              ListRow(
                icon: Icons.link_off_rounded,
                title: 'Disconnect Last.fm',
                destructive: true,
                onTap: _busy ? null : _disconnect,
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _connect() async {
    final username = _username.text.trim();
    final typedKey = _apiKey.text.trim();
    final existingKey = await ref
        .read(settingsProvider.notifier)
        .lastfmApiKey();
    final key = typedKey.isEmpty ? existingKey : typedKey;
    if (username.isEmpty) {
      setState(() => _error = 'Enter your Last.fm username.');
      return;
    }
    if (key == null || key.isEmpty) {
      setState(() => _error = 'Enter your Last.fm API key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await ref
          .read(settingsProvider.notifier)
          .connectLastfm(username: username, apiKey: key);
      _apiKey.clear();
      if (!mounted) return;
      setState(() {
        _status = 'Credentials saved. Press Sync now to import tracks.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save credentials: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    final settings = ref.read(settingsProvider);
    final apiKey = await ref
        .read(settingsProvider.notifier)
        .lastfmApiKey();
    final username = settings.lastfmUsername;
    if (username == null || apiKey == null) {
      setState(() => _error = 'Connect Last.fm first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Requesting scrobbles from Last.fm…';
    });
    try {
      final now = DateTime.now();
      final from = now.subtract(Duration(days: _syncDays));
      final tracks = await ref.read(appServicesProvider).lastfm
          .fetchRecentTracks(
            username: username,
            apiKey: apiKey,
            from: from,
            to: now,
            maxPages: 12,
          );
      if (!mounted) return;
      final added = await ref
          .read(archiveProvider.notifier)
          .importScrobbles(tracks);
      await ref
          .read(settingsProvider.notifier)
          .recordLastfmSync(now, tracks.isEmpty ? null : tracks.first.playedAt);
      if (!mounted) return;
      setState(() {
        _status = tracks.isEmpty
            ? 'Last.fm returned no scrobbles in this range.'
            : '$added new ${added == 1 ? 'scrobble' : 'scrobbles'} imported '
                  '(${tracks.length} received).';
      });
    } on LastfmException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Sync failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirm(
      context,
      title: 'Disconnect Last.fm?',
      message:
          'Credentials will be removed from this device. Previously imported '
          'scrobbles remain in the archive unless you delete them separately.',
      confirmLabel: 'Disconnect',
      destructive: false,
    );
    if (!ok) return;
    if (!mounted) return;
    await guard(
      context,
      ref.read(settingsProvider.notifier).disconnectLastfm(),
      errorPrefix: 'Could not disconnect',
    );
    _apiKey.clear();
    if (mounted) {
      setState(() {
        _status = 'Disconnected.';
        _error = null;
      });
    }
  }

  Future<void> _deleteImported() async {
    final archive = ref.read(archiveProvider);
    final count = archive.scrobbles.where((s) => s.source != 'manual').length;
    if (count == 0) {
      showSnack(context, 'There are no imported Last.fm tracks to delete.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Delete imported music?',
      message:
          'This permanently removes $count imported Last.fm '
          '${count == 1 ? 'scrobble' : 'scrobbles'}. Manually added tracks '
          'are kept. Your Last.fm account is not affected.',
    );
    if (!ok) return;
    if (!mounted) return;
    await guard(
      context,
      ref.read(archiveProvider.notifier).removeImportedMusic(),
      errorPrefix: 'Could not delete imported music',
    );
    if (mounted) setState(() => _status = 'Imported music history deleted.');
  }
}

