import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/places.dart';
import 'package:lifelog/integrations/health/health_steps_service.dart';
import 'package:lifelog/integrations/location/background_location_channel.dart';
import 'package:lifelog/integrations/location/location_tracking.dart';

void main() {
  test('native visit events become deterministic arrival and departure samples',
      () {
    final event = BackgroundVisitEvent.fromMap({
      'id': 'visit-1778400000000-51.51000--0.12000',
      'source': 'visit',
      'latitude': 51.51,
      'longitude': -0.12,
      'accuracy': 65.0,
      'startedAt': '2026-05-10T09:00:00.000Z',
      'endedAt': '2026-05-10T11:30:00.000Z',
    });

    final arrival = backgroundArrivalSample(event);
    final departure = backgroundDepartureSample(event);

    expect(arrival.id, 'visit-1778400000000-51.51000--0.12000-arrive');
    expect(arrival.latitude, 51.51);
    expect(arrival.longitude, -0.12);
    expect(arrival.accuracyMeters, 65);
    expect(
      arrival.recordedAt,
      DateTime.parse('2026-05-10T09:00:00.000Z').toLocal(),
    );

    expect(departure, isNotNull);
    expect(departure!.id, 'visit-1778400000000-51.51000--0.12000-depart');
    expect(
      departure.recordedAt,
      DateTime.parse('2026-05-10T11:30:00.000Z').toLocal(),
    );
    expect(departure.latitude, arrival.latitude);
    expect(departure.longitude, arrival.longitude);
  });

  test('UTC native timestamps are localized before calendar-day grouping', () {
    const nativeStart = '2026-05-10T23:30:00.000Z';
    const nativeEnd = '2026-05-11T01:15:00.000Z';
    final event = BackgroundVisitEvent.fromMap({
      'id': 'visit-local-day',
      'startedAt': nativeStart,
      'endedAt': nativeEnd,
    });

    final localStart = DateTime.parse(nativeStart).toLocal();
    final localEnd = DateTime.parse(nativeEnd).toLocal();

    expect(event.startedAt.isUtc, isFalse);
    expect(event.endedAt?.isUtc, isFalse);
    expect(event.startedAt, localStart);
    expect(event.endedAt, localEnd);

    // Even in UTC, the parsed value is a local DateTime; in non-UTC zones this
    // is what makes samples land on the correct local day.
    expect(event.startedAt.year, localStart.year);
    expect(event.startedAt.month, localStart.month);
    expect(event.startedAt.day, localStart.day);
    expect(backgroundArrivalSample(event).recordedAt, localStart);
    expect(backgroundDepartureSample(event)?.recordedAt, localEnd);

    final roundTrip = event.toMap();
    expect(
      DateTime.tryParse(roundTrip['startedAt'] as String? ?? ''),
      isNotNull,
    );
    expect((roundTrip['startedAt'] as String).contains('T'), isTrue);
  });

  test('significant-change events have an arrival but no departure', () {
    final event = BackgroundVisitEvent.fromMap({
      'id': 'significant-1778400000000-40.70000--74.00000',
      'source': 'significant',
      'latitude': 40.7,
      'longitude': -74.0,
      'startedAt': '2026-05-10T12:00:00.000Z',
      'endedAt': null,
    });

    expect(backgroundArrivalSample(event).id, endsWith('-arrive'));
    expect(backgroundDepartureSample(event), isNull);
  });

  test('events without a native id still get a stable local id', () {
    final event = BackgroundVisitEvent.fromMap({
      'latitude': 10.0,
      'longitude': 20.0,
      'startedAt': '2026-05-10T15:00:00.000Z',
    });

    final first = backgroundArrivalSample(event);
    final second = backgroundArrivalSample(event);
    expect(first.id, second.id);
    expect(first.id, startsWith('background-'));
    expect(first.id, endsWith('-arrive'));
    expect(event.source, 'visit');
  });

  test('only successfully persisted events are acked', () {
    final saved = BackgroundVisitEvent.fromMap({
      'id': 'visit-saved',
      'startedAt': '2026-05-10T09:00:00.000Z',
    });
    final failed = BackgroundVisitEvent.fromMap({
      'id': 'visit-failed',
      'startedAt': '2026-05-10T10:00:00.000Z',
    });
    final missingId = BackgroundVisitEvent.fromMap({
      'startedAt': '2026-05-10T11:00:00.000Z',
    });

    final acked = ackableBackgroundEventIds(
      [saved, failed, missingId],
      const ['visit-saved'],
    );

    expect(acked, ['visit-saved']);
    expect(acked, isNot(contains('visit-failed')));
    expect(acked, isNot(contains(missingId.id)));
  });

  test('effective status is On only with Always plus active monitoring', () {
    final effective = BackgroundLocationStatus.fromMap({
      'enabled': true,
      'authorization': 'always',
      'monitoringActive': true,
      'locationServicesEnabled': true,
      'canMonitorVisits': true,
    });
    expect(effective.authorization, BackgroundLocationAuthorization.always);
    expect(effective.isEffectivelyOn, isTrue);

    final needsAlways = BackgroundLocationStatus.fromMap({
      'enabled': true,
      'authorization': 'whenInUse',
      'monitoringActive': false,
      'locationServicesEnabled': true,
    });
    expect(needsAlways.isEffectivelyOn, isFalse);
    expect(
      needsAlways.authorization,
      BackgroundLocationAuthorization.whenInUse,
    );

    final restricted = BackgroundLocationStatus.fromMap({
      'enabled': true,
      'authorization': 'restricted',
      'monitoringActive': false,
      'locationServicesEnabled': true,
    });
    expect(restricted.isEffectivelyOn, isFalse);
    expect(
      restricted.authorization,
      BackgroundLocationAuthorization.restricted,
    );

    final legacy = BackgroundLocationStatus.fromLegacyBool(true);
    expect(legacy.enabled, isTrue);
    expect(legacy.isEffectivelyOn, isFalse);
  });

  test('stale last-known location is not labelled as current', () {
    final staleAt = DateTime.now().subtract(const Duration(hours: 2));
    final archive = Archive(
      locationSamples: [
        LocationSample(
          id: 'stale-sample',
          recordedAt: staleAt,
          latitude: 51.5,
          longitude: -0.12,
        ),
      ],
    );

    final summary = LocationTracking.summarizeDay(archive, staleAt);

    expect(summary.status, isNotNull);
    expect(summary.status!.isCurrent, isFalse);
    expect(summary.status!.subtitle, isNot(contains('now')));
    expect(summary.segments, isNotEmpty);
    expect(summary.segments.last.isCurrent, isFalse);
  });

  test('health summary claims data only when a value was actually read', () {
    final syncedOnly = DailyHealthSummary(
      syncedAt: DateTime(2026, 5, 10, 9),
    );
    expect(syncedOnly.hasData, isFalse);
    expect(syncedOnly.hasSteps, isFalse);
    expect(syncedOnly.hasSleep, isFalse);

    const stepsOnly = DailyHealthSummary(steps: 0);
    expect(stepsOnly.hasData, isTrue);
    expect(stepsOnly.hasSteps, isTrue);
    expect(stepsOnly.hasSleep, isFalse);
  });
}
