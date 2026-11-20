import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/meals_migration.dart';
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
}
