import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/places.dart';
import 'package:lifelog/integrations/location/location_tracking.dart';

Position fix({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double accuracy = 12,
  double speed = 0,
  bool isMocked = false,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
    isMocked: isMocked,
    hasAccuracy: true,
    hasSpeed: true,
  );
}

void main() {
  final now = DateTime(2026, 5, 10, 10);

  test('unusable fixes are rejected before they can appear as live', () {
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 51.5,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 59, 30),
        ),
        now: now,
      ),
      isTrue,
    );
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 51.5,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 59, 30),
          isMocked: true,
        ),
        now: now,
      ),
      isFalse,
    );
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 51.5,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 50),
        ),
        now: now,
      ),
      isFalse,
    );
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 51.5,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 10, 0, 30),
        ),
        now: now,
      ),
      isFalse,
    );
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 51.5,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 59, 30),
          accuracy: 400,
        ),
        now: now,
      ),
      isFalse,
    );
    expect(
      LocationTracking.isUsablePosition(
        fix(
          latitude: 100,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 59, 30),
        ),
        now: now,
      ),
      isFalse,
    );
  });

  test('samples keep the device fix time and measured precision', () {
    final sample = LocationTracking.sampleFromPosition(
      fix(
        latitude: 51.51,
        longitude: -0.13,
        timestamp: DateTime(2026, 5, 10, 9, 58, 45),
        accuracy: 18,
        speed: 3.5,
      ),
      now: now,
    );

    expect(sample, isNotNull);
    expect(sample!.recordedAt, DateTime(2026, 5, 10, 9, 58, 45));
    expect(sample.accuracyMeters, 18);
    expect(sample.speedMps, 3.5);
  });

  test('best fix prefers precision and teleport jumps are rejected', () {
    final previous = LocationSample(
      id: 'previous',
      recordedAt: DateTime(2026, 5, 10, 9, 55),
      latitude: 51.5,
      longitude: -0.12,
      accuracyMeters: 20,
    );
    final coarse = fix(
      latitude: 51.502,
      longitude: -0.122,
      timestamp: DateTime(2026, 5, 10, 9, 59, 40),
      accuracy: 80,
    );
    final tight = fix(
      latitude: 51.501,
      longitude: -0.121,
      timestamp: DateTime(2026, 5, 10, 9, 59, 30),
      accuracy: 8,
    );

    final best = LocationTracking.chooseBestPosition(
      [coarse, tight],
      previous: previous,
      now: now,
    );
    expect(best, same(tight));

    expect(
      LocationTracking.isPlausiblePosition(tight, previous, now: now),
      isTrue,
    );
    expect(
      LocationTracking.isPlausiblePosition(
        fix(
          latitude: 51.65,
          longitude: -0.12,
          timestamp: DateTime(2026, 5, 10, 9, 59, 30),
        ),
        previous,
        now: now,
      ),
      isFalse,
    );
  });

  test('inferred stops group real nearby samples and keep saved place names',
      () {
    final day = DateTime(2026, 5, 10);
    LocationSample at(int minute, double latitude, double longitude) =>
        LocationSample(
          id: 'sample-$minute',
          recordedAt: DateTime(2026, 5, 10, 9, minute),
          latitude: latitude,
          longitude: longitude,
          accuracyMeters: 12,
        );
    final archive = Archive(
      places: [
        Place(
          id: 'library',
          name: 'Library',
          createdAt: DateTime(2026, 5, 1),
          latitude: 51.5,
          longitude: -0.12,
          radiusMeters: 100,
        ),
      ],
      locationSamples: [
        at(0, 51.5, -0.12),
        at(3, 51.5001, -0.1201),
        at(6, 51.50005, -0.12005),
        at(20, 51.65, -0.12),
      ],
    );

    final stops = LocationTracking.inferStops(archive, day);

    expect(stops, hasLength(1));
    expect(stops.single.label, 'Library');
    expect(stops.single.placeId, 'library');
    expect(stops.single.sampleCount, 3);
    expect(stops.single.startAt, DateTime(2026, 5, 10, 9, 0));
    expect(stops.single.endAt, DateTime(2026, 5, 10, 9, 6));
  });
}
