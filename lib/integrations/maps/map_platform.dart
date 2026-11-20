import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_models.dart';

/// Apple MapKit is used on iOS: detailed tiles, POIs and geocoding without an
/// external API key. Other platforms keep the local schematic fallback.
bool get isNativeMapAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum LifelogMapType { standard, satellite, hybrid }

class LifelogMapData {
  const LifelogMapData({
    required this.places,
    required this.stops,
    required this.route,
    this.current,
    this.privateMode = false,
    this.mapType = LifelogMapType.standard,
    this.followUser = true,
    this.showUser = true,
    this.fitOnLoad = true,
    this.crosshair = false,
  });

  final List<MapPoint> places;
  final List<MapPoint> stops;
  final List<MapPoint> route;
  final MapPoint? current;
  final bool privateMode;
  final LifelogMapType mapType;
  final bool followUser;
  final bool showUser;
  final bool fitOnLoad;
  final bool crosshair;

  LifelogMapData copyWith({
    List<MapPoint>? places,
    List<MapPoint>? stops,
    List<MapPoint>? route,
    MapPoint? current,
    bool clearCurrent = false,
    bool? privateMode,
    LifelogMapType? mapType,
    bool? followUser,
    bool? showUser,
    bool? fitOnLoad,
    bool? crosshair,
  }) {
    return LifelogMapData(
      places: places ?? this.places,
      stops: stops ?? this.stops,
      route: route ?? this.route,
      current: clearCurrent ? null : (current ?? this.current),
      privateMode: privateMode ?? this.privateMode,
      mapType: mapType ?? this.mapType,
      followUser: followUser ?? this.followUser,
      showUser: showUser ?? this.showUser,
      fitOnLoad: fitOnLoad ?? this.fitOnLoad,
      crosshair: crosshair ?? this.crosshair,
    );
  }

  Map<String, dynamic> toJson() => {
        'places': places.map((p) => p.toJson()).toList(),
        'stops': stops.map((p) => p.toJson()).toList(),
        'route': route.map((p) => p.toJson()).toList(),
        'current': current?.toJson(),
        'privateMode': privateMode,
        'mapType': mapType.name,
        'followUser': followUser,
        'showUser': showUser,
        'fitOnLoad': fitOnLoad,
        'crosshair': crosshair,
      };
}

/// Controls one native MKMapView instance.
class LifelogMapController {
  LifelogMapController(this._viewId, this._onPinDropped) {
    _channel = MethodChannel('lifelog/map/$_viewId');
    _channel.setMethodCallHandler(_handleCall);
  }

  final int _viewId;
  final ValueChanged<MapPoint> _onPinDropped;
  late final MethodChannel _channel;

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'pinDropped':
        final point = MapPoint.fromJson(
          Map<String, dynamic>.from(call.arguments as Map),
        );
        _onPinDropped(point);
        return null;
      default:
        return null;
    }
  }

  Future<void> update(LifelogMapData data) =>
      _channel.invokeMethod<void>('update', data.toJson());

  Future<void> setMapType(LifelogMapType type) =>
      _channel.invokeMethod<void>('setMapType', type.name);

  Future<void> centerOn(double latitude, double longitude) => _channel
      .invokeMethod<void>('centerOn', {
        'latitude': latitude,
        'longitude': longitude,
      });

  Future<void> centerOnUser() =>
      _channel.invokeMethod<void>('centerOnUser');

  Future<void> fitAll() => _channel.invokeMethod<void>('fitAll');

  Future<void> dropPinAtCenter() =>
      _channel.invokeMethod<void>('dropPinAtCenter');
}

/// Apple local search and reverse geocoding. Queries go to Apple, but saved
/// archive coordinates and history are never uploaded by Lifelog.
class MapSearchService {
  MapSearchService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('lifelog/map/search');

  final MethodChannel _channel;

  Future<List<MapSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('search', trimmed);
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => MapSearchResult.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((result) => result.latitude.isFinite && result.longitude.isFinite)
        .toList();
  }

  Future<MapSearchResult?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('reverse', {
      'latitude': latitude,
      'longitude': longitude,
    });
    if (raw == null) return null;
    final result = MapSearchResult.fromJson(raw);
    if (!result.latitude.isFinite || !result.longitude.isFinite) return null;
    return result;
  }
}

/// Shared service used by dialogs and the map screen.
final mapSearchServiceProvider = Provider.autoDispose<MapSearchService>(
  (ref) => MapSearchService(),
);
