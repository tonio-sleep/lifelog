import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import '../../integrations/lastfm/lastfm_service.dart';

/// Pulls the last few days of scrobbles. Shared by pull-to-refresh on Today
/// and Music so both behave identically.
Future<({bool ok, String message})> syncLastfmRecent(
  WidgetRef ref, {
  int days = 7,
}) async {
  final settingsController = ref.read(settingsProvider.notifier);
  final archiveController = ref.read(archiveProvider.notifier);
  final lastfm = ref.read(appServicesProvider).lastfm;
  final username = ref.read(settingsProvider).lastfmUsername;
  final apiKey = await settingsController.lastfmApiKey();
  if (username == null || username.trim().isEmpty) {
    return (ok: false, message: 'Connect Last.fm first.');
  }
  try {
    final now = DateTime.now();
    final tracks = await lastfm.fetchRecentTracks(
      username: username,
      apiKey: apiKey ?? '',
      from: now.subtract(Duration(days: days)),
      to: now,
      maxPages: 4,
    );
    final added = await archiveController.importScrobbles(tracks);
    await settingsController.recordLastfmSync(
      now,
      tracks.isEmpty ? null : tracks.first.playedAt,
    );
    return (
      ok: true,
      message: added == 0
          ? 'Already up to date.'
          : '$added new ${plural(added, 'play')} added.',
    );
  } on LastfmException catch (error) {
    return (ok: false, message: error.message);
  } catch (error) {
    return (ok: false, message: 'Sync failed: $error');
  }
}
