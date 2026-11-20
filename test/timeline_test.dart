import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/meals.dart';
import 'package:lifelog/domain/models/timeline.dart';
import 'package:lifelog/domain/models/trackers.dart';
import 'package:lifelog/domain/timeline_builder.dart';

void main() {
  final day = DateTime(2026, 5, 10);

  test('timeline merges real records in chronological order', () {
    final archive = Archive(
      entries: [
        JournalEntry(
          id: 'e1',
          createdAt: DateTime(2026, 5, 10, 9, 30),
          updatedAt: DateTime(2026, 5, 10, 9, 30),
          title: 'Morning note',
          body: 'Wrote an entry.',
        ),
      ],
      trackers: [
        TrackerDefinition(
          id: 't1',
          name: 'Water',
          type: TrackerType.count,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      trackerRecords: [
        TrackerRecord(
          id: 'r1',
          trackerId: 't1',
          recordedAt: DateTime(2026, 5, 10, 8),
          value: 2,
        ),
      ],
      events: [
        TimelineEvent(
          id: 'm1',
          title: 'Manual event',
          occurredAt: DateTime(2026, 5, 10, 11),
        ),
      ],
    );

    final items = buildTimelineForDay(archive, day);

    expect(items.map((item) => item.source), [
      TimelineSource.tracker,
      TimelineSource.journal,
      TimelineSource.manual,
    ]);
    expect(items.map((item) => item.at), [
      DateTime(2026, 5, 10, 8),
      DateTime(2026, 5, 10, 9, 30),
      DateTime(2026, 5, 10, 11),
    ]);
  });

  test('hidden manual events are excluded unless requested', () {
    final archive = Archive(
      events: [
        TimelineEvent(
          id: 'm1',
          title: 'Hidden',
          occurredAt: DateTime(2026, 5, 10, 11),
          hidden: true,
        ),
      ],
    );

    expect(buildTimelineForDay(archive, day), isEmpty);
    expect(buildTimelineForDay(archive, day, includeHidden: true), hasLength(1));
  });

  test('timeline for a different day contains no records', () {
    final archive = Archive(
      entries: [
        JournalEntry(
          id: 'e1',
          createdAt: DateTime(2026, 5, 10, 9),
          updatedAt: DateTime(2026, 5, 10, 9),
          title: 'Note',
          body: '',
        ),
      ],
    );

    expect(buildTimelineForDay(archive, DateTime(2026, 5, 11)), isEmpty);
  });

  test('meals appear chronologically with useful detail and honest times', () {
    final archive = Archive(
      entries: [
        JournalEntry(
          id: 'e1',
          createdAt: DateTime(2026, 5, 10, 10),
          updatedAt: DateTime(2026, 5, 10, 10),
          title: 'Note',
          body: '',
        ),
      ],
      meals: [
        MealRecord(
          id: 'm1',
          at: DateTime(2026, 5, 10, 12, 30),
          day: '2026-05-10',
          kind: MealKind.meal,
          name: 'Pasta',
          notes: 'with salad',
          amount: 250,
          unit: 'g',
        ),
        MealRecord(
          id: 'm2',
          at: DateTime(2026, 5, 10, 8),
          day: '2026-05-10',
          kind: MealKind.drink,
          name: 'Coffee',
          timeKnown: false,
        ),
      ],
    );

    final items = buildTimelineForDay(archive, day);

    expect(items.map((item) => item.source), [
      TimelineSource.meal,
      TimelineSource.journal,
      TimelineSource.meal,
    ]);
    final coffee = items.first;
    expect(coffee.title, 'Coffee');
    expect(coffee.subtitle, contains('time not recorded'));
    expect(coffee.metadata['timeKnown'], 'false');
    final pasta = items.last;
    expect(pasta.metadata['mealId'], 'm1');
    expect(pasta.subtitle, contains('250 g'));
    expect(pasta.subtitle, contains('with salad'));
  });

  test('a migrated legacy tracker record is not repeated in the timeline', () {
    final archive = Archive(
      trackers: [
        TrackerDefinition(
          id: 'legacy',
          name: 'What I ate today',
          type: TrackerType.text,
          createdAt: day,
          icon: 'meal',
        ),
      ],
      trackerRecords: [
        TrackerRecord(
          id: 'r1',
          trackerId: 'legacy',
          recordedAt: DateTime(2026, 5, 10, 12),
          text: 'Lunch: Pasta',
        ),
      ],
      meals: [
        MealRecord(
          id: 'meal-1',
          at: DateTime(2026, 5, 10, 12),
          day: '2026-05-10',
          kind: MealKind.meal,
          name: 'Pasta',
          legacyRef: 'tracker:r1',
        ),
      ],
    );

    final items = buildTimelineForDay(archive, day);

    expect(items.where((item) => item.source == TimelineSource.tracker), isEmpty);
    expect(items.where((item) => item.source == TimelineSource.meal), hasLength(1));
  });
}
