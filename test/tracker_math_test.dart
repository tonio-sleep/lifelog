import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/models/trackers.dart';

TrackerDefinition tracker(TrackerType type) => TrackerDefinition(
  id: 't1',
  name: 'Tracker',
  type: type,
  createdAt: DateTime(2026, 1, 1),
);

TrackerRecord record(DateTime at, double? value, {String text = ''}) =>
    TrackerRecord(
      id: 'r-${at.microsecondsSinceEpoch}-$value',
      trackerId: 't1',
      recordedAt: at,
      value: value,
      text: text,
    );

void main() {
  test('totals only count records for the requested tracker and day', () {
    final records = [
      record(DateTime(2026, 5, 10, 8), 2),
      record(DateTime(2026, 5, 10, 12), 3),
      record(DateTime(2026, 5, 11, 8), 100),
      TrackerRecord(
        id: 'other',
        trackerId: 't2',
        recordedAt: DateTime(2026, 5, 10, 9),
        value: 50,
      ),
    ];

    expect(TrackerMath.totalOn(records, 't1', DateTime(2026, 5, 10)), 5);
    expect(TrackerMath.loggedOn(records, 't1', DateTime(2026, 5, 10)), isTrue);
    expect(TrackerMath.loggedOn(records, 't1', DateTime(2026, 5, 12)), isFalse);
  });

  test('rating average ignores missing values and empty days', () {
    final records = [
      record(DateTime(2026, 5, 10, 8), 4),
      record(DateTime(2026, 5, 10, 20), 2),
    ];

    expect(TrackerMath.averageOn(records, 't1', DateTime(2026, 5, 10)), 3);
    expect(TrackerMath.averageOn(records, 't1', DateTime(2026, 5, 11)), isNull);
  });

  test('daily series is oldest first and ends on the requested day', () {
    final end = DateTime(2026, 5, 12);
    final records = [
      record(DateTime(2026, 5, 10, 8), 3),
      record(DateTime(2026, 5, 12, 9), 4),
    ];
    final series = TrackerMath.dailySeries(
      tracker(TrackerType.count),
      records,
      end,
      3,
    );

    expect(series.map((point) => point.day), [
      DateTime(2026, 5, 10),
      DateTime(2026, 5, 11),
      DateTime(2026, 5, 12),
    ]);
    expect(series.map((point) => point.value), [3, 0, 4]);
  });

  test('boolean trackers report 1 when marked and 0 when not', () {
    final series = TrackerMath.dailySeries(
      tracker(TrackerType.boolean),
      [record(DateTime(2026, 5, 11, 7), null)],
      DateTime(2026, 5, 12),
      2,
    );

    expect(series[0].value, 1);
    expect(series[1].value, 0);
  });
}
