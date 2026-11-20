import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';

/// Heading for one day's group of entries in the Journal list.
///
/// The day itself is the button: tapping it opens the finished day layout with
/// every entry, photo and habit for that date. The small add button is kept
/// separate for writing straight into the day.
class JournalDayHeader extends StatelessWidget {
  const JournalDayHeader({
    super.key,
    required this.day,
    required this.count,
    required this.onOpen,
    required this.onAdd,
    this.mood,
  });

  final DateTime day;
  final int count;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final int? mood;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    final moodColorValue =
        mood == null ? null : moodColor(mood!, context.scheme);

    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.xs),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(Radii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (moodColorValue != null) ...[
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: moodColorValue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: Insets.sm),
                                ],
                                Flexible(
                                  child: Text(
                                    relativeDayLabel(day),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.headlineSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatDayHeader(day)} · $count ${plural(count, 'entry')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  text.bodySmall?.copyWith(color: palette.mutedText),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: palette.dimText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: Insets.xs),
            HeaderButton(
              icon: Icons.add_rounded,
              tooltip: 'Add entry to this day',
              onPressed: onAdd,
              color: palette.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}
