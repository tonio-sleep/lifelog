import 'package:intl/intl.dart';

/// Local-day helpers. Lifelog stores timestamps as UTC internally but renders
/// everything in the device's current local time. A saved timezone offset may
/// be added when multi-device sync is introduced.
DateTime dayStart(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime dayEnd(DateTime value) {
  final start = dayStart(value);
  return DateTime(start.year, start.month, start.day + 1);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameDayAs(DateTime value, DateTime day) => sameDay(value, day);

String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return DateTime.now();
  return DateTime(
    int.tryParse(parts[0]) ?? 2000,
    int.tryParse(parts[1]) ?? 1,
    int.tryParse(parts[2]) ?? 1,
  );
}

String formatTime(DateTime value) => DateFormat.jm().format(value);

String formatTimeRange(DateTime start, DateTime? end) {
  if (end == null) return formatTime(start);
  return '${formatTime(start)} – ${formatTime(end)}';
}

String formatDayHeader(DateTime value) =>
    DateFormat('EEEE, MMMM d').format(value);

String formatDayLong(DateTime value) =>
    DateFormat('EEEE, MMMM d, y').format(value);

String formatMonthYear(DateTime value) => DateFormat('MMMM y').format(value);

String formatShortDate(DateTime value) => DateFormat('MMM d').format(value);

String relativeDayLabel(DateTime value, {DateTime? now}) {
  final today = dayStart(now ?? DateTime.now());
  final target = dayStart(value);
  // Calendar-day delta in UTC avoids DST changing a local duration to 23 or
  // 25 hours, which would make `inDays` off by one.
  final diff = DateTime.utc(target.year, target.month, target.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  if (diff < 0 && diff > -7) return DateFormat('EEEE').format(value);
  if (target.year == today.year) return DateFormat('EEE, MMM d').format(value);
  return DateFormat('MMM d, y').format(value);
}

String formatDurationMinutes(num minutes) {
  final rounded = minutes.round();
  if (rounded < 60) return '$rounded min';
  final hours = rounded ~/ 60;
  final rest = rounded % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String formatCompactNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String plural(int count, String singular, [String? pluralForm]) =>
    count == 1 ? singular : (pluralForm ?? '${singular}s');

/// A sensible timestamp for a record created "on" [day]: right now when the
/// day is today, otherwise midday so it sorts away from midnight edges.
DateTime momentForDay(DateTime day) {
  final now = DateTime.now();
  if (sameDay(day, now)) return now;
  return DateTime(day.year, day.month, day.day, 12);
}
