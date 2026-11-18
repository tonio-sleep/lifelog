import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../domain/models/music.dart';

class LastfmException implements Exception {
  LastfmException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Minimal Last.fm Web API client for reading a user's recent tracks.
///
/// Only the public API key is required for read-only calls. The Last.fm
/// shared secret is never needed and must never be placed in the Flutter
/// client. Listening history depends entirely on the user's scrobbling setup.
class LastfmService {
  LastfmService({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://ws.audioscrobbler.com/2.0/';
  final http.Client _client;

  Future<List<MusicScrobble>> fetchRecentTracks({
    required String username,
    String apiKey = '',
    DateTime? from,
    DateTime? to,
    int maxPages = 10,
  }) async {
    final user = username.trim();
    final key = apiKey.trim();
    if (user.isEmpty) throw LastfmException('Enter your Last.fm username.');
    if (key.isEmpty) {
      throw LastfmException(
        'A Last.fm API key is required to sync listening history. '
        'Add your API key in Last.fm settings, then try again.',
      );
    }

    final results = <MusicScrobble>[];
    var page = 1;
    var totalPages = 1;

    while (page <= totalPages && page <= maxPages) {
      final query = <String, String>{
        'method': 'user.getrecenttracks',
        'user': user,
        'api_key': key,
        'format': 'json',
        'limit': '200',
        'page': '$page',
        'extended': '1',
        if (from != null)
          'from': '${from.toUtc().millisecondsSinceEpoch ~/ 1000}',
        if (to != null) 'to': '${to.toUtc().millisecondsSinceEpoch ~/ 1000}',
      };

      final uri = Uri.parse(_base).replace(queryParameters: query);
      late final http.Response response;
      try {
        response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 25));
      } catch (error) {
        throw LastfmException(
          'Could not reach Last.fm. Check your connection and try again.',
          error,
        );
      }

      if (response.statusCode != 200) {
        String detail = 'Last.fm returned HTTP ${response.statusCode}.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['message'] is String) {
            final msg = body['message'] as String;
            detail = msg.isEmpty ? detail : 'Last.fm: $msg';
          }
        } catch (_) {}
        throw LastfmException('$detail Check your username and API key.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw LastfmException('Last.fm returned an unexpected response.');
      }
      if (decoded['error'] != null) {
        throw LastfmException(
          'Last.fm: ${decoded['message'] ?? 'request failed'}',
        );
      }

      final recent = decoded['recenttracks'];
      if (recent is! Map<String, dynamic>) break;
      final tracks = recent['track'];
      final trackList = tracks is List ? tracks : (tracks == null ? const [] : [tracks]);

      for (final raw in trackList) {
        if (raw is! Map) continue;
        final track = Map<String, dynamic>.from(raw);
        final attrs = track['@attr'];
        if (attrs is Map && attrs['nowplaying'] == 'true') continue;

        final date = track['date'];
        final uts = date is Map ? int.tryParse('${date['uts']}') : null;
        if (uts == null) continue;

        final artistRaw = track['artist'];
        final artist = artistRaw is Map
            ? (artistRaw['name'] as String? ?? '')
            : (artistRaw as String? ?? '');
        final title = track['name'] as String? ?? '';
        if (title.trim().isEmpty) continue;

        results.add(
          MusicScrobble(
            id: const Uuid().v4(),
            artist: artist.trim(),
            title: title.trim(),
            album: (track['album'] is Map)
                ? ((track['album'] as Map)['#text'] as String? ?? '')
                : (track['album'] as String? ?? ''),
            artworkUrl: _artwork(track['image']),
            playedAt: DateTime.fromMillisecondsSinceEpoch(
              uts * 1000,
              isUtc: true,
            ).toLocal(),
            source: 'lastfm',
          ),
        );
      }

      final pageAttrs = recent['@attr'];
      if (pageAttrs is Map) {
        totalPages = int.tryParse('${pageAttrs['totalPages']}') ?? 1;
      }
      if (trackList.length < 200) break;
      page++;
    }

    results.sort((a, b) => a.playedAt.compareTo(b.playedAt));
    return results;
  }

  String? _artwork(Object? raw) {
    if (raw is! List) return null;
    String? best;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final text = (entry['#text'] as String? ?? '').trim();
      if (text.isNotEmpty) best = text;
    }
    return best;
  }

  void close() => _client.close();
}
