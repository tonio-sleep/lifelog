import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import 'lastfm_service.dart';

/// Silently syncs recent Last.fm scrobbles if connected.
/// Returns number of newly imported tracks, or null on failure/not connected.
Future<int?> syncLastfmIfConnected(WidgetRef ref, {int fallbackDays = 14}) async {
  final settings = ref.read(settingsProvider);
  if (!settings.lastfmConnected) return null;

  final apiKey = await ref.read(settingsProvider.notifier).lastfmApiKey();
  final username = settings.lastfmUsername;
  if (username == null || apiKey == null || apiKey.isEmpty) return null;

  final now = DateTime.now();
  DateTime from;
  if (settings.lastfmLastSync != null) {
    from = settings.lastfmLastSync!.subtract(const Duration(days: 1));
  } else {
    from = now.subtract(Duration(days: fallbackDays));
  }
  if (from.isAfter(now)) from = now.subtract(Duration(days: fallbackDays));

  try {
    final tracks = await ref.read(appServicesProvider).lastfm.fetchRecentTracks(
      username: username,
      apiKey: apiKey,
      from: from,
      to: now,
      maxPages: 12,
    );
    final added = await ref.read(archiveProvider.notifier).importScrobbles(tracks);
    await ref.read(settingsProvider.notifier).recordLastfmSync(
      now,
      tracks.isEmpty ? settings.lastfmLastSyncFrom : tracks.first.playedAt,
    );
    return added;
  } on LastfmException {
    return null;
  } catch (_) {
    return null;
  }
}
