import 'package:uuid/uuid.dart';

import '../../core/util/dates.dart' as dates;
import 'journal.dart' show normaliseTags;

const _uuid = Uuid();

/// Food and drink are first-class records, not a generic habit. Meals can be
/// logged several times a day and stay independent of journal entries.
enum MealKind {
  meal,
  drink,
  snack;

  String get label => switch (this) {
        MealKind.meal => 'Meal',
        MealKind.drink => 'Drink',
        MealKind.snack => 'Snack',
      };

  static MealKind fromJson(String? value) =>
      MealKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => MealKind.meal,
      );
}

class MealRecord {
  const MealRecord({
    required this.id,
    required this.at,
    required this.kind,
    required this.name,
    this.createdAt,
    this.day,
    this.notes = '',
    this.amount,
    this.unit = '',
    this.tags = const [],
    this.legacyRef,
    this.timeKnown = true,
  });

  final String id;
  final DateTime at;
  final MealKind kind;
  final String name;
  final DateTime? createdAt;
  final String? day;
  final String notes;
  final double? amount;
  final String unit;
  final List<String> tags;

  /// Identifies a record created by the one-time legacy migration. Keeps the
  /// migration idempotent without touching old archive keys.
  final String? legacyRef;

  /// Legacy journal meal notes never stored a clock time. When false, [at] is
  /// only an ordering anchor and must not be shown as a real time.
  final bool timeKnown;

  String get dayKey => day ?? dayKeyFor(at);

  /// Never fabricate a time for records that only carry a day.
  String get timeLabel => timeKnown ? dates.formatTime(at) : 'time not recorded';

  String get timeDisplay => timeLabel;

  String get amountLabel {
    if (amount == null) return '';
    final value = amount == amount!.roundToDouble()
        ? amount!.toInt().toString()
        : amount!.toStringAsFixed(1);
    return unit.trim().isEmpty ? value : '$value $unit';
  }

  String get searchText => [name, notes, ...tags].join(' ');

  MealRecord copyWith({
    String? id,
    DateTime? at,
    MealKind? kind,
    String? name,
    DateTime? createdAt,
    String? day,
    String? notes,
    double? amount,
    bool clearAmount = false,
    String? unit,
    List<String>? tags,
    String? legacyRef,
    bool clearLegacyRef = false,
    bool? timeKnown,
  }) {
    final nextAt = at ?? this.at;
    final atChanged = at != null && at != this.at;
    // An explicit day is meaningful (the date can be stored independently of
    // the ordering timestamp). Only recompute it when the time actually moves.
    final nextDay = atChanged ? dayKeyFor(nextAt) : (day ?? this.day);
    final nextTimeKnown = timeKnown ?? (atChanged ? true : this.timeKnown);
    return MealRecord(
      id: id ?? this.id,
      at: nextAt,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      day: nextDay,
      notes: notes ?? this.notes,
      amount: clearAmount ? null : (amount ?? this.amount),
      unit: unit ?? this.unit,
      tags: tags ?? this.tags,
      legacyRef: clearLegacyRef ? null : (legacyRef ?? this.legacyRef),
      timeKnown: nextTimeKnown,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': dayKey,
        'createdAt': (createdAt ?? at).toIso8601String(),
        'at': at.toIso8601String(),
        'kind': kind.name,
        'name': name,
        'notes': notes,
        'amount': amount,
        'unit': unit,
        'tags': tags,
        if (legacyRef != null) 'legacyRef': legacyRef,
        'timeKnown': timeKnown,
      };

  factory MealRecord.fromJson(Map<String, dynamic> json) {
    var at = DateTime.tryParse(json['at'] as String? ?? '') ??
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now();
    final storedDay = json['day'] as String?;
    final day = storedDay != null && storedDay.trim().isNotEmpty
        ? storedDay.trim()
        : dayKeyFor(at);
    // Keep the stored day authoritative for grouping while retaining the
    // recorded clock time. Old archives with a slightly drifted timestamp stay
    // readable and still appear on the day the user saved.
    if (dayKeyFor(at) != day) {
      final parsedDay = dates.parseDayKey(day);
      at = DateTime(
        parsedDay.year,
        parsedDay.month,
        parsedDay.day,
        at.hour,
        at.minute,
        at.second,
        at.millisecond,
        at.microsecond,
      );
    }
    final kind = MealKind.fromJson(json['kind'] as String?);
    final rawName = (json['name'] as String? ?? '').trim();
    return MealRecord(
      id: json['id'] as String? ?? _uuid.v4(),
      at: at,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      day: day,
      kind: kind,
      name: rawName.isEmpty ? 'Untitled ${kind.label.toLowerCase()}' : rawName,
      notes: json['notes'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? '',
      tags: (json['tags'] as List? ?? const [])
          .whereType<String>()
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      legacyRef: json['legacyRef'] as String?,
      // Absent in old archives: those records always carried a real `at`.
      timeKnown: json['timeKnown'] is bool ? json['timeKnown'] as bool : true,
    );
  }

  static String dayKeyFor(DateTime at) => dates.dayKey(at);

  static MealRecord create({
    required DateTime at,
    required MealKind kind,
    required String name,
    String notes = '',
    double? amount,
    String unit = '',
    List<String> tags = const [],
  }) {
    final now = DateTime.now();
    return MealRecord(
      id: _uuid.v4(),
      at: at,
      kind: kind,
      name: name.trim(),
      createdAt: now,
      day: dayKeyFor(at),
      notes: notes.trim(),
      amount: amount,
      unit: unit.trim(),
      tags: normaliseTags(tags),
    );
  }
}
