import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/meals.dart';
import 'meal_dialogs.dart';

IconData mealIcon(MealKind kind) => switch (kind) {
      MealKind.meal => Icons.restaurant_rounded,
      MealKind.drink => Icons.local_drink_outlined,
      MealKind.snack => Icons.cookie_outlined,
    };

Color mealAccent(MealKind kind, ColorScheme scheme, LifelogPalette palette) =>
    switch (kind) {
      MealKind.meal => palette.tracker,
      MealKind.drink => palette.place,
      MealKind.snack => palette.warning,
    };

/// Compact, read-first card used on Today and in the finished day layout.
class MealsDayCard extends ConsumerWidget {
  const MealsDayCard({
    super.key,
    required this.day,
    this.maxItems,
  });

  final DateTime day;
  final int? maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(archiveProvider).mealsOn(day);
    final palette = context.palette;
    final text = context.text;
    final shown = maxItems == null ? meals : meals.take(maxItems!).toList();

    return QuietCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_outlined,
                  size: 18, color: palette.tracker),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text('Meals and drinks', style: text.titleSmall),
              ),
              if (meals.isNotEmpty)
                Text(
                  '${meals.length} ${plural(meals.length, 'item')}',
                  style: text.labelSmall?.copyWith(color: palette.mutedText),
                ),
              const SizedBox(width: Insets.xs),
              HeaderButton(
                icon: Icons.add_rounded,
                tooltip: 'Add meal, drink or snack',
                onPressed: () => showMealEditor(context, ref, day),
                color: palette.mutedText,
              ),
            ],
          ),
          if (meals.isEmpty) ...[
            const SizedBox(height: Insets.sm),
            Text(
              'Log what you ate or drank. Meals are their own thing, not a habit.',
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
          ] else ...[
            const SizedBox(height: Insets.xs),
            for (final meal in shown)
              _MealTile(
                meal: meal,
                onTap: () => showMealEditor(
                  context,
                  ref,
                  day,
                  existing: meal,
                ),
              ),
            if (shown.length < meals.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => showMealsForDay(context, ref, day),
                  child: Text('See all ${meals.length} items'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MealTile extends StatelessWidget {
  const _MealTile({required this.meal, required this.onTap});

  final MealRecord meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final accent = mealAccent(meal.kind, context.scheme, palette);
    final detail = [
      meal.amountLabel,
      if (meal.notes.trim().isNotEmpty) meal.notes.trim(),
      if (meal.tags.isNotEmpty) meal.tags.map((t) => '#$t').join(' '),
    ].where((value) => value.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                meal.timeLabel,
                style: text.labelMedium?.copyWith(
                  color: palette.mutedText,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(left: Insets.sm),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Insets.xs),
            SourceChip(
              label: meal.kind.label,
              color: accent,
              dense: true,
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: palette.dimText),
          ],
        ),
      ),
    );
  }
}
