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
    // Native ISO strings are UTC ("...Z"). Convert to the device's local zone
    // before grouping samples into calendar days or rendering clock times.
    return DateTime.tryParse(value)?.toLocal();
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

/// Ids that are safe to ack after a flush: events read from the non-destructive
/// peek whose samples were persisted. Failures and empty ids stay in the queue.
List<String> ackableBackgroundEventIds(
  Iterable<BackgroundVisitEvent> events,
  Iterable<String> persistedIds,
) {
  final persisted = persistedIds.toSet();
  return events
      .where((event) => event.id.isNotEmpty && persisted.contains(event.id))
      .map((event) => event.id)
      .toSet()
      .toList();
}

/// Effective Core Location permission for background visit monitoring.
enum BackgroundLocationAuthorization {
  always,
  whenInUse,
  denied,
  restricted,
  notDetermined,
  unknown,
  unavailable,
}

BackgroundLocationAuthorization _parseAuthorization(String? value) {
  switch (value) {
    case 'always':
      return BackgroundLocationAuthorization.always;
    case 'whenInUse':
      return BackgroundLocationAuthorization.whenInUse;
    case 'denied':
      return BackgroundLocationAuthorization.denied;
    case 'restricted':
      return BackgroundLocationAuthorization.restricted;
    case 'notDetermined':
      return BackgroundLocationAuthorization.notDetermined;
    case 'unknown':
      return BackgroundLocationAuthorization.unknown;
    default:
      return BackgroundLocationAuthorization.unavailable;
  }
}

/// What iOS is actually doing, as opposed to what the person toggled.
class BackgroundLocationStatus {
  const BackgroundLocationStatus({
    required this.enabled,
    required this.authorization,
    required this.monitoringActive,
    required this.locationServicesEnabled,
    this.canMonitorVisits = false,
    this.canMonitorSignificantChanges = false,
  });

  final bool enabled;
  final BackgroundLocationAuthorization authorization;
  final bool monitoringActive;
  final bool locationServicesEnabled;
  final bool canMonitorVisits;
  final bool canMonitorSignificantChanges;

  bool get isEffectivelyOn =>
      enabled &&
      monitoringActive &&
      authorization == BackgroundLocationAuthorization.always;

  factory BackgroundLocationStatus.fromMap(Map<dynamic, dynamic> map) {
    return BackgroundLocationStatus(
      enabled: map['enabled'] as bool? ?? false,
      authorization: _parseAuthorization(map['authorization'] as String?),
      monitoringActive: map['monitoringActive'] as bool? ?? false,
      locationServicesEnabled: map['locationServicesEnabled'] as bool? ?? false,
      canMonitorVisits: map['canMonitorVisits'] as bool? ?? false,
      canMonitorSignificantChanges:
          map['canMonitorSignificantChanges'] as bool? ?? false,
    );
  }

  /// Fallback for older native code that only returned a bool from setEnabled.
  factory BackgroundLocationStatus.fromLegacyBool(bool value) {
    return BackgroundLocationStatus(
      enabled: value,
      authorization: value
          ? BackgroundLocationAuthorization.unknown
          : BackgroundLocationAuthorization.unavailable,
      monitoringActive: value,
      locationServicesEnabled: value,
    );
  }
}

const _unavailableBackgroundStatus = BackgroundLocationStatus(
  enabled: false,
  authorization: BackgroundLocationAuthorization.unavailable,
  monitoringActive: false,
  locationServicesEnabled: false,
);

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

  /// Enables or disables native monitoring and returns the effective status.
  Future<BackgroundLocationStatus> setEnabled(bool enabled) async {
    try {
      final result = await _methodChannel.invokeMethod<dynamic>(
        'setEnabled',
        enabled,
      );
      if (result is Map) {
        return BackgroundLocationStatus.fromMap(result);
      }
      return BackgroundLocationStatus.fromLegacyBool(result == true);
    } on MissingPluginException {
      return _unavailableBackgroundStatus;
    } on PlatformException {
      return _unavailableBackgroundStatus;
    }
  }

  /// Current effective status. [enabled] is only a fallback for plugins that
  /// do not implement the newer `locationStatus` method.
  Future<BackgroundLocationStatus> status({bool? enabled}) async {
    try {
      final result = await _methodChannel.invokeMethod<dynamic>('locationStatus');
      if (result is Map) {
        return BackgroundLocationStatus.fromMap(result);
      }
    } on MissingPluginException {
      return _unavailableBackgroundStatus;
    } on PlatformException {
      return _unavailableBackgroundStatus;
    }
    final authorization = await authorizationStatus();
    return BackgroundLocationStatus(
      enabled: enabled ?? false,
      authorization: _parseAuthorization(authorization),
      monitoringActive: false,
      locationServicesEnabled: authorization != null,
    );
  }

  /// Non-destructive peek at events queued by iOS. Events remain native-side
  /// until [ackPending] confirms Dart persisted them.
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

  /// Alias for [takePending], kept for callers that prefer explicit peeking.
  Future<List<BackgroundVisitEvent>> peekPending() => takePending();

  /// Removes only the ids that Dart successfully persisted. Failed writes stay
  /// in the native queue for the next flush.
  Future<void> ackPending(Iterable<String> ids) async {
    final eventIds = ids.toSet().where((id) => id.isNotEmpty).toList();
    if (eventIds.isEmpty) return;
    try {
      await _methodChannel.invokeMethod<void>('ackPending', eventIds);
    } on MissingPluginException {
      // Native queue will be pruned on the next successful ack.
    } on PlatformException {
      // Leave events queued for a retry.
    }
  }

  /// Drop every queued event. Used when background tracking is switched off.
  Future<void> clearPending() async {
    try {
      await _methodChannel.invokeMethod<void>('clearPending');
    } on MissingPluginException {
      // Nothing to clear without the native plugin.
    } on PlatformException {
      // Best effort.
    }
  }

  /// Legacy authorization string accessor.
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
