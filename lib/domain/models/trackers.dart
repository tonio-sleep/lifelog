import 'package:uuid/uuid.dart';

import '../../core/util/dates.dart';

const _uuid = Uuid();

/// Schema-driven tracker types. A tracker definition can be changed without
/// destroying historical values because records store their own timestamps
/// and the original numeric/text value.
enum TrackerType {
  boolean,
  count,
  number,
  duration,
  rating,
  text,
  event;

  String get label => switch (this) {
    TrackerType.boolean => 'Yes / no',
    TrackerType.count => 'Count',
    TrackerType.number => 'Number',
    TrackerType.duration => 'Duration',
    TrackerType.rating => 'Rating',
    TrackerType.text => 'Note',
    TrackerType.event => 'Event',
  };

  String get description => switch (this) {
    TrackerType.boolean => 'A daily yes or no.',
    TrackerType.count => 'Tap once per occurrence.',
    TrackerType.number => 'A measured value with an optional unit.',
    TrackerType.duration => 'Minutes spent.',
    TrackerType.rating => 'A 1–5 personal rating.',
    TrackerType.text => 'A short written observation.',
    TrackerType.event => 'A timestamped occurrence.',
  };

  static TrackerType parse(String? value) {
    for (final type in TrackerType.values) {
      if (type.name == value) return type;
    }
    return TrackerType.count;
  }
}

class TrackerDefinition {
  const TrackerDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.icon = 'circle',
    this.colorValue = 0xFF6B8F71,
    this.category = 'Personal',
    this.unit = '',
    this.target,
    this.active = true,
    this.archived = false,
    this.multiplePerDay = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final TrackerType type;
  final DateTime createdAt;
  final String icon;
  final int colorValue;
  final String category;
  final String unit;
  final double? target;
  final bool active;
  final bool archived;
  final bool multiplePerDay;
  final int sortOrder;

  bool get isNumeric =>
      type == TrackerType.count ||
      type == TrackerType.number ||
      type == TrackerType.duration ||
      type == TrackerType.rating;

  String get targetLabel {
    if (target == null) return '';
    final unitText = unit.trim().isEmpty ? '' : ' ${unit.trim()}';
    return 'Target ${formatCompactNumber(target!)}$unitText';
  }

