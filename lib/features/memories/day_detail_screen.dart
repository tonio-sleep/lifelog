import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/memories.dart';
import '../../domain/models/timeline.dart';
import '../../domain/models/trackers.dart';
import '../journal/journal_widgets.dart';
import '../music/music_screen.dart';
import '../photos/photo_widgets.dart';
import '../timeline/event_dialogs.dart';
import '../timeline/timeline_widgets.dart';
import '../today/today_widgets.dart';
import '../trackers/tracker_dialogs.dart';
import '../trackers/tracker_widgets.dart';

/// A single day read as a story: what you wrote, with its photos beneath it,
/// then the habits, places and music that surrounded it.
class DayDetailScreen extends ConsumerStatefulWidget {
  const DayDetailScreen({super.key, required this.day});
  final DateTime day;

  @override
  ConsumerState<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends ConsumerState<DayDetailScreen> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    _day = dayStart(widget.day);
  }

  void _shift(int delta) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: relativeDayLabel(_day),
      subtitle: formatDayLong(_day),
      actions: [
        HeaderButton(
          icon: Icons.bolt_rounded,
          tooltip: 'Add event',
          onPressed: () =>
              showTimelineEventEditor(context, ref, initialDate: _day),
        ),
        HeaderButton(
          icon: Icons.edit_rounded,
          tooltip: 'Write about this day',
          filled: true,
          onPressed: () => createJournalEntry(context, date: _day, focusBody: true),
        ),
      ],
      children: [
        DayNavigator(
          day: _day,
          onChanged: (value) => setState(() => _day = value),
        ),
        const SizedBox(height: Insets.lg),
        DaySwitcher(
          day: _day,
          onSwipe: _shift,
          builder: (context, day) => _DayStory(day: day),
        ),
      ],
    );
  }
}

class _DayStory extends ConsumerWidget {
  const _DayStory({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final summary = DaySummary.of(archive, day);
    final palette = context.palette;
    final text = context.text;
    final mood = dominantMood(archive, day);
    final entries = archive.entriesOn(day, includeDrafts: true);
    final looseMedia = summary.photos
        .where((m) => m.journalEntryId == null)
        .toList();
    final trackers = archive.activeTrackers
        .where((t) => TrackerMath.loggedOn(archive.trackerRecords, t.id, day))
        .toList();
    final memories = onThisDay(archive, day);

    if (summary.isEmpty) {
      return EmptyState(
        icon: Icons.nights_stay_outlined,
        title: 'Nothing recorded',
        message: 'This day is quiet. You can still write about it.',
        actionLabel: 'Write about this day',
        onAction: () => createJournalEntry(context, date: day, focusBody: true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mood != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md, left: Insets.xs),
            child: Row(
              children: [
                Text(
                  'Mostly',
                  style: text.labelMedium?.copyWith(color: palette.mutedText),
                ),
                const SizedBox(width: Insets.sm),
                MoodBadge(mood),
              ],
            ),
          ),
        for (final entry in entries)
          JournalEntryCard(
            key: ValueKey(entry.id),
            entry: entry,
            showDate: false,
            heroScope: 'day',
          ),
        if (looseMedia.isNotEmpty) ...[
          const SectionHeader(
            title: 'Moments',
            padding: EdgeInsets.only(top: Insets.md, bottom: Insets.sm),
          ),
          StoryStrip(items: looseMedia, scope: 'day-moments', height: 150),
        ],
        if (trackers.isNotEmpty) ...[
          const SectionHeader(title: 'Habits'),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final tracker in trackers)
                Pressable(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  onTap: () => showTrackerLogDialog(context, ref, tracker, day: day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.md,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: trackerColor(tracker.colorValue).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          trackerIcon(tracker.icon),
                          size: 15,
                          color: trackerColor(tracker.colorValue),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          [
                            tracker.name,
                            habitValueLabel(tracker, archive.trackerRecords, day),
                          ].whereType<String>().join(', '),
                          style: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (summary.visits.isNotEmpty || summary.events.isNotEmpty) ...[
          const SectionHeader(title: 'Places and events'),
          TimelineDayList(
            day: day,
            compact: true,
            showEmptyAction: false,
            sources: const {TimelineSource.location, TimelineSource.manual},
          ),
        ],
        if (summary.scrobbles.isNotEmpty) ...[
          const SectionHeader(title: 'Music'),
          DayListeningCard(
            summary: summary.music,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => MusicScreen(day: day)),
            ),
          ),
        ],
        if (memories.isNotEmpty) ...[
          const SectionHeader(title: 'In other years'),
          for (final memory in memories.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: QuietCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DayDetailScreen(day: memory.day),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(memory.relativeLabel, style: text.titleSmall),
                          Text(
                            memory.description,
                            style: text.bodySmall?.copyWith(color: palette.mutedText),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: palette.dimText),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
