import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/meals_migration.dart';
import 'package:lifelog/domain/memories.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/meals.dart';
import 'package:lifelog/domain/models/trackers.dart';

void main() {
  test('meal records round trip through the additive archive key', () {
    final at = DateTime(2026, 5, 10, 13, 30);
    final meal = MealRecord.create(
      at: at,
      kind: MealKind.drink,
      name: '  Coffee  ',
      notes: '  oat milk  ',
      amount: 2.5,
      unit: 'cups',
      tags: const ['Hot', 'Favourite'],
    );

    expect(meal.name, 'Coffee');
    expect(meal.notes, 'oat milk');
    expect(meal.amountLabel, '2.5 cups');
    expect(meal.dayKey, MealRecord.dayKeyFor(at));

    final decoded = MealRecord.fromJson(meal.toJson());
    expect(decoded.id, meal.id);
    expect(decoded.kind, MealKind.drink);
    expect(decoded.name, 'Coffee');
    expect(decoded.amount, 2.5);
    expect(decoded.tags, containsAll(['hot', 'favourite']));

    final archive = Archive.empty();
    final withMeal = Archive(meals: [meal]);
    expect(archive.meals, isEmpty);
    expect(withMeal.meals.single.toJson(), decoded.toJson());
  });

  test('legacy meal habits and entry text migrate once', () {
    final day = DateTime(2026, 5, 10, 12);
    final tracker = TrackerDefinition(
      id: 'meal-habit',
      name: 'What I ate today',
      type: TrackerType.text,
      createdAt: day,
      icon: 'meal',
      unit: 'g',
    );
    final record = TrackerRecord(
      id: 'tracker-1',
      trackerId: tracker.id,
      recordedAt: day,
      startedAt: day,
      text: 'Lunch: Pasta',
      value: 250,
      note: 'with salad',
    );
    final entry = JournalEntry(
      id: 'entry-1',
      createdAt: day,
      updatedAt: day,
      title: 'A day',
      body: '',
      meals: 'Snack: Apple; Dinner: Soup',
    );
    final source = Archive(
      entries: [entry],
      trackers: [tracker],
      trackerRecords: [record],
    );

    final migrated = migrateLegacyMeals(source);

    expect(migrated.meals, hasLength(3));
    expect(
      migrated.meals.map((meal) => meal.legacyRef).toList(),
      containsAll([
        'tracker:tracker-1',
        'entry:entry-1:0',
        'entry:entry-1:1',
      ]),
    );
    expect(
      migrated.meals.firstWhere(
        (meal) => meal.legacyRef == 'tracker:tracker-1',
      ),
      isA<MealRecord>()
          .having((meal) => meal.kind, 'kind', MealKind.meal)
          .having((meal) => meal.name, 'name', 'Pasta')
          .having((meal) => meal.amount, 'amount', 250)
          .having((meal) => meal.unit, 'unit', 'g')
          .having((meal) => meal.notes, 'notes', 'with salad'),
    );
    expect(
      migrated.meals
          .where((meal) => meal.legacyRef?.startsWith('entry:') ?? false)
          .map((meal) => meal.kind)
          .toList(),
      containsAll([MealKind.snack, MealKind.meal]),
    );

    // The old meal habit is archived, not deleted, and old fields stay intact.
    expect(migrated.trackers.single.archived, isTrue);
    expect(migrated.trackers.single.active, isFalse);
    expect(migrated.entries.single.meals, entry.meals);
    expect(migrated.trackerRecords, hasLength(1));
    expect(source.meals, isEmpty);

    // Running again must not duplicate anything.
    final again = migrateLegacyMeals(migrated);
    expect(again.meals, hasLength(3));
  });

  test('a meal-only day counts as a day with records', () {
    final day = DateTime(2026, 6, 1);
    final meal = MealRecord.create(
      at: DateTime(2026, 6, 1, 12, 30),
      kind: MealKind.meal,
      name: 'Soup',
    );
    final summary = DaySummary.of(Archive(meals: [meal]), day);

    expect(summary.meals, [meal]);
    expect(summary.totalRecords, 1);
    expect(summary.isEmpty, isFalse);
    expect(
      OnThisDayMemory(day: day, summary: summary).description,
      contains('1 meal'),
    );
  });

  test('same-name meals with distinct details are kept', () {
    final day = DateTime(2026, 6, 2);
    final tracker = TrackerDefinition(
      id: 'meals',
      name: 'What I ate today',
      type: TrackerType.text,
      createdAt: day,
      icon: 'meal',
      category: 'Nutrition',
    );
    final records = [
      TrackerRecord(
        id: 'r1',
        trackerId: tracker.id,
        recordedAt: day,
        startedAt: DateTime(2026, 6, 2, 12, 30),
        text: 'Lunch: Pasta',
        note: 'with salad',
        value: 250,
      ),
      TrackerRecord(
        id: 'r2',
        trackerId: tracker.id,
        recordedAt: day,
        startedAt: DateTime(2026, 6, 2, 13),
        text: 'Lunch: Pasta',
        note: 'no dressing',
        value: 300,
      ),
    ];

    final migrated = migrateLegacyMeals(
      Archive(trackers: [tracker], trackerRecords: records),
    );

    expect(migrated.meals, hasLength(2));
    expect(
      migrated.meals.map((m) => m.notes).toList(),
      containsAll(['with salad', 'no dressing']),
    );
    expect(
      migrateLegacyMeals(migrated).meals,
      hasLength(2),
      reason: 'migration must remain idempotent by legacyRef',
    );
  });

  test('food-adjacent but unrelated trackers are never migrated or archived', () {
    final day = DateTime(2026, 6, 2);
    final trackers = [
      TrackerDefinition(
        id: 't1',
        name: 'Eat more vegetables',
        type: TrackerType.boolean,
        createdAt: day,
        icon: 'heart',
        category: 'Wellness',
      ),
      TrackerDefinition(
        id: 't2',
        name: 'Ate out',
        type: TrackerType.count,
        createdAt: day,
        icon: 'star',
        category: 'Personal',
      ),
      TrackerDefinition(
        id: 't3',
        name: 'Meal prep',
        type: TrackerType.text,
        createdAt: day,
        icon: 'note',
        category: 'Personal',
      ),
    ];
    final records = [
      for (final tracker in trackers)
        TrackerRecord(
          id: 'record-${tracker.id}',
          trackerId: tracker.id,
          recordedAt: day,
          text: 'Lunch: Pasta',
        ),
    ];

    final migrated = migrateLegacyMeals(
      Archive(trackers: trackers, trackerRecords: records),
    );

    expect(migrated.meals, isEmpty);
    expect(migrated.trackers.every((t) => !t.archived), isTrue);
  });

  test('legacy meal notes do not invent a clock time', () {
    final at = DateTime(2026, 6, 3, 8);
    final entry = JournalEntry(
      id: 'entry-2',
      createdAt: at,
      updatedAt: at,
      title: 'A day',
      body: '',
      meals: 'Lunch: Soup',
    );
    final migrated = migrateLegacyMeals(Archive(entries: [entry]));
    final meal = migrated.meals.single;

    expect(meal.timeKnown, isFalse);
    expect(meal.timeLabel, 'time not recorded');
    expect(meal.toJson()['timeKnown'], isFalse);

    final decoded = MealRecord.fromJson(meal.toJson());
    expect(decoded.timeKnown, isFalse);
    expect(decoded.timeLabel, 'time not recorded');

    final oldJson = Map<String, dynamic>.from(meal.toJson())
      ..remove('timeKnown');
    expect(MealRecord.fromJson(oldJson).timeKnown, isTrue);
  });

  test('copyWith preserves an explicit day and unknown time unless time moves', () {
    final meal = MealRecord(
      id: 'm1',
      at: DateTime(2026, 6, 3, 12),
      day: '2026-06-02',
      kind: MealKind.meal,
      name: 'Soup',
      timeKnown: false,
    );

    final renamed = meal.copyWith(name: 'Soup with bread');
    expect(renamed.dayKey, '2026-06-02');
    expect(renamed.timeKnown, isFalse);

    final moved = meal.copyWith(at: DateTime(2026, 6, 4, 12));
    expect(moved.dayKey, '2026-06-04');
    expect(moved.timeKnown, isTrue);
  });
}
