import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';

/// Heading for one day's group of entries in the Journal list.
///
/// A serif day name with the full date and entry count beneath, and one quiet
/// action to add to that day. It replaces the folder-icon row: the grouping is
/// carried by typography and spacing rather than by an icon.
class JournalDayHeader extends StatelessWidget {
  const JournalDayHeader({
    super.key,
    required this.day,
    required this.count,
    required this.onAdd,
  });

  final DateTime day;
  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    relativeDayLabel(day),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatDayHeader(day)} · $count ${plural(count, 'entry')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ],
              ),
            ),
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
