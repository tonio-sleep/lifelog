import '../core/util/dates.dart';
import 'models/archive.dart';
import 'models/meals.dart';
import 'models/trackers.dart';

final _mealPrefix = RegExp(
  r'^(breakfast|lunch|dinner|snack|drink|dessert)\s*:\s*(.*)$',
  caseSensitive: false,
);

bool _isLegacyMealTracker(TrackerDefinition tracker) {
  final name = tracker.name.toLowerCase();
  return tracker.icon == 'meal' ||
      tracker.category.toLowerCase() == 'nutrition' ||
      name.contains('ate') ||
      name.contains('eat') ||
      name.contains('meal');
}

({MealKind kind, String name}) _parseMealText(String raw) {
  final text = raw.trim();
  final match = _mealPrefix.firstMatch(text);
  if (match == null) return (kind: MealKind.meal, name: text);
  final prefix = match.group(1)!.toLowerCase();
  final kind = switch (prefix) {
    'drink' => MealKind.drink,
    'snack' || 'dessert' => MealKind.snack,
    _ => MealKind.meal,
  };
  return (kind: kind, name: (match.group(2) ?? '').trim());
}

String _dedupeKey(MealRecord meal) =>
    '${meal.dayKey}|${meal.kind.name}|${meal.name.toLowerCase()}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// One-time, additive migration from the old "What I ate today" habit and the
/// legacy `JournalEntry.meals` string into first-class `MealRecord`s.
///
/// Old fields are left readable. Meal tracker definitions are archived so food
/// stops appearing as a habit, but their records remain in the archive.
Archive migrateLegacyMeals(Archive source) {
  final meals = [...source.meals];
  final seenRefs = <String>{
    for (final meal in meals)
      if (meal.legacyRef != null) meal.legacyRef!,
  };
  final seen = <String>{for (final meal in meals) _dedupeKey(meal)};
  var added = 0;

  void addIfNew(MealRecord meal) {
    if (meal.name.trim().isEmpty) return;
    final ref = meal.legacyRef;
    if (ref != null && !seenRefs.add(ref)) return;
    final key = _dedupeKey(meal);
    if (!seen.add(key)) return;
    meals.add(meal);
    added++;
  }

  final legacyTrackerIds = <String>{};
  for (final tracker in source.trackers) {
    if (!_isLegacyMealTracker(tracker)) continue;
    legacyTrackerIds.add(tracker.id);
    for (final record in source.trackerRecords) {
      if (record.trackerId != tracker.id || record.text.trim().isEmpty) {
        continue;
      }
      final parsed = _parseMealText(record.text);
      final at = record.startedAt ?? record.recordedAt;
      addIfNew(
        MealRecord(
          id: 'legacy-tracker-${record.id}',
          at: at,
          createdAt: record.recordedAt,
          day: dayKey(at),
          kind: parsed.kind,
          name: parsed.name,
          notes: record.note,
          amount: record.value ?? record.count,
          unit: tracker.unit,
          legacyRef: 'tracker:${record.id}',
        ),
      );
    }
  }

  for (final entry in source.entries) {
    final raw = entry.meals.trim();
    if (raw.isEmpty) continue;
    final lines = raw.split(RegExp(r'[\n;]+'));
    for (var i = 0; i < lines.length; i++) {
      final parsed = _parseMealText(lines[i]);
      addIfNew(
        MealRecord(
          id: 'legacy-entry-${entry.id}-$i',
          at: entry.createdAt,
          createdAt: entry.updatedAt,
          day: dayKey(entry.createdAt),
          kind: parsed.kind,
          name: parsed.name,
          notes: '',
          legacyRef: 'entry:${entry.id}:$i',
        ),
      );
    }
  }

  if (added == 0) {
    // Still archive legacy meal trackers so the first run cannot resurrect
    // them on the next launch.
    return Archive(
      entries: source.entries,
      media: source.media,
      trackers: source.trackers
          .map((t) => legacyTrackerIds.contains(t.id)
              ? t.copyWith(active: false, archived: true)
              : t)
          .toList(),
      trackerRecords: source.trackerRecords,
      events: source.events,
      places: source.places,
      visits: source.visits,
      scrobbles: source.scrobbles,
      locationSamples: source.locationSamples,
      meals: source.meals,
    );
  }

  meals.sort((a, b) => a.at.compareTo(b.at));
  return Archive(
    entries: source.entries,
    media: source.media,
    trackers: source.trackers
        .map((t) => legacyTrackerIds.contains(t.id)
            ? t.copyWith(active: false, archived: true)
            : t)
        .toList(),
    trackerRecords: source.trackerRecords,
    events: source.events,
    places: source.places,
    visits: source.visits,
    scrobbles: source.scrobbles,
    locationSamples: source.locationSamples,
    meals: meals,
  );
}
