import '../core/util/dates.dart';
import 'models/archive.dart';

enum SearchKind {
  journal,
  photo,
  tracker,
  place,
  visit,
  music,
  event;

  String get label => switch (this) {
    SearchKind.journal => 'Journal',
    SearchKind.photo => 'Photos',
    SearchKind.tracker => 'Trackers',
    SearchKind.place => 'Places',
    SearchKind.visit => 'Visits',
    SearchKind.music => 'Music',
    SearchKind.event => 'Events',
  };
}

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.date,
    required this.sourceId,
  });

  final SearchKind kind;
  final String title;
  final String subtitle;
  final DateTime date;
  final String sourceId;
}

/// Local-only search. Queries never leave the device: the archive is decrypted
/// in memory and searched here, so no plaintext is sent to a backend.
List<SearchHit> searchArchive(Archive archive, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];

  bool matches(String? text) =>
      text != null && text.toLowerCase().contains(query);

  String snippet(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    final index = clean.toLowerCase().indexOf(query);
    if (index < 0) {
      return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
    }
    final start = (index - 40).clamp(0, clean.length);
    final end = (index + query.length + 80).clamp(0, clean.length);
    return '${start > 0 ? '…' : ''}'
        '${clean.substring(start, end)}'
        '${end < clean.length ? '…' : ''}';
  }

  final hits = <SearchHit>[];

  for (final entry in archive.entries) {
    if (entry.archived) continue;
    final joinedTags = entry.tags.join(' ');
    if (matches(entry.title) ||
        matches(entry.body) ||
        matches(joinedTags) ||
        matches(entry.placeLabel) ||
        matches(entry.mood?.label) ||
        matches(entry.meals) ||
        matches(entry.highlight) ||
        (entry.steps != null && matches('${entry.steps}')) ||
        (entry.sleepHours != null && matches('${entry.sleepHours}'))) {
      final bodyMatch = matches(entry.body);
      final subtitle = bodyMatch
          ? snippet(entry.body)
          : matches(entry.meals)
              ? snippet(entry.meals)
              : matches(entry.highlight)
                  ? snippet(entry.highlight)
                  : entry.tags.join(' ');
      hits.add(
        SearchHit(
          kind: SearchKind.journal,
          title: entry.displayTitle,
          subtitle: subtitle,
          date: entry.createdAt,
          sourceId: entry.id,
        ),
      );
    }
  }

  for (final item in archive.media) {
    if (matches(item.caption) || matches(item.tags.join(' '))) {
      hits.add(
        SearchHit(
          kind: SearchKind.photo,
          title: item.displayCaption,
          subtitle: item.tags.map((t) => '#$t').join(' '),
          date: item.createdAt,
          sourceId: item.id,
        ),
      );
    }
  }

  for (final tracker in archive.trackers) {
    if (matches(tracker.name) ||
        matches(tracker.category) ||
        matches(tracker.unit)) {
      hits.add(
        SearchHit(
          kind: SearchKind.tracker,
          title: tracker.name,
          subtitle: '${tracker.type.label} · ${tracker.category}',
          date: tracker.createdAt,
          sourceId: tracker.id,
        ),
      );
    }
  }

  for (final record in archive.trackerRecords) {
    final tracker = archive.trackerById(record.trackerId);
    if (tracker == null) continue;
    if (matches(record.text) || matches(record.note)) {
      hits.add(
        SearchHit(
          kind: SearchKind.tracker,
          title: '${tracker.name}: '
              '${record.text.isEmpty ? record.note : record.text}',
          subtitle: snippet([record.text, record.note].join(' ')),
          date: record.recordedAt,
          sourceId: tracker.id,
        ),
      );
    }
  }

  for (final place in archive.places) {
    if (matches(place.name) || matches(place.notes)) {
      hits.add(
        SearchHit(
          kind: SearchKind.place,
          title: place.name,
          subtitle: place.hasCoordinates
              ? 'Saved place with coordinates'
              : 'Saved place',
          date: place.createdAt,
          sourceId: place.id,
        ),
      );
    }
  }

  for (final visit in archive.visits) {
    if (matches(visit.label) || matches(visit.notes)) {
      hits.add(
        SearchHit(
          kind: SearchKind.visit,
          title: visit.label,
          subtitle: visit.notes.isEmpty
              ? '${formatTime(visit.startAt)} · ${visit.confidence.label}'
              : snippet(visit.notes),
          date: visit.startAt,
          sourceId: visit.id,
        ),
      );
    }
  }

  for (final scrobble in archive.scrobbles) {
    if (matches(scrobble.title) ||
        matches(scrobble.artist) ||
        matches(scrobble.album)) {
      hits.add(
        SearchHit(
          kind: SearchKind.music,
          title: '${scrobble.displayTitle} · ${scrobble.displayArtist}',
          subtitle: scrobble.album.isEmpty ? 'Last.fm scrobble' : scrobble.album,
          date: scrobble.playedAt,
          sourceId: scrobble.id,
        ),
      );
    }
  }

  for (final event in archive.events) {
    if (event.hidden) continue;
    if (matches(event.title) || matches(event.notes)) {
      hits.add(
        SearchHit(
          kind: SearchKind.event,
          title: event.title,
          subtitle: event.notes.isEmpty
              ? 'Timeline event'
              : snippet(event.notes),
          date: event.occurredAt,
          sourceId: event.id,
        ),
      );
    }
  }

  hits.sort((a, b) => b.date.compareTo(a.date));
  return hits.take(250).toList();
}