  TrackerDefinition copyWith({
    String? name,
    TrackerType? type,
    String? icon,
    int? colorValue,
    String? category,
    String? unit,
    double? target,
    bool clearTarget = false,
    bool? active,
    bool? archived,
    bool? multiplePerDay,
    int? sortOrder,
  }) {
    return TrackerDefinition(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt,
      icon: icon ?? this.icon,
      colorValue: colorValue ?? this.colorValue,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      target: clearTarget ? null : (target ?? this.target),
      active: active ?? this.active,
      archived: archived ?? this.archived,
      multiplePerDay: multiplePerDay ?? this.multiplePerDay,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
    'icon': icon,
    'colorValue': colorValue,
    'category': category,
    'unit': unit,
    'target': target,
    'active': active,
    'archived': archived,
    'multiplePerDay': multiplePerDay,
    'sortOrder': sortOrder,
  };

  factory TrackerDefinition.fromJson(Map<String, dynamic> json) {
    return TrackerDefinition(
      id: json['id'] as String? ?? _uuid.v4(),
      name: json['name'] as String? ?? 'Tracker',
      type: TrackerType.parse(json['type'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      icon: json['icon'] as String? ?? 'circle',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF6B8F71,
      category: json['category'] as String? ?? 'Personal',
      unit: json['unit'] as String? ?? '',
      target: (json['target'] as num?)?.toDouble(),
      active: json['active'] as bool? ?? true,
      archived: json['archived'] as bool? ?? false,
      multiplePerDay: json['multiplePerDay'] as bool? ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  static TrackerDefinition blank() => TrackerDefinition(
    id: _uuid.v4(),
    name: '',
    type: TrackerType.count,
    createdAt: DateTime.now(),
  );
}

class TrackerRecord {
  const TrackerRecord({
    required this.id,
    required this.trackerId,
    required this.recordedAt,
    this.value,
    this.text = '',
    this.note = '',
  });

  final String id;
  final String trackerId;
  final DateTime recordedAt;
  final double? value;
  final String text;
  final String note;

  TrackerRecord copyWith({
    DateTime? recordedAt,
    double? value,
    String? text,
    String? note,
  }) {
    return TrackerRecord(
      id: id,
      trackerId: trackerId,
      recordedAt: recordedAt ?? this.recordedAt,
      value: value ?? this.value,
      text: text ?? this.text,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackerId': trackerId,
    'recordedAt': recordedAt.toIso8601String(),
    'value': value,
    'text': text,
    'note': note,
  };

  factory TrackerRecord.fromJson(Map<String, dynamic> json) {
    return TrackerRecord(
      id: json['id'] as String? ?? _uuid.v4(),
      trackerId: json['trackerId'] as String? ?? '',
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.now(),
      value: (json['value'] as num?)?.toDouble(),
      text: json['text'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }
}

/// Pure tracker calculations, kept outside widgets so they can be tested.
class TrackerMath {
  const TrackerMath._();

  static List<TrackerRecord> recordsOn(
    Iterable<TrackerRecord> records,
    String trackerId,
    DateTime day,
  ) {
    return records
        .where((r) => r.trackerId == trackerId && sameDay(r.recordedAt, day))
        .toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  static bool loggedOn(
    Iterable<TrackerRecord> records,
    String trackerId,
    DateTime day,
  ) {
    return records.any(
      (r) => r.trackerId == trackerId && sameDay(r.recordedAt, day),
    );
  }

  static double totalOn(
    Iterable<TrackerRecord> records,
    String trackerId,
    DateTime day,
  ) {
    final matching = recordsOn(records, trackerId, day);
    return matching.fold<double>(0, (sum, r) => sum + (r.value ?? 1));
  }

  static double? averageOn(
    Iterable<TrackerRecord> records,
    String trackerId,
    DateTime day,
  ) {
    final matching = recordsOn(records, trackerId, day);
    if (matching.isEmpty) return null;
    final total = matching.fold<double>(0, (sum, r) => sum + (r.value ?? 0));
    return total / matching.length;
  }

  /// A short value shown in day summaries. Never invents a value: when there
  /// are no records it returns `null`.
  static String? dailyLabel(
    TrackerDefinition tracker,
    Iterable<TrackerRecord> records,
    DateTime day,
  ) {
    final matching = recordsOn(records, tracker.id, day);
    if (matching.isEmpty) return null;

    switch (tracker.type) {
      case TrackerType.boolean:
        return matching.any((r) => (r.value ?? 0) > 0) ? 'Yes' : 'No';
      case TrackerType.count:
      case TrackerType.event:
        final total = totalOn(records, tracker.id, day).round();
        return total == 1 ? '1 time' : '$total times';
      case TrackerType.duration:
        return formatDurationMinutes(totalOn(records, tracker.id, day));
      case TrackerType.number:
        final total = totalOn(records, tracker.id, day);
        final unit = tracker.unit.trim();
        return '${formatCompactNumber(total)}${unit.isEmpty ? '' : ' $unit'}';
      case TrackerType.rating:
        final average = averageOn(records, tracker.id, day);
        if (average == null) return null;
        return '${average.toStringAsFixed(1)} / 5';
      case TrackerType.text:
        return matching.length == 1
            ? (matching.first.text.isEmpty ? '1 note' : matching.first.text)
            : '${matching.length} notes';
    }
  }

  static String recordLabel(TrackerDefinition tracker, TrackerRecord record) {
    switch (tracker.type) {
      case TrackerType.boolean:
        return (record.value ?? 0) > 0 ? 'Yes' : 'No';
      case TrackerType.count:
      case TrackerType.event:
        return '${formatCompactNumber(record.value ?? 1)}×';
      case TrackerType.duration:
        return formatDurationMinutes(record.value ?? 0);
      case TrackerType.number:
        final unit = tracker.unit.trim();
        final value = formatCompactNumber(record.value ?? 0);
        return unit.isEmpty ? value : '$value $unit';
      case TrackerType.rating:
        return '${formatCompactNumber(record.value ?? 0)} / 5';
      case TrackerType.text:
        return record.text.isEmpty ? 'Note' : record.text;
    }
  }

  /// Series of daily totals for the last [days] days, oldest first.
  static List<({DateTime day, double value})> dailySeries(
    TrackerDefinition tracker,
    Iterable<TrackerRecord> records,
    DateTime endDay,
    int days,
  ) {
    final end = dayStart(endDay);
    return List.generate(days, (index) {
      final day = end.subtract(Duration(days: days - 1 - index));
      final value = switch (tracker.type) {
        TrackerType.rating =>
          averageOn(records, tracker.id, day) ?? 0.0,
        TrackerType.boolean => loggedOn(records, tracker.id, day) ? 1.0 : 0.0,
        TrackerType.text =>
          recordsOn(records, tracker.id, day).length.toDouble(),
        _ => totalOn(records, tracker.id, day),
      };
      return (day: day, value: value);
    });
  }
}
