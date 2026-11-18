import '../core/util/dates.dart';
import 'models/trackers.dart';

/// Per-tracker history indexed by day, so streaks and progress are computed
/// from stored records only. Build one per tracker per frame, not per cell.
class HabitHistory {
  HabitHistory(this.tracker, Iterable<TrackerRecord> records) {
    for (final record in records) {
      if (record.trackerId != tracker.id) continue;
      final key = dayKey(record.recordedAt);
      final value = record.value ?? 1;
      _totals[key] = (_totals[key] ?? 0) + value;
      _logged.add(key);
      if (value > 0) _positive.add(key);
    }
  }

  final TrackerDefinition tracker;
  final Map<String, double> _totals = {};
  final Set<String> _logged = {};
  final Set<String> _positive = {};

  bool _doneKey(String key) {
    switch (tracker.type) {
      case TrackerType.boolean:
        return _positive.contains(key);
      case TrackerType.count:
      case TrackerType.number:
      case TrackerType.duration:
      case TrackerType.event:
        final target = tracker.target;
        if (target != null && target > 0) {
          return (_totals[key] ?? 0) >= target;
        }
        return _logged.contains(key);
      case TrackerType.rating:
      case TrackerType.text:
        return _logged.contains(key);
    }
  }

  bool loggedOn(DateTime day) => _logged.contains(dayKey(day));

  /// A yes/no tracker explicitly answered "no" for the day.
  bool skippedOn(DateTime day) {
    final key = dayKey(day);
    return tracker.type == TrackerType.boolean &&
        _logged.contains(key) &&
        !_positive.contains(key);
  }

  bool doneOn(DateTime day) => _doneKey(dayKey(day));

  double totalOn(DateTime day) => _totals[dayKey(day)] ?? 0;

  /// 0..1 toward the day's goal. Trackers without a target are complete once
  /// anything is logged.
  double progressOn(DateTime day) {
    final key = dayKey(day);
    final target = tracker.target;
    final numeric =
        tracker.type == TrackerType.count ||
        tracker.type == TrackerType.number ||
        tracker.type == TrackerType.duration ||
        tracker.type == TrackerType.event;
    if (numeric && target != null && target > 0) {
      return ((_totals[key] ?? 0) / target).clamp(0.0, 1.0);
    }
    return _doneKey(key) ? 1.0 : 0.0;
  }

  /// Consecutive completed days ending today, or yesterday if today is not
  /// done yet (so a streak is not lost before the day is over).
  int currentStreak(DateTime today) {
    var cursor = dayStart(today);
    if (!doneOn(cursor)) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    var streak = 0;
    while (doneOn(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  int bestStreak() {
    final keys = _logged.where(_doneKey).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final key in keys) {
      final day = parseDayKey(key);
      if (previous != null &&
          sameDay(day, DateTime(previous.year, previous.month, previous.day + 1))) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }

  /// Completion for the [count] days ending on [end], oldest first.
  List<bool> lastDays(DateTime end, int count) {
    final last = dayStart(end);
    return List<bool>.generate(count, (index) {
      final day = DateTime(last.year, last.month, last.day - (count - 1 - index));
      return doneOn(day);
    });
  }
}
