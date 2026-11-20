import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/models/places.dart';

/// A place/stop observed by iOS while the app was in the background.
class BackgroundVisitEvent {
  const BackgroundVisitEvent({
    required this.id,
    required this.source,
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    this.accuracy,
    this.endedAt,
  });

  final String id;
  final String source;
  final double latitude;
  final double longitude;
  final DateTime startedAt;
  final double? accuracy;
  final DateTime? endedAt;

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  factory BackgroundVisitEvent.fromMap(Map<dynamic, dynamic> map) {
    return BackgroundVisitEvent(
      id: map['id'] as String? ?? '',
      source: map['source'] as String? ?? 'visit',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      startedAt: _parseDate(map['startedAt']) ?? DateTime.now(),
      endedAt: _parseDate(map['endedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'source': source,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
      };
}

String _backgroundEventId(BackgroundVisitEvent event) => event.id.isEmpty
    ? 'background-${event.startedAt.microsecondsSinceEpoch}'
    : event.id;

/// An arrival sample lets the existing stay/travel detector see the beginning
/// of a background visit.
LocationSample backgroundArrivalSample(BackgroundVisitEvent event) =>
    LocationSample(
      id: '${_backgroundEventId(event)}-arrive',
      recordedAt: event.startedAt,
      latitude: event.latitude,
      longitude: event.longitude,
      accuracyMeters: event.accuracy,
    );

/// A visit with a departure becomes two samples so a finite stay is plotted.
/// Significant-change events have no end and therefore produce no departure.
LocationSample? backgroundDepartureSample(BackgroundVisitEvent event) {
  final endedAt = event.endedAt;
  if (endedAt == null || !endedAt.isAfter(event.startedAt)) return null;
  return LocationSample(
    id: '${_backgroundEventId(event)}-depart',
    recordedAt: endedAt,
    latitude: event.latitude,
    longitude: event.longitude,
    accuracyMeters: event.accuracy,
  );
}

/// Thin wrapper around the native visit/significant-change manager in
/// `ios/Runner/AppDelegate.swift`.
class BackgroundLocationChannel {
  BackgroundLocationChannel();

  static const _methodChannel = MethodChannel('lifelog/location');
  static const _eventChannel = EventChannel('lifelog/location/events');

  Stream<BackgroundVisitEvent>? _events;

  Stream<BackgroundVisitEvent> get events => _events ??= _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => BackgroundVisitEvent.fromMap(event as Map<dynamic, dynamic>))
      .asBroadcastStream();

  Future<bool> setEnabled(bool enabled) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setEnabled',
        enabled,
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BackgroundVisitEvent>> takePending() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'takePending',
      );
      return (result ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(BackgroundVisitEvent.fromMap)
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<String?> authorizationStatus() async {
    try {
      return await _methodChannel.invokeMethod<String>('authorizationStatus');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// iOS cannot upgrade When-In-Use to Always programmatically. This opens
  /// Settings so the person can choose Always themselves.
  Future<void> openSettings() => Geolocator.openAppSettings();
}
