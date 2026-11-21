import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/day_provider.dart';
import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/memories.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/music.dart';
import '../../domain/models/timeline.dart';
import '../journal/day_overview.dart';
import '../journal/journal_widgets.dart';
import '../memories/calendar.dart';
import '../memories/day_detail_screen.dart';
import '../meals/meal_widgets.dart';
import '../music/music_sync.dart';
import '../photos/photo_widgets.dart';
import '../timeline/timeline_widgets.dart';
import '../trackers/tracker_widgets.dart';
import 'quick_add.dart';
import 'today_composer.dart';
import 'today_widgets.dart';

/// Navigation callback that can carry the day the person is viewing.
typedef TodayNavigate = void Function(String destination, {DateTime? day});

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, this.onNavigate});

  final TodayNavigate? onNavigate;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  bool _showMonth = false;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final day = ref.read(selectedDayProvider);
    _month = DateTime(day.year, day.month);
  }

  void _select(DateTime day) {
    ref.read(selectedDayProvider.notifier).select(day);
    if (day.year != _month.year || day.month != _month.month) {
      setState(() => _month = DateTime(day.year, day.month));
    }
  }

  Future<void> _refresh() async {
    final result = await syncLastfmRecent(ref, days: 2);
    if (mounted) showSnack(context, result.message);
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(selectedDayProvider);
    final archive = ref.watch(archiveProvider);
    final settings = ref.watch(settingsProvider);

    final activeCache = <int, Set<int>>{};
    bool hasActivity(DateTime d) => activeCache
        .putIfAbsent(d.year * 100 + d.month, () => archive.activityDaysIn(d))
        .contains(d.day);

    return ScreenFrame(
      onRefresh: settings.lastfmConnected ? _refresh : null,
      header: TodayHeader(
        day: day,
        calendarOpen: _showMonth,
        onToggleCalendar: () => setState(() => _showMonth = !_showMonth),
        onSearch: () => widget.onNavigate?.call('search'),
        onAdd: () => showQuickAdd(context, ref),
        onToday: () => _select(dayStart(DateTime.now())),
      ),
      children: [
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Motion.base,
            child: _showMonth
                ? QuietCard(
                    key: const ValueKey('month'),
                    padding: const EdgeInsets.fromLTRB(
                      Insets.md,
                      Insets.sm,
                      Insets.md,
                      Insets.md,
                    ),
                    child: MonthCalendar(
                      month: _month,
                      selectedDay: day,
                      onSelect: _select,
                      onMonthChanged: (m) => setState(() => _month = m),
                    ),
                  )
                : WeekStrip(
                    key: const ValueKey('week'),
                    selected: day,
                    onSelect: _select,
                    hasActivity: hasActivity,
                    weekStartsMonday: settings.weekStartsMonday,
                  ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        DaySwitcher(
          day: day,
          onSwipe: (delta) => ref.read(selectedDayProvider.notifier).shift(delta),
          builder: (context, shownDay) => _DayBody(
            day: shownDay,
            onNavigate: widget.onNavigate,
          ),
        ),
      ],
    );
  }
}

class _DayBody extends ConsumerWidget {
  const _DayBody({required this.day, this.onNavigate});

  final DateTime day;
  final TodayNavigate? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final summary = DaySummary.of(archive, day);
    final isToday = sameDay(day, DateTime.now());

    MusicScrobble? latest;
    if (isToday && archive.scrobbles.isNotEmpty) {
      latest = archive.scrobbles.reduce(
        (a, b) => a.playedAt.isAfter(b.playedAt) ? a : b,
      );
    }
    final listening = summary.scrobbles.isEmpty ? null : summary.music;

    final writingEntry = archive.primaryWritingEntryFor(day);
    final dayEntries = archive.entriesOn(day, includeDrafts: true);
    final checkins = archive.checkinsOn(day);
    final latestCheckin = checkins.isEmpty ? null : checkins.last;
    final metrics = archive.dayMetricsEntryFor(day);
    final entryCount = dayEntries.length;

