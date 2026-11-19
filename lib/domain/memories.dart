import '../core/util/dates.dart';
import 'models/archive.dart';
import 'models/journal.dart';
import 'models/media.dart';
import 'models/music.dart';
import 'models/places.dart';
import 'models/timeline.dart';
import 'models/trackers.dart';

/// Counts for one day. Every count comes from a stored record; nothing is
/// estimated or filled in.
class DaySummary {
  const DaySummary({
    required this.day,
    required this.entries,
    required this.photos,
    required this.visits,
    required this.scrobbles,
    required this.trackerRecords,
    required this.events,
  });

  final DateTime day;
  final List<JournalEntry> entries;
  final List<MediaItem> photos;
  final List<Visit> visits;
  final List<MusicScrobble> scrobbles;
  final List<TrackerRecord> trackerRecords;
  final List<TimelineEvent> events;

  int get totalRecords =>
      entries.length +
      photos.length +
      visits.length +
      scrobbles.length +
      trackerRecords.length +
      events.length;

  bool get isEmpty => totalRecords == 0;

  MusicDaySummary get music => MusicDaySummary.fromScrobbles(scrobbles);

  static DaySummary of(Archive archive, DateTime day) {
    return DaySummary(
      day: dayStart(day),
      entries: archive.entriesOn(day),
      photos: archive.mediaOn(day),
      visits: archive.visitsOn(day),
      scrobbles: archive.scrobblesOn(day),
      trackerRecords: archive.trackerRecordsOn(day),
      events: archive.eventsOn(day),
    );
  }
}

/// A previous year's record of the same month and day. Only complete, stored
/// records are described; gaps are not filled with guesses.
class OnThisDayMemory {
  const OnThisDayMemory({required this.day, required this.summary});
  final DateTime day;
  final DaySummary summary;

  int get yearsAgo => DateTime.now().year - day.year;

  String get relativeLabel {
    if (yearsAgo == 1) return 'One year ago today';
    if (yearsAgo > 1) return '$yearsAgo years ago today';
    return 'Earlier today';
  }

  /// A plain-language summary derived only from counts present in the archive.
  String get description {
    final parts = <String>[];
    final s = summary;
    if (s.entries.isNotEmpty) {
      parts.add(
        '${s.entries.length} journal ${plural(s.entries.length, 'entry', 'entries')}',
      );
    }
    if (s.photos.isNotEmpty) {
      parts.add('${s.photos.length} ${plural(s.photos.length, 'photo')}');
    }
    if (s.visits.isNotEmpty) {
      final uniquePlaces = s.visits.map((v) => v.label).toSet().length;
      parts.add(
        '$uniquePlaces ${plural(uniquePlaces, 'place')} visited',
      );
    }
    if (s.scrobbles.isNotEmpty) {
      parts.add('${s.scrobbles.length} ${plural(s.scrobbles.length, 'track')}');
    }
    if (s.trackerRecords.isNotEmpty) {
      parts.add(
        '${s.trackerRecords.length} tracker '
        '${plural(s.trackerRecords.length, 'record')}',
      );
    }
    if (s.events.isNotEmpty) {
      parts.add('${s.events.length} ${plural(s.events.length, 'event')}');
    }
    if (parts.isEmpty) return 'No records for this day.';
    return 'You recorded ${_join(parts)}.';
  }

  static String _join(List<String> parts) {
    if (parts.length == 1) return parts.first;
    if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// Finds matching month/day records from previous years, newest first.
List<OnThisDayMemory> onThisDay(Archive archive, DateTime today) {
  final memories = <OnThisDayMemory>[];
  final currentYear = today.year;
  // A decade is enough to keep the view calm; add more years only if they
  // actually contain records.
  for (var year = currentYear - 1; year >= currentYear - 25; year--) {
    final probe = DateTime(year, today.month, today.day);
    final summary = DaySummary.of(archive, probe);
    if (summary.isEmpty) continue;
    memories.add(OnThisDayMemory(day: probe, summary: summary));
  }
  return memories;
}

/// Days in a month that contain any record. Used for the calendar's quiet
/// activity indicators.
Set<int> activityDays(Archive archive, DateTime month) =>
    archive.activityDaysIn(month);

/// Days with records in earlier years for the same month. Used for the quiet
/// “earlier this month” shortcuts in the memory explorer.
List<DaySummary> activeDaysInPreviousYears(
  Archive archive,
  DateTime month, {
  int years = 10,
}) {
  final results = <DaySummary>[];
  for (var year = month.year - 1; year >= month.year - years; year--) {
    final daysInMonth = DateTime(year, month.month + 1, 0).day;
    for (var day = 1; day <= daysInMonth; day++) {
      final summary = DaySummary.of(
        archive,
        DateTime(year, month.month, day),
      );
      if (!summary.isEmpty) results.add(summary);
    }
  }
  results.sort((a, b) => b.day.compareTo(a.day));
  return results;
}

/// The average mood score for a day (1-10), if any entry records one.
/// Rounded to nearest int for display. This is a stored value, not an
/// inferred emotional assessment.
int? dominantMood(Archive archive, DateTime day) {
  final entries = archive
      .entriesOn(day, includeDrafts: true)
      .where((e) => e.mood != null)
      .toList();
  if (entries.isEmpty) return null;
  final total = entries.fold<int>(0, (sum, e) => sum + e.mood!);
  return (total / entries.length).round().clamp(1, 10);
}

/// Consecutive days, ending today (or yesterday if today is still empty), on
/// which you personally logged something: a journal entry, tracker log, photo
/// or video, visit, event or manually added track. Days that only contain
/// imported Last.fm listening never count towards the streak.
int currentStreak(Archive archive, DateTime today) {
  final days = <String>{};
  for (final entry in archive.entries) {
    if (!entry.draft && !entry.archived) days.add(dayKey(entry.createdAt));
  }
  for (final item in archive.media) {
    days.add(dayKey(item.createdAt));
  }
  for (final visit in archive.visits) {
    days.add(dayKey(visit.startAt));
  }
  for (final scrobble in archive.scrobbles) {
    if (scrobble.source == 'manual') days.add(dayKey(scrobble.playedAt));
  }
  for (final record in archive.trackerRecords) {
    days.add(dayKey(record.recordedAt));
  }
  var cursor = dayStart(today);
  if (!days.contains(dayKey(cursor))) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var streak = 0;
  while (days.contains(dayKey(cursor))) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return streak;
}
