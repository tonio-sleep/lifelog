import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up a human-readable name (shop, cafe, park, street...) for a spot.
///
/// Uses OpenStreetMap Nominatim reverse geocoding. Only rounded coordinates
/// are sent, results are cached for the session, and requests are spaced out
/// to respect the public service's one-request-per-second policy. Callers must
/// only use this when the person has allowed place-name lookups.
class PlaceNameResolver {
  PlaceNameResolver._();

  static final PlaceNameResolver instance = PlaceNameResolver._();

  /// A stay must last at least this long before we try to name it.
  static const minimumStay = Duration(minutes: 5);

  static const _endpoint = 'nominatim.openstreetmap.org';
  static const _spacing = Duration(milliseconds: 1100);

  final http.Client _client = http.Client();
  final Map<String, String?> _cache = <String, String?>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  Future<void> _queue = Future<void>.value();

  /// ~11 m grid so repeated visits to the same spot share one lookup.
  static String keyFor(double lat, double lon) =>
      '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

  /// True once a lookup finished (even when it found nothing).
  bool hasAttempted(double lat, double lon) =>
      _cache.containsKey(keyFor(lat, lon));

  /// The name found earlier, or null when unknown / not looked up yet.
  String? cached(double lat, double lon) => _cache[keyFor(lat, lon)];

  Future<String?> resolve(double lat, double lon) {
    final key = keyFor(lat, lon);
    if (_cache.containsKey(key)) return Future<String?>.value(_cache[key]);
    return _inFlight.putIfAbsent(key, () {
      final completer = Completer<String?>();
      _queue = _queue.then((_) async {
        String? name;
        var failed = false;
        try {
          name = await _fetch(lat, lon).timeout(const Duration(seconds: 8));
        } catch (_) {
          failed = true;
        }
        // Network failures are not cached so a later attempt can succeed.
        if (!failed) _cache[key] = name;
        _inFlight.remove(key);
        completer.complete(name);
        await Future<void>.delayed(_spacing);
      });
      return completer.future;
    });
  }

  Future<String?> _fetch(double lat, double lon) async {
    final uri = Uri.https(_endpoint, '/reverse', {
      'format': 'jsonv2',
      'lat': lat.toStringAsFixed(5),
      'lon': lon.toStringAsFixed(5),
      'zoom': '18',
      'addressdetails': '1',
      'namedetails': '1',
    });
    final response = await _client.get(uri, headers: const {
      'User-Agent': 'Lifelog/1.0 (personal journal app)',
      'Accept-Language': 'en',
    });
    if (response.statusCode != 200) {
      throw http.ClientException('Lookup failed (${response.statusCode})');
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) return null;
    return nameFromResponse(json);
  }

  /// Picks the most useful short name from a Nominatim reverse response.
  static String? nameFromResponse(Map<String, dynamic> json) {
    String? clean(Object? v) {
      final s = v is String ? v.trim() : '';
      return s.isEmpty ? null : s;
    }

    final named = clean(json['name']) ??
        clean((json['namedetails'] as Map?)?['name']);
    if (named != null) return named;

    final address = json['address'];
    if (address is Map) {
      for (final key in const [
        'amenity',
        'shop',
        'tourism',
        'leisure',
        'office',
        'building',
        'historic',
        'craft',
      ]) {
        final v = clean(address[key]);
        if (v != null) return v;
      }
      final road = clean(address['road']) ?? clean(address['pedestrian']);
      if (road != null) {
        final number = clean(address['house_number']);
        return number == null ? road : '$number $road';
      }
      for (final key in const [
        'neighbourhood',
        'suburb',
        'village',
        'town',
        'city',
      ]) {
        final v = clean(address[key]);
        if (v != null) return v;
      }
    }
    final display = clean(json['display_name']);
    if (display == null) return null;
    return display.split(',').take(2).map((p) => p.trim()).join(', ');
  }
}