    String? checkinSummary;
    if (latestCheckin != null) {
      final parts = <String>[
        if (latestCheckin.mood != null) MoodScore.label(latestCheckin.mood!),
        if (latestCheckin.energy != null) 'Energy ${latestCheckin.energy}/5',
        if (latestCheckin.highlight.trim().isNotEmpty)
          latestCheckin.highlight.trim(),
      ];
      checkinSummary = parts.isEmpty ? null : parts.join(' · ');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TodayComposer(
          isToday: isToday,
          entry: writingEntry,
          entryCount: entryCount,
          checkinCount: checkins.length,
          checkinSummary: checkinSummary,
          onCheckin: () => showDailyCheckinSheet(context, ref, day),
          onWrite: () {
            if (entryCount > 1) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DayDetailScreen(day: day),
                ),
              );
            } else {
              createJournalEntry(context, date: day, focusBody: true);
            }
          },
          onNewEntry: () => createJournalEntry(
            context,
            date: day,
            focusBody: true,
            createNew: true,
          ),
        ),
        const SizedBox(height: Insets.md),
        DayStatStrip(stats: DayStats.of(archive, day)),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DayDetailScreen(day: day),
                  ),
                ),
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                label: Text(isToday ? 'Today’s summary' : 'Day summary'),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => onNavigate?.call('places', day: day),
                icon: const Icon(Icons.place_outlined, size: 18),
                label: const Text('Map'),
              ),
            ),
          ],
        ),
        // The composer already summarises the latest check-in; the detailed
        // list only appears when there is more than one to look through.
        if (checkins.length > 1) ...[
          const SizedBox(height: Insets.md),
          _DayCheckinsCard(day: day, checkins: checkins, metrics: metrics),
        ],
        const SizedBox(height: Insets.md),
        TodayHabits(day: day, onSeeAll: () => onNavigate?.call('trackers')),
        const SizedBox(height: Insets.md),
        MealsDayCard(day: day, maxItems: 3),
        if (latest != null) ...[
          const SizedBox(height: Insets.md),
          NowPlayingCard(scrobble: latest, onTap: () => onNavigate?.call('music')),
        ] else if (listening != null) ...[
          const SizedBox(height: Insets.md),
          DayListeningCard(summary: listening, onTap: () => onNavigate?.call('music')),
        ],
        if (summary.photos.isNotEmpty) ...[
          SectionHeader(
            title: 'Moments',
            actionLabel: 'Media',
            onAction: () => onNavigate?.call('photos'),
          ),
          StoryStrip(items: summary.photos, scope: 'today', height: 104),
        ],
        SectionHeader(
          title: isToday ? 'Today so far' : 'That day',
          actionLabel: 'Timeline',
          onAction: () => onNavigate?.call('timeline', day: day),
        ),
        TimelineDayList(
          day: day,
          compact: true,
          maxItems: 4,
          showEmptyAction: false,
          sources: const {
            TimelineSource.journal,
            TimelineSource.tracker,
            TimelineSource.location,
            TimelineSource.manual,
            TimelineSource.photo,
            TimelineSource.meal,
          },
          emptyMessage: isToday
              ? 'Nothing here yet. A small check-in, a habit, a photo, or a few words is a great way to start.'
              : 'Nothing was recorded on this day.',
        ),
      ],
    );
  }
}

class _DayCheckinsCard extends ConsumerWidget {
  const _DayCheckinsCard({
    required this.day,
    required this.checkins,
    required this.metrics,
  });

  final DateTime day;
  final List<JournalEntry> checkins;
  final JournalEntry? metrics;

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    final hasMetrics = metrics != null &&
        (metrics!.sleepHours != null || metrics!.steps != null);
    return QuietCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Check-ins', style: text.titleSmall)),
              if (checkins.isNotEmpty)
                Text(
                  '${checkins.length}',
                  style: text.labelMedium?.copyWith(color: palette.mutedText),
                ),
            ],
          ),
          if (hasMetrics) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.xs,
              children: [
                if (metrics!.sleepHours != null)
                  SourceChip(
                    label: 'Sleep ${_fmtNum(metrics!.sleepHours!)}h (Health)',
                    color: palette.place,
                    dense: true,
                  ),
                if (metrics!.steps != null)
                  SourceChip(
                    label: '${metrics!.steps} steps (Health)',
                    color: palette.music,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sleep and steps are synced from Health, separate from check-ins.',
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
          ],
          if (checkins.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            for (final entry in checkins) ...[
              _CheckinRow(
                day: day,
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
          ] else ...[
            const SizedBox(height: Insets.xs),
            Text(
              'No check-ins yet. A quick check-in can help you notice how your day is going.',
              style: text.bodySmall?.copyWith(color: palette.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckinRow extends StatelessWidget {
  const _CheckinRow({
    required this.day,
    required this.entry,
    required this.onTap,
  });
  final DateTime day;
  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final parts = <String>[
      if (entry.mood != null) MoodScore.label(entry.mood!),
      if (entry.energy != null) 'Energy ${entry.energy}/5',
    ];
    final summary = parts.join(' · ');
    final highlight = entry.highlight.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                formatTime(entry.createdAt),
                style: text.labelMedium?.copyWith(
                  color: palette.mutedText,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (summary.isNotEmpty)
                    Text(summary, style: text.bodyMedium),
                  if (highlight.isNotEmpty)
                    Text(
                      highlight,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: summary.isEmpty ? null : palette.mutedText,
                      ),
                    ),
                  if (summary.isEmpty && highlight.isEmpty)
                    Text(
                      'Check-in',
                      style: text.bodyMedium?.copyWith(color: palette.mutedText),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.dimText),
          ],
        ),
      ),
    );
  }
}
