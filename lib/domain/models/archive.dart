import '../../core/util/dates.dart';
import 'journal.dart';
import 'meals.dart';
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
    List<LocationSample>? locationSamples,
    List<MealRecord>? meals,
  }) : entries = entries ?? [],
       media = media ?? [],
       trackers = trackers ?? [],
       trackerRecords = trackerRecords ?? [],
       events = events ?? [],
       places = places ?? [],
       visits = visits ?? [],
       scrobbles = scrobbles ?? [],
       locationSamples = locationSamples ?? [],
       meals = meals ?? [];

  final List<JournalEntry> entries;
  final List<MediaItem> media;
  final List<TrackerDefinition> trackers;
  final List<TrackerRecord> trackerRecords;
  final List<TimelineEvent> events;
  final List<Place> places;
  final List<Visit> visits;
  final List<MusicScrobble> scrobbles;
  final List<LocationSample> locationSamples;
  final List<MealRecord> meals;

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
    locationSamples: [...locationSamples],
    meals: [...meals],
  );

  bool get isEmpty =>
      entries.isEmpty &&
      media.isEmpty &&
      trackers.isEmpty &&
      trackerRecords.isEmpty &&
      events.isEmpty &&
      places.isEmpty &&
      visits.isEmpty &&
      scrobbles.isEmpty &&
      locationSamples.isEmpty &&
      meals.isEmpty;

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

  /// Backward-compatible primary entry lookup for a day.
  /// Prefers a writing/vocab entry, then a check-in/metrics entry.
  JournalEntry? dailyEntryFor(DateTime day) {
    return primaryWritingEntryFor(day) ??
        latestCheckinOn(day) ??
        dayMetricsEntryFor(day) ??
        (entriesOn(day, includeDrafts: true).isEmpty
            ? null
            : entriesOn(day, includeDrafts: true).last);
  }

  /// Entry that carries day-level health metrics (sleep/steps) when synced.
  /// Prefers the stable `day-<dayKey>` entry, then any entry with sleep/steps.
  JournalEntry? dayMetricsEntryFor(DateTime day) {
    final stableId = 'day-${dayKey(day)}';
    final byId = entryById(stableId);
    if (byId != null) return byId;
    final candidates = entries
        .where((e) =>
            sameDay(e.createdAt, day) &&
            (e.sleepHours != null || e.steps != null))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.first;
  }

  /// Best entry to resume for writing (journal/note/vocab), excluding pure check-ins.
  JournalEntry? primaryWritingEntryFor(DateTime day) {
    final candidates = entriesOn(day, includeDrafts: true).where((e) {
      if (e.isVocab) return true;
      if (e.body.trim().isNotEmpty || e.title.trim().isNotEmpty) return true;
      // Draft placeholder with no check-in-only intent.
      if (e.draft && !e.isCheckinEntry) return true;
      return false;
    }).toList();
    if (candidates.isEmpty) return null;
    int rank(JournalEntry e) {
      if (!e.archived && !e.draft) return 0;
      if (!e.archived && e.draft) return 1;
      return 2;
    }

    candidates.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return candidates.first;
  }

  /// Check-in entries for a day (mood/energy/highlight snapshots), newest last.
  List<JournalEntry> checkinsOn(DateTime day) {
    return entriesOn(day, includeDrafts: true)
        .where((e) => e.isCheckinEntry)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  JournalEntry? latestCheckinOn(DateTime day) {
    final items = checkinsOn(day);
    if (items.isEmpty) return null;
    return items.last;
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

  List<LocationSample> locationSamplesOn(DateTime day) {
    return locationSamples.where((s) => sameDay(s.recordedAt, day)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  List<MealRecord> mealsOn(DateTime day) {
    return meals.where((m) => sameDay(m.at, day)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
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
      // Drafts are visible in Journal and Timeline, so they mark the day too.
      if (!entry.archived) addIfInMonth(entry.createdAt);
    }
    for (final item in media) {
      addIfInMonth(item.createdAt);
    }
    for (final visit in visits) {
      addIfInMonth(visit.startAt);
    }
    for (final sample in locationSamples) {
      addIfInMonth(sample.recordedAt);
    }
    for (final scrobble in scrobbles) {
      addIfInMonth(scrobble.playedAt);
    }
    for (final record in trackerRecords) {
      addIfInMonth(record.recordedAt);
    }
    for (final meal in meals) {
      addIfInMonth(meal.at);
    }
    for (final event in events) {
      if (!event.hidden) addIfInMonth(event.occurredAt);
    }
    return days;
  }

  /// A tiny structural signature used to decide whether the month grid needs
  /// to be rebuilt.
  String get signature =>
      '${entries.length}:${media.length}:${trackerRecords.length}:'
      '${visits.length}:${scrobbles.length}:${events.length}:'
      '${places.length}:${trackers.length}:${locationSamples.length}:'
      '${meals.length}';

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
    'locationSamples': locationSamples.map((s) => s.toJson()).toList(),
    'meals': meals.map((m) => m.toJson()).toList(),
  };

  factory Archive.fromJson(Map<String, dynamic> json) {
    // Validate the envelope before parsing. A wrong shape must never turn a
    // real archive into Archive.empty() and silently show empty screens.
    final format = json['format'];
    if (format != null && format != 'lifelog-archive') {
      throw FormatException('Unsupported archive format: $format');
    }
    final version = json['version'];
    if (version != null && version is! int) {
      throw const FormatException('Archive version is not an integer');
    }
    if (version != null && version != 1) {
      throw FormatException('Unsupported archive version: $version');
    }

    List<Map<String, dynamic>> list(String key) {
      final raw = json[key];
      if (raw == null) return const <Map<String, dynamic>>[];
      if (raw is! List) {
        throw FormatException('Archive field "$key" is not a list');
      }
      return raw.map((item) {
        if (item is! Map) {
          throw FormatException('Archive field "$key" has a non-object entry');
        }
        return Map<String, dynamic>.from(item);
      }).toList();
    }

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
      locationSamples: list('locationSamples').map(LocationSample.fromJson).toList(),
      meals: list('meals').map(MealRecord.fromJson).toList(),
    );
  }
}
