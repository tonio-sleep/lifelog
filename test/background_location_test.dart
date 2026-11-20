import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/integrations/location/background_location_channel.dart';

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
    expect(arrival.recordedAt, DateTime.parse('2026-05-10T09:00:00.000Z'));

    expect(departure, isNotNull);
    expect(departure!.id, 'visit-1778400000000-51.51000--0.12000-depart');
    expect(departure.recordedAt, DateTime.parse('2026-05-10T11:30:00.000Z'));
    expect(departure.latitude, arrival.latitude);
    expect(departure.longitude, arrival.longitude);
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
}
