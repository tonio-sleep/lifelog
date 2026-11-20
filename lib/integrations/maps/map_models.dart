import 'dart:ui';

/// A coordinate passed between Dart and the native map.
class MapPoint {
  const MapPoint({
    required this.latitude,
    required this.longitude,
    this.id = '',
    this.name = '',
    this.color = 0xFF52796F,
    this.radiusMeters = 120,
    this.kind = 'place',
    this.notes = '',
  });

  final double latitude;
  final double longitude;
  final String id;
  final String name;
  final int color;
  final double radiusMeters;
  final String kind;
  final String notes;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'id': id,
        'name': name,
        'color': color,
        'radiusMeters': radiusMeters,
        'kind': kind,
        'notes': notes,
      };

  static MapPoint fromJson(Map<String, dynamic> json) => MapPoint(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: (json['color'] as num?)?.toInt() ?? 0xFF52796F,
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 120,
        kind: json['kind'] as String? ?? 'place',
        notes: json['notes'] as String? ?? '',
      );

  Color get dartColor => Color(color);
}

/// A result from Apple address / point-of-interest search.
class MapSearchResult {
  const MapSearchResult({
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.subtitle,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String subtitle;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'title': title,
        'subtitle': subtitle,
      };

  static MapSearchResult fromJson(Map<String, dynamic> json) => MapSearchResult(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        title: json['title'] as String? ?? 'Location',
        subtitle: json['subtitle'] as String? ?? '',
      );
}
