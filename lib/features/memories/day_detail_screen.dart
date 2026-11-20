import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/memories.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/timeline.dart';
import '../../domain/models/trackers.dart';
import '../journal/journal_widgets.dart';
import '../meals/meal_dialogs.dart';
import '../meals/meal_widgets.dart';
import '../music/music_screen.dart';
import '../photos/photo_widgets.dart';
import '../timeline/event_dialogs.dart';
import '../timeline/timeline_widgets.dart';
import '../today/quick_add.dart';
import '../today/today_widgets.dart';
import '../trackers/tracker_dialogs.dart';
import '../trackers/tracker_widgets.dart';

/// One day, read as a finished page: how it felt, what was written, what was
/// captured, and the habits around it. Every section stays editable.
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
          icon: Icons.mood_outlined,
          tooltip: 'Add check-in',
          onPressed: () => showDailyCheckinSheet(context, ref, _day),
        ),
        HeaderButton(
          icon: Icons.restaurant_outlined,
          tooltip: 'Log meal or drink',
          onPressed: () => showMealEditor(context, ref, _day),
        ),
        HeaderButton(
          icon: Icons.bolt_rounded,
          tooltip: 'Add event',
          onPressed: () =>
              showTimelineEventEditor(context, ref, initialDate: _day),
        ),
        HeaderButton(
          icon: Icons.note_add_outlined,
          tooltip: 'Add entry for this day',
          filled: true,
          onPressed: () => createJournalEntry(
            context,
            date: _day,
            focusBody: true,
            createNew: true,
          ),
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

bool _isMetricsOnly(JournalEntry entry) {
  if (entry.title.trim().isNotEmpty ||
      entry.body.trim().isNotEmpty ||
      entry.hasVocabContent ||
      entry.highlight.trim().isNotEmpty ||
      entry.mood != null ||
      entry.energy != null) {
    return false;
  }
  return entry.sleepHours != null ||
      entry.steps != null ||
      entry.meals.trim().isNotEmpty;
}

class _DayStory extends ConsumerWidget {
  const _DayStory({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final summary = DaySummary.of(archive, day);
    final palette = context.palette;
    final entries = archive.entriesOn(day, includeDrafts: true);
    final checkins = archive.checkinsOn(day);
    final writing = entries
        .where((e) => !e.isCheckinEntry && !_isMetricsOnly(e))
        .toList();
    final metrics = archive.dayMetricsEntryFor(day);
    final mood = checkins.isEmpty ? dominantMood(archive, day) : checkins.last.mood;
    final trackers = archive.activeTrackers
        .where((t) => TrackerMath.loggedOn(archive.trackerRecords, t.id, day))
        .toList();
    final memories = onThisDay(archive, day);

    if (summary.isEmpty && entries.isEmpty) {
      return EmptyState(
        icon: Icons.nights_stay_outlined,
        title: 'Nothing recorded',
        message:
            'This day is quiet. Add a check-in, an entry, or a photo to start its page.',
        actionLabel: 'Add entry',
        onAction: () => createJournalEntry(
          context,
          date: day,
          focusBody: true,
          createNew: true,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayFeelingCard(
          day: day,
          checkins: checkins,
          mood: mood,
          metrics: metrics,
        ),
        if (writing.isNotEmpty) ...[
          const SectionHeader(title: 'Entries'),
          for (final entry in writing)
            JournalEntryCard(
              key: ValueKey(entry.id),
              entry: entry,
              showDate: false,
              heroScope: 'day',
            ),
        ],
        if (summary.photos.isNotEmpty) ...[
          const SectionHeader(title: 'Photos and videos'),
          StoryStrip(items: summary.photos, scope: 'day-all', height: 150),
        ],
        if (archive.mealsOn(day).isNotEmpty) ...[
          const SectionHeader(title: 'Meals'),
          MealsDayCard(day: day),
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
                  onTap: () =>
                      showTrackerLogDialog(context, ref, tracker, day: day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Insets.md,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: trackerColor(tracker.colorValue)
                          .withValues(alpha: 0.13),
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
                            habitValueLabel(
                              tracker,
                              archive.trackerRecords,
                              day,
                            ),
                          ].whereType<String>().join(', '),
                          style: context.text.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (metrics != null &&
            (metrics.sleepHours != null || metrics.steps != null)) ...[
          const SectionHeader(title: 'Health'),
          QuietCard(
            child: Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.xs,
              children: [
                if (metrics.sleepHours != null)
                  SourceChip(
                    label: '${_fmtNum(metrics.sleepHours!)}h sleep',
                    color: palette.place,
                    dense: true,
                  ),
                if (metrics.steps != null)
                  SourceChip(
                    label: '${metrics.steps} steps',
                    color: palette.music,
                    dense: true,
                  ),
              ],
            ),
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
                          Text(memory.relativeLabel, style: context.text.titleSmall),
                          Text(
                            memory.description,
                            style: context.text.bodySmall?.copyWith(
                              color: palette.mutedText,
                            ),
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

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
}

class _DayFeelingCard extends ConsumerWidget {
  const _DayFeelingCard({
    required this.day,
    required this.checkins,
    required this.mood,
    required this.metrics,
  });

  final DateTime day;
  final List<JournalEntry> checkins;
  final int? mood;
  final JournalEntry? metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    final accent =
        mood == null ? palette.mutedText : moodColor(mood!, context.scheme);
    final latest = checkins.isEmpty ? null : checkins.last;
    final highlight = latest?.highlight.trim() ?? '';
    final health = metrics;

    return QuietCard(
      color: mood == null ? null : accent.withValues(alpha: 0.10),
      border: mood != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.mood_outlined, size: 18, color: accent),
              const SizedBox(width: Insets.sm),
              Expanded(child: Text('How I felt today', style: text.titleSmall)),
              TextButton.icon(
                onPressed: () => showDailyCheckinSheet(
                  context,
                  ref,
                  day,
                  existing: latest,
                ),
                icon: Icon(
                  latest == null ? Icons.add_rounded : Icons.edit_outlined,
                  size: 16,
                ),
                label: Text(latest == null ? 'Check in' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 58,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mood == null ? 'No mood recorded' : MoodScore.label(mood!),
                      style: AppTheme.serif(text.headlineMedium, size: 25)
                          .copyWith(
                            color: mood == null ? palette.mutedText : accent,
                          ),
                    ),
                    if (highlight.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        highlight,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(text.bodyMedium, size: 15)
                            .copyWith(color: palette.mutedText, height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (mood != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$mood',
                      style: text.titleLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      '/ 10',
                      style: text.labelSmall?.copyWith(color: palette.mutedText),
                    ),
                  ],
                ),
            ],
          ),
          if (checkins.length > 1) ...[
            const SizedBox(height: Insets.md),
            Divider(height: 1, color: palette.border),
            const SizedBox(height: Insets.xs),
            for (final entry in checkins) ...[
              _DayCheckinTile(
                entry: entry,
                onTap: () => showDailyCheckinSheet(
                  context,
                  ref,
                  day,
                  existing: entry,
                ),
              ),
              if (entry != checkins.last)
                Divider(height: 1, color: palette.border),
            ],
          ],
          if (health != null &&
              (health.sleepHours != null || health.steps != null)) ...[
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.xs,
              children: [
                if (health.sleepHours != null)
                  SourceChip(
                    label: '${_fmtNum(health.sleepHours!)}h sleep',
                    color: palette.place,
                    dense: true,
                  ),
                if (health.steps != null)
                  SourceChip(
                    label: '${health.steps} steps',
                    color: palette.music,
                    dense: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCheckinTile extends StatelessWidget {
  const _DayCheckinTile({required this.entry, required this.onTap});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final mood = entry.mood;
    final accent =
        mood == null ? palette.mutedText : moodColor(mood, context.scheme);
    final highlight = entry.highlight.trim();

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
                formatTime(entry.createdAt),
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
                    mood == null ? 'Check-in' : MoodScore.label(mood),
                    style: text.bodyMedium,
                  ),
                  if (highlight.isNotEmpty)
                    Text(
                      highlight,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                ],
              ),
            ),
            if (entry.energy != null)
              SourceChip(
                label: '${entry.energy}/5',
                color: palette.tracker,
                dense: true,
              ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.dimText),
          ],
        ),
      ),
    );
  }
}
