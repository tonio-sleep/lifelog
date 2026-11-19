import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../domain/models/journal.dart';

/// The one primary card on Today: write, with the daily check-in beside it.
///
/// Replaces two near-identical cards (check-in, journal) so the page has a
/// single obvious first action. Check-in values are plain text, not a row of
/// differently coloured chips.
class TodayComposer extends StatelessWidget {
  const TodayComposer({
    super.key,
    required this.isToday,
    required this.entry,
    required this.entryCount,
    required this.onWrite,
    required this.onNewEntry,
    required this.onCheckin,
  });

  final bool isToday;
  final JournalEntry? entry;
  final int entryCount;
  final VoidCallback onWrite;
  final VoidCallback onNewEntry;
  final VoidCallback onCheckin;

  static String _num(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  /// "Good · 7.5h sleep · 8,204 steps", or null when nothing is logged.
  String? _checkinSummary() {
    final e = entry;
    if (e == null) return null;
    final parts = <String>[
      if (e.mood != null) e.mood!.label,
      if (e.energy != null) 'Energy ${e.energy}/5',
      if (e.sleepHours != null) '${_num(e.sleepHours!)}h sleep',
      if (e.steps != null) '${e.steps} steps',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    final e = entry;
    final hasWriting =
        e != null &&
        (e.title.trim().isNotEmpty ||
            e.body.trim().isNotEmpty ||
            e.hasVocabContent);
    final multiple = entryCount > 1;

    final prompt = hasWriting
        ? (e.excerpt == 'No text' ? e.displayTitle : e.excerpt)
        : (isToday ? 'What is on your mind?' : 'Write about this day');
    final meta = multiple
        ? '$entryCount entries ${isToday ? 'today' : 'on this day'}'
        : hasWriting
        ? 'Tap to keep writing'
        : 'Thoughts, notes or a vocab list';
    final summary = _checkinSummary();

    return QuietCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            onTap: onWrite,
            scale: 0.995,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.lg,
                Insets.lg,
                Insets.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prompt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      text.titleLarge,
                      size: 21,
                      weight: FontWeight.w500,
                    ).copyWith(
                      height: 1.3,
                      color: hasWriting ? null : palette.mutedText,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    meta,
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ],
              ),
            ),
          ),
          Divider(color: palette.border),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _FooterAction(
                    label: 'Check-in',
                    detail: summary ?? (isToday ? 'Mood, sleep, steps' : 'Add this day'),
                    onTap: onCheckin,
                  ),
                ),
                VerticalDivider(width: 1, color: palette.border),
                Expanded(
                  child: _FooterAction(
                    label: 'New entry',
                    detail: 'Journal, note or vocab',
                    onTap: onNewEntry,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.labelLarge?.copyWith(color: context.scheme.primary),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: context.palette.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
