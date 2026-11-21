import 'package:uuid/uuid.dart';

import '../../core/util/dates.dart';

const _uuid = Uuid();

/// One scrobble imported from Last.fm. Individual plays are preserved so the
/// timeline can show what was playing at a particular moment.
class MusicScrobble {
  const MusicScrobble({
    required this.id,
    required this.artist,
    required this.title,
    required this.playedAt,
    this.album = '',
    this.artworkUrl,
    this.durationSeconds,
    this.source = 'lastfm',
  });

  final String id;
  final String artist;
  final String title;
  final DateTime playedAt;
  final String album;
  final String? artworkUrl;
  final int? durationSeconds;
  final String source;

  /// Stable key used to avoid duplicate imports on repeated synchronisation.
  String get dedupeKey => '$source|${playedAt.toUtc().millisecondsSinceEpoch}|'
      '${artist.trim().toLowerCase()}|${title.trim().toLowerCase()}';

  String get displayTitle => title.trim().isEmpty ? 'Unknown track' : title;
  String get displayArtist =>
      artist.trim().isEmpty ? 'Unknown artist' : artist;

  Map<String, dynamic> toJson() => {
    'id': id,
    'artist': artist,
    'title': title,
    'playedAt': playedAt.toIso8601String(),
    'album': album,
    'artworkUrl': artworkUrl,
    'durationSeconds': durationSeconds,
    'source': source,
  };

  factory MusicScrobble.fromJson(Map<String, dynamic> json) {
    return MusicScrobble(
      id: json['id'] as String? ?? _uuid.v4(),
      artist: json['artist'] as String? ?? '',
      title: json['title'] as String? ?? '',
      playedAt: parseTimestampOr(json['playedAt'], DateTime.now()),
      album: json['album'] as String? ?? '',
      artworkUrl: json['artworkUrl'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      source: json['source'] as String? ?? 'lastfm',
    );
  }

  static MusicScrobble manual({
    required String artist,
    required String title,
    String album = '',
    DateTime? playedAt,
  }) {
    return MusicScrobble(
      id: _uuid.v4(),
      artist: artist,
      title: title,
      album: album,
      playedAt: playedAt ?? DateTime.now(),
      source: 'manual',
    );
  }
}

/// Daily music statistics derived from scrobbles.
class MusicDaySummary {
  const MusicDaySummary({
    required this.scrobbles,
    required this.topArtists,
    required this.topTracks,
  });

  final List<MusicScrobble> scrobbles;
  final List<({String name, int plays})> topArtists;
  final List<({String name, String artist, int plays})> topTracks;

  int get total => scrobbles.length;
  int get uniqueTracks =>
      scrobbles.map((s) => '${s.artist}|${s.title}'.toLowerCase()).toSet().length;
  int get uniqueArtists =>
      scrobbles.map((s) => s.artist.toLowerCase()).toSet().length;

  String? get topArtistName => topArtists.isEmpty ? null : topArtists.first.name;

  static MusicDaySummary fromScrobbles(Iterable<MusicScrobble> input) {
    final scrobbles = input.toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));

    final artists = <String, int>{};
    final tracks = <String, ({String name, String artist, int plays})>{};

    for (final scrobble in scrobbles) {
      final artistKey = scrobble.displayArtist;
      artists[artistKey] = (artists[artistKey] ?? 0) + 1;
      final trackKey =
          '${scrobble.displayArtist}|${scrobble.displayTitle}'.toLowerCase();
      final existing = tracks[trackKey];
      tracks[trackKey] = (
        name: scrobble.displayTitle,
        artist: scrobble.displayArtist,
        plays: (existing?.plays ?? 0) + 1,
      );
    }

    final sortedArtists = artists.entries
        .map((entry) => (name: entry.key, plays: entry.value))
        .toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
    final sortedTracks = tracks.values.toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));

    return MusicDaySummary(
      scrobbles: scrobbles,
      topArtists: sortedArtists,
      topTracks: sortedTracks,
    );
  }

  static List<MusicScrobble> recordsOn(
    Iterable<MusicScrobble> scrobbles,
    DateTime day,
  ) {
    return scrobbles.where((s) => sameDay(s.playedAt, day)).toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
  }
}
