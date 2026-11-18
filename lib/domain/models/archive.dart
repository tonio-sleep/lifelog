import '../../core/util/dates.dart';
import 'journal.dart';
import 'media.dart';
import 'music.dart';
import 'places.dart';
import 'timeline.dart';
import 'trackers.dart';

/// The entire local archive. Persisted as one authenticated, encrypted
/// document. Keeping the working copy in memory makes local search fast and
/// keeps every feature immediately available offline.
class Archive {
  Archive({
    List<JournalEntry>? entries,
    List<MediaItem>? media,
    List<TrackerDefinition>? trackers,
    List<TrackerRecord>? trackerRecords,
    List<TimelineEvent>? events,
    List<Place>? places,
    List<Visit>? visits,
    List<MusicScrobble>? scrobbles,
  }) : entries = entries ?? [],
       media = media ?? [],
       trackers = trackers ?? [],
       trackerRecords = trackerRecords ?? [],
       events = events ?? [],
       places = places ?? [],
       visits = visits ?? [],
       scrobbles = scrobbles ?? [];

  final List<JournalEntry> entries;
  final List<MediaItem> media;
  final List<TrackerDefinition> trackers;
  final List<TrackerRecord> trackerRecords;
  final List<TimelineEvent> events;
  final List<Place> places;
  final List<Visit> visits;
  final List<MusicScrobble> scrobbles;

  factory Archive.empty() => Archive();

  Archive copy() => Archive(
    entries: [...entries],
    media: [...media],
    trackers: [...trackers],
    trackerRecords: [...trackerRecords],
    events: [...events],
    places: [...places],
    visits: [...visits],
    scrobbles: [...scrobbles],
  );

  bool get isEmpty =>
      entries.isEmpty &&
      media.isEmpty &&
      trackers.isEmpty &&
      trackerRecords.isEmpty &&
      events.isEmpty &&
      places.isEmpty &&
      visits.isEmpty &&
      scrobbles.isEmpty;

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  JournalEntry? entryById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  MediaItem? mediaById(String id) {
    for (final item in media) {
      if (item.id == id) return item;
    }
    return null;
  }

  TrackerDefinition? trackerById(String id) {
    for (final tracker in trackers) {
      if (tracker.id == id) return tracker;
    }
    return null;
  }

  Place? placeById(String? id) {
    if (id == null) return null;
    for (final place in places) {
      if (place.id == id) return place;
    }
    return null;
  }

  Visit? visitById(String id) {
    for (final visit in visits) {
      if (visit.id == id) return visit;
    }
    return null;
  }

  List<MediaItem> mediaForEntry(String entryId) {
    return media.where((m) => m.journalEntryId == entryId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<MediaItem> mediaOn(DateTime day) {
    return media.where((m) => sameDay(m.createdAt, day)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<JournalEntry> entriesOn(
    DateTime day, {
    bool includeDrafts = false,
    bool includeArchived = false,
  }) {
    return entries
        .where(
          (e) =>
              sameDay(e.createdAt, day) &&
              (includeDrafts || !e.draft) &&
              (includeArchived || !e.archived),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// The primary journal entry for a day (one-entry-per-day UX).
  /// Prefers non-draft, non-archived entries, then drafts; newest-updated first.
  /// Includes drafts so an in-progress day entry is resumed.
  JournalEntry? dailyEntryFor(DateTime day) {
    final dayEntries = entries.where((e) => sameDay(e.createdAt, day)).toList();
    if (dayEntries.isEmpty) return null;
    int rank(JournalEntry e) {
      if (!e.archived && !e.draft) return 0;
      if (!e.archived && e.draft) return 1;
      return 2;
    }
    dayEntries.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return dayEntries.first;
  }

  List<JournalEntry> get drafts {
    return entries.where((e) => e.draft && !e.archived).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<TrackerDefinition> get activeTrackers {
    return trackers.where((t) => t.active && !t.archived).toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
      });
  }

  List<TrackerRecord> trackerRecordsOn(DateTime day) {
    return trackerRecords.where((r) => sameDay(r.recordedAt, day)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  List<TrackerRecord> recordsForTracker(String trackerId) {
    return trackerRecords.where((r) => r.trackerId == trackerId).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  }

  List<Visit> visitsOn(DateTime day) {
    return visits.where((v) => sameDay(v.startAt, day)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<TimelineEvent> eventsOn(DateTime day, {bool includeHidden = false}) {
    return events
        .where(
          (e) => sameDay(e.occurredAt, day) && (includeHidden || !e.hidden),
        )
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  }

  List<MusicScrobble> scrobblesOn(DateTime day) =>
      MusicDaySummary.recordsOn(scrobbles, day);

  MusicDaySummary musicOn(DateTime day) =>
      MusicDaySummary.fromScrobbles(scrobblesOn(day));

  /// Days in [month] that contain any archive activity, used by the calendar.
  Set<int> activityDaysIn(DateTime month) {
    final days = <int>{};
    void addIfInMonth(DateTime at) {
      if (at.year == month.year && at.month == month.month) {
        days.add(at.day);
      }
    }

    for (final entry in entries) {
      if (!entry.draft && !entry.archived) addIfInMonth(entry.createdAt);
    }
    for (final item in media) {
      addIfInMonth(item.createdAt);
    }
    for (final visit in visits) {
      addIfInMonth(visit.startAt);
    }
    for (final scrobble in scrobbles) {
      addIfInMonth(scrobble.playedAt);
    }
    for (final record in trackerRecords) {
      addIfInMonth(record.recordedAt);
    }
    return days;
  }

  /// A tiny structural signature used to decide whether the month grid needs
  /// to be rebuilt.
  String get signature =>
      '${entries.length}:${media.length}:${trackerRecords.length}:'
      '${visits.length}:${scrobbles.length}:${events.length}:'
      '${places.length}:${trackers.length}';

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'format': 'lifelog-archive',
    'version': 1,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'media': media.map((m) => m.toJson()).toList(),
    'trackers': trackers.map((t) => t.toJson()).toList(),
    'trackerRecords': trackerRecords.map((r) => r.toJson()).toList(),
    'events': events.map((e) => e.toJson()).toList(),
    'places': places.map((p) => p.toJson()).toList(),
    'visits': visits.map((v) => v.toJson()).toList(),
    'scrobbles': scrobbles.map((s) => s.toJson()).toList(),
  };

  factory Archive.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        (json[key] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    return Archive(
      entries: list('entries').map(JournalEntry.fromJson).toList(),
      media: list('media').map(MediaItem.fromJson).toList(),
      trackers: list('trackers').map(TrackerDefinition.fromJson).toList(),
      trackerRecords: list(
        'trackerRecords',
      ).map(TrackerRecord.fromJson).toList(),
      events: list('events').map(TimelineEvent.fromJson).toList(),
      places: list('places').map(Place.fromJson).toList(),
      visits: list('visits').map(Visit.fromJson).toList(),
      scrobbles: list('scrobbles').map(MusicScrobble.fromJson).toList(),
    );
  }
}
