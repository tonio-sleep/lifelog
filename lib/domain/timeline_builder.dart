import '../core/util/dates.dart';
import 'models/archive.dart';
import 'models/music.dart';
import 'models/timeline.dart';
import 'models/trackers.dart';

/// A single chronological row derived from the underlying records. Timeline
/// rows are views, never duplicated storage.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.at,
    required this.title,
    required this.subtitle,
    required this.source,
    required this.confidence,
    required this.derived,
    this.sourceId,
    this.metadata = const {},
  });

  final String id;
  final DateTime at;
  final String title;
  final String subtitle;
  final TimelineSource source;
  final TimelineConfidence confidence;

  /// Derived rows point at their source record; manual rows are editable.
  final bool derived;
  final String? sourceId;
  final Map<String, String> metadata;
}

/// Builds the unified timeline for a day from journal, trackers, locations,
/// music, photos and manual events. Missing information is never invented.
List<TimelineItem> buildTimelineForDay(
  Archive archive,
  DateTime day, {
  bool includeHidden = false,
}) {
  final items = <TimelineItem>[];

  for (final entry in archive.entriesOn(day)) {
    items.add(
      TimelineItem(
        id: 'journal:${entry.id}',
        at: entry.createdAt,
        title: entry.displayTitle,
        subtitle: entry.excerpt,
        source: TimelineSource.journal,
        confidence: TimelineConfidence.confirmed,
        derived: true,
        sourceId: entry.id,
      ),
    );
  }

  for (final record in archive.trackerRecordsOn(day)) {
    final tracker = archive.trackerById(record.trackerId);
    if (tracker == null) continue;
    final value = TrackerMath.recordLabel(tracker, record);
    final note = record.note.trim();
    final subtitle = note.isEmpty ? value : '$value · $note';
    items.add(
      TimelineItem(
        id: 'tracker:${record.id}',
        at: record.startedAt ?? record.recordedAt,
        title: tracker.name,
        subtitle: subtitle,
        source: TimelineSource.tracker,
        confidence: TimelineConfidence.confirmed,
        derived: true,
        sourceId: record.id,
        metadata: {'trackerId': tracker.id},
      ),
    );
  }

  for (final visit in archive.visitsOn(day)) {
    final duration = visit.duration;
    final subtitle = [
      visit.endAt == null
          ? 'Since ${formatTime(visit.startAt)}'
          : formatTimeRange(visit.startAt, visit.endAt),
      if (duration != null) formatDurationMinutes(duration.inMinutes),
      if (visit.notes.trim().isNotEmpty) visit.notes.trim(),
    ].join(' · ');
    items.add(
      TimelineItem(
        id: 'visit:${visit.id}',
        at: visit.startAt,
        title: 'At ${visit.label}',
        subtitle: subtitle,
        source: TimelineSource.location,
        confidence: visit.confidence,
        derived: true,
        sourceId: visit.id,
        metadata: {'visitId': visit.id},
      ),
    );
  }

  for (final event in archive.eventsOn(day, includeHidden: includeHidden)) {
    items.add(
      TimelineItem(
        id: 'event:${event.id}',
        at: event.occurredAt,
        title: event.title.isEmpty ? 'Event' : event.title,
        subtitle: event.notes.trim(),
        source: TimelineSource.manual,
        confidence: TimelineConfidence.confirmed,
        derived: false,
        sourceId: event.id,
      ),
    );
  }

  for (final media in archive.mediaOn(day)) {
    items.add(
      TimelineItem(
        id: 'photo:${media.id}',
        at: media.createdAt,
        title: media.displayCaption,
        subtitle: media.caption.trim().isEmpty
            ? '${media.kindLabel} added'
            : media.tags.isEmpty
                ? media.kindLabel
                : media.tags.map((t) => '#$t').join(' '),
        source: TimelineSource.photo,
        confidence: TimelineConfidence.confirmed,
        derived: true,
        sourceId: media.id,
      ),
    );
  }

  items.addAll(_musicSessions(archive.scrobblesOn(day)));

  items.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    if (byTime != 0) return byTime;
    final bySource = a.source.index.compareTo(b.source.index);
    if (bySource != 0) return bySource;
    return a.id.compareTo(b.id);
  });
  return items;
}

/// A single daily music summary row keeps the timeline calm instead of
/// splitting the day into many separate track sessions.
List<TimelineItem> _musicSessions(List<MusicScrobble> scrobbles) {
  if (scrobbles.isEmpty) return const [];
  final plays = [...scrobbles]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
  final summary = MusicDaySummary.fromScrobbles(plays);
  final artistNames = summary.topArtists.take(3).map((a) => a.name).join(' · ');
  var artwork = '';
  for (final play in plays) {
    final url = play.artworkUrl;
    if (url != null && url.trim().isNotEmpty) {
      artwork = url;
      break;
    }
  }
  return [
    TimelineItem(
      id: 'music:${dayKey(plays.first.playedAt)}',
      at: plays.first.playedAt,
      title: 'Listened to ${plays.length} ${plays.length == 1 ? 'track' : 'tracks'}',
      subtitle: artistNames,
      source: TimelineSource.music,
      confidence: TimelineConfidence.confirmed,
      derived: true,
      metadata: {
        'artwork': artwork,
        'artist': artistNames,
        'track': 'Listening session',
      },
    ),
  ];
}
