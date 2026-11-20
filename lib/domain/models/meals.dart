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

  String get dayKey => day ?? dayKeyFor(at);
  String get timeLabel => dates.formatTime(at);

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
  }) {
    final nextAt = at ?? this.at;
    return MealRecord(
      id: id ?? this.id,
      at: nextAt,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      day: day ?? dayKeyFor(nextAt),
      notes: notes ?? this.notes,
      amount: clearAmount ? null : (amount ?? this.amount),
      unit: unit ?? this.unit,
      tags: tags ?? this.tags,
      legacyRef: clearLegacyRef ? null : (legacyRef ?? this.legacyRef),
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
      };

  factory MealRecord.fromJson(Map<String, dynamic> json) {
    final at = DateTime.tryParse(json['at'] as String? ?? '') ??
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now();
    return MealRecord(
      id: json['id'] as String? ?? _uuid.v4(),
      at: at,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      day: json['day'] as String? ?? dayKeyFor(at),
      kind: MealKind.fromJson(json['kind'] as String?),
      name: json['name'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? '',
      tags: (json['tags'] as List? ?? const [])
          .whereType<String>()
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      legacyRef: json['legacyRef'] as String?,
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
