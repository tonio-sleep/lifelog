import 'package:uuid/uuid.dart';

import 'timeline.dart';

const _uuid = Uuid();

/// A saved place. Coordinates are optional: a place can be a simple named
/// label ("Home", "School") without precise coordinates.
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.radiusMeters = 120,
    this.notes = '',
    this.colorValue = 0xFF52796F,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final String notes;
  final int colorValue;

  bool get hasCoordinates => latitude != null && longitude != null;

  Place copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? notes,
    int? colorValue,
    bool clearCoordinates = false,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      latitude: clearCoordinates ? null : (latitude ?? this.latitude),
      longitude: clearCoordinates ? null : (longitude ?? this.longitude),
      radiusMeters: radiusMeters ?? this.radiusMeters,
      notes: notes ?? this.notes,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'notes': notes,
    'colorValue': colorValue,
  };

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String? ?? _uuid.v4(),
      name: json['name'] as String? ?? 'Place',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 120,
      notes: json['notes'] as String? ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF52796F,
    );
  }
}

/// A confirmed or suggested visit. Raw GPS samples are intentionally not
/// invented here; visits are manually logged or captured on demand.
class Visit {
  const Visit({
    required this.id,
    required this.label,
    required this.startAt,
    this.placeId,
    this.endAt,
    this.confidence = TimelineConfidence.confirmed,
    this.notes = '',
  });

  final String id;
  final String label;
  final DateTime startAt;
  final String? placeId;
  final DateTime? endAt;
  final TimelineConfidence confidence;
  final String notes;

  Duration? get duration => endAt?.difference(startAt);

  Visit copyWith({
    String? label,
    DateTime? startAt,
    String? placeId,
    bool clearPlace = false,
    DateTime? endAt,
    bool clearEnd = false,
    TimelineConfidence? confidence,
    String? notes,
  }) {
    return Visit(
      id: id,
      label: label ?? this.label,
      startAt: startAt ?? this.startAt,
      placeId: clearPlace ? null : (placeId ?? this.placeId),
      endAt: clearEnd ? null : (endAt ?? this.endAt),
      confidence: confidence ?? this.confidence,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'startAt': startAt.toIso8601String(),
    'placeId': placeId,
    'endAt': endAt?.toIso8601String(),
    'confidence': confidence.name,
    'notes': notes,
  };

  factory Visit.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final confidence = TimelineConfidence.values.firstWhere(
      (c) => c.name == json['confidence'],
      orElse: () => TimelineConfidence.confirmed,
    );
    return Visit(
      id: json['id'] as String? ?? _uuid.v4(),
      label: json['label'] as String? ?? 'Visit',
      startAt:
          DateTime.tryParse(json['startAt'] as String? ?? '') ?? now,
      placeId: json['placeId'] as String?,
      endAt: DateTime.tryParse(json['endAt'] as String? ?? ''),
      confidence: confidence,
      notes: json['notes'] as String? ?? '',
    );
  }
}
