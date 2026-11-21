import 'package:uuid/uuid.dart';

import '../../core/util/dates.dart';
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
      createdAt: parseTimestampOr(json['createdAt'], DateTime.now()),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 120,
      notes: json['notes'] as String? ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF52796F,
    );
  }
}

/// A recorded location sample used for on-device visit tracking.
/// Samples are stored locally in the encrypted archive and can be used to
/// estimate where time was spent during the day.
class LocationSample {
  const LocationSample({
    required this.id,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.speedMps,
  });

  final String id;
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  /// Device-reported speed in meters/second, when available and reliable.
  final double? speedMps;

  Map<String, dynamic> toJson() => {
        'id': id,
        'recordedAt': recordedAt.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'speedMps': speedMps,
      };

  factory LocationSample.fromJson(Map<String, dynamic> json) {
    return LocationSample(
      id: json['id'] as String? ?? _uuid.v4(),
      recordedAt: parseTimestampOr(json['recordedAt'], DateTime.now()),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
    );
  }
}

/// A confirmed or suggested visit. Visits can be logged manually or
/// generated on-device from location samples when tracking is enabled.
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
      startAt: parseTimestampOr(json['startAt'], now),
      placeId: json['placeId'] as String?,
      endAt: parseTimestamp(json['endAt']),
      confidence: confidence,
      notes: json['notes'] as String? ?? '',
    );
  }
}
