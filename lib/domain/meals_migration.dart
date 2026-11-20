import '../core/util/dates.dart';
import 'models/archive.dart';
import 'models/meals.dart';
import 'models/trackers.dart';

/// Exact markers of the one-time "What I ate today" template. Broad words like
/// "eat" or "ate" are deliberately absent: user habits such as "Eat more
/// vegetables" must never be mistaken for a meal log.
const _legacyMealNames = <String>{
  'what i ate today',
  'what did i eat today',
};
const _legacyMealIds = <String>{
  'meals',
  'meal-log',
  'legacy-meals',
  'what-i-ate-today',
};
const _legacyMealCategories = <String>{'nutrition'};

final _mealPrefix = RegExp(
  r'^(breakfast|lunch|dinner|snack|drink|dessert)\s*:\s*(.+)$',
  caseSensitive: false,
);

String _normalise(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _isLegacyMealTracker(TrackerDefinition tracker) {
  final name = _normalise(tracker.name);
  final id = _normalise(tracker.id);
  final category = _normalise(tracker.category);
  final icon = _normalise(tracker.icon);

  final exactName = _legacyMealNames.contains(name);
  final exactId = _legacyMealIds.contains(id);
  final exactIcon = icon == 'meal';
  final exactCategory = _legacyMealCategories.contains(category);

  // Require an exact template marker plus at least one independent exact
  // marker. A lone word match is never enough.
  if (exactName &&
      (exactIcon || exactCategory || tracker.type == TrackerType.text)) {
    return true;
  }
  if (exactId && (exactIcon || exactCategory || exactName)) return true;
  if (exactIcon && exactCategory && tracker.type == TrackerType.text) {
    return true;
  }
  return false;
}

/// Returns null unless the text has the shape of a legacy meal note
/// (`Lunch: Pasta`, `Drink: Water`, ...). Free-form tracker text is left alone.
({MealKind kind, String name})? _parseMealText(String raw) {
  final match = _mealPrefix.firstMatch(raw.trim());
  if (match == null) return null;
  final prefix = match.group(1)!.toLowerCase();
  final name = (match.group(2) ?? '').trim();
  if (name.isEmpty) return null;
  final kind = switch (prefix) {
    'drink' => MealKind.drink,
    'snack' || 'dessert' => MealKind.snack,
    _ => MealKind.meal,
  };
  return (kind: kind, name: name);
}

String _dedupeKey(MealRecord meal) {
  final time = meal.timeKnown ? formatTime(meal.at) : 'time not recorded';
  final tags = [...meal.tags]..sort();
  return [
    meal.dayKey,
    time,
    meal.kind.name,
    meal.name.trim().toLowerCase(),
    meal.notes.trim().toLowerCase(),
    meal.amountLabel.toLowerCase(),
    meal.unit.trim().toLowerCase(),
    ...tags,
  ].join('|').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Legacy refs already represented by a first-class meal. Used both for
/// migration idempotency and for hiding duplicate tracker rows in the timeline.
Set<String> migratedMealLegacyRefs(Archive archive) => {
      for (final meal in archive.meals)
        if (meal.legacyRef != null) meal.legacyRef!,
    };

bool isMigratedLegacyTrackerRecord(Archive archive, String recordId) =>
    migratedMealLegacyRefs(archive).contains('tracker:$recordId');

Archive _archiveWith(
  Archive source,
  List<MealRecord> meals,
  Set<String> legacyTrackerIds,
) {
  return Archive(
    entries: source.entries,
    media: source.media,
    trackers: source.trackers
        .map(
          (t) => legacyTrackerIds.contains(t.id)
              ? t.copyWith(active: false, archived: true)
              : t,
        )
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

/// One-time, additive migration from the old "What I ate today" habit and the
/// legacy `JournalEntry.meals` string into first-class `MealRecord`s.
///
/// Old fields are left readable. Only exact legacy meal trackers are archived;
/// unrelated habits keep their place. Journal meal notes carry no clock time,
/// so those records are marked [MealRecord.timeKnown] false instead of showing
/// a fabricated time.
Archive migrateLegacyMeals(Archive source) {
  final meals = [...source.meals];
  final seenRefs = migratedMealLegacyRefs(source);
  final seen = <String>{for (final meal in meals) _dedupeKey(meal)};
  var added = 0;

  void addIfNew(MealRecord meal) {
    if (meal.name.trim().isEmpty) return;
    final ref = meal.legacyRef;
    // A ref is a stronger identity than a content heuristic.
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
      if (record.trackerId != tracker.id) continue;
      final parsed = _parseMealText(record.text);
      if (parsed == null) continue;
      final startedAt = record.startedAt;
      final at = startedAt ?? record.recordedAt;
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
          timeKnown: startedAt != null,
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
      if (parsed == null) continue;
      addIfNew(
        MealRecord(
          id: 'legacy-entry-${entry.id}-$i',
          at: entry.createdAt,
          createdAt: entry.updatedAt,
          day: dayKey(entry.createdAt),
          kind: parsed.kind,
          name: parsed.name,
          legacyRef: 'entry:${entry.id}:$i',
          timeKnown: false,
        ),
      );
    }
  }

  if (added == 0) {
    // Still archive exact legacy meal trackers so the first run cannot
    // resurrect them on the next launch.
    return _archiveWith(source, source.meals, legacyTrackerIds);
  }

  meals.sort((a, b) => a.at.compareTo(b.at));
  return _archiveWith(source, meals, legacyTrackerIds);
}
