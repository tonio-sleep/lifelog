import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';

/// A month grid: selected day filled, today ringed, activity as a small dot.
class MonthCalendar extends ConsumerWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.onSelect,
    required this.onMonthChanged,
  });

  final DateTime month;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final weekStartsMonday = ref.watch(
      settingsProvider.select((s) => s.weekStartsMonday),
    );
    final palette = context.palette;
    final text = context.text;
    final scheme = context.scheme;

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = weekStartsMonday ? first.weekday - 1 : first.weekday % 7;
    final labels = weekStartsMonday
        ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
        : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    final active = archive.activityDaysIn(month);
    final today = dayStart(DateTime.now());
    final isCurrentMonth = month.year == today.year && month.month == today.month;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: Insets.xs),
                child: AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Align(
                    key: ValueKey<int>(month.year * 100 + month.month),
                    alignment: Alignment.centerLeft,
                    child: Text(formatMonthYear(month), style: text.titleMedium),
                  ),
                ),
              ),
            ),
            if (!isCurrentMonth)
              TextButton(
                onPressed: () => onMonthChanged(DateTime(today.year, today.month)),
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                child: const Text('This month'),
              ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Row(
          children: [
            for (final label in labels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: text.labelSmall?.copyWith(color: palette.dimText),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        for (var row = 0; row < rows; row++)
          SizedBox(
            height: 46,
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _cell(
                      context,
                      row * 7 + col - leading + 1,
                      daysInMonth,
                      active,
                      today,
                      scheme,
                      palette,
                      text,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    int dayNumber,
    int daysInMonth,
    Set<int> active,
    DateTime today,
    ColorScheme scheme,
    LifelogPalette palette,
    TextTheme text,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox.shrink();
    final date = DateTime(month.year, month.month, dayNumber);
    final selected = sameDay(date, selectedDay);
    final isToday = sameDay(date, today);
    final hasActivity = active.contains(dayNumber);
    return Pressable(
      scale: 0.9,
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: () => onSelect(date),
      child: Center(
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.out,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? scheme.primary : Colors.transparent,
            border: isToday && !selected
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayNumber',
                style: text.bodyMedium?.copyWith(
                  fontFeatures: tabularFigures,
                  fontWeight: selected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
              AnimatedContainer(
                duration: Motion.base,
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasActivity
                      ? (selected ? scheme.onPrimary : scheme.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
