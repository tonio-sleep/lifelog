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
import '../../domain/models/music.dart';
import '../../domain/models/timeline.dart';
import '../journal/journal_widgets.dart';
import '../memories/calendar.dart';
import '../memories/day_detail_screen.dart';
import '../music/music_sync.dart';
import '../photos/photo_widgets.dart';
import '../timeline/timeline_widgets.dart';
import '../trackers/tracker_widgets.dart';
import 'quick_add.dart';
import 'today_composer.dart';
import 'today_widgets.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, this.onNavigate});

  final ValueChanged<String>? onNavigate;

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
    final isToday = sameDay(day, DateTime.now());
    final desktop = MediaQuery.sizeOf(context).width >= 900;

    final activeCache = <int, Set<int>>{};
    bool hasActivity(DateTime d) => activeCache
        .putIfAbsent(d.year * 100 + d.month, () => archive.activityDaysIn(d))
        .contains(d.day);

    return ScreenFrame(
      background: TodayGlow(isToday: isToday),
      onRefresh: settings.lastfmConnected ? _refresh : null,
      header: TodayHeader(
        day: day,
        streak: currentStreak(archive, DateTime.now()),
        calendarOpen: _showMonth,
        onToggleCalendar: () => setState(() => _showMonth = !_showMonth),
        onSearch: () => widget.onNavigate?.call('search'),
        onAccount: () => widget.onNavigate?.call('settings'),
        onAdd: desktop ? () => showQuickAdd(context, ref) : null,
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
  final ValueChanged<String>? onNavigate;

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

    final dailyEntry = archive.dailyEntryFor(day);
    final dayEntries = archive.entriesOn(day, includeDrafts: true);
    final journalEntries = dayEntries
        .where((e) => e.body.trim().isNotEmpty || e.title.trim().isNotEmpty || e.hasVocabContent)
        .toList();
    final entryCount = dayEntries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TodayComposer(
          isToday: isToday,
          entry: dailyEntry,
          entryCount: entryCount,
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
        if (latest != null) ...[
          const SizedBox(height: Insets.md),
          NowPlayingCard(scrobble: latest, onTap: () => onNavigate?.call('music')),
        ] else if (listening != null) ...[
          const SizedBox(height: Insets.md),
          DayListeningCard(summary: listening, onTap: () => onNavigate?.call('music')),
        ],
        const SizedBox(height: Insets.md),
        TodayHabits(day: day, onSeeAll: () => onNavigate?.call('trackers')),
        if (summary.photos.isNotEmpty) ...[
          SectionHeader(
            title: 'Moments',
            actionLabel: 'Media',
            onAction: () => onNavigate?.call('photos'),
          ),
          StoryStrip(items: summary.photos, scope: 'today', height: 132),
        ],
        SectionHeader(
          title: isToday ? 'Today so far' : 'That day',
          actionLabel: 'Timeline',
          onAction: () => onNavigate?.call('timeline'),
        ),
        TimelineDayList(
          day: day,
          compact: true,
          maxItems: 6,
          showEmptyAction: false,
          sources: const {
            TimelineSource.journal,
            TimelineSource.tracker,
            TimelineSource.location,
            TimelineSource.manual,
          },
          emptyMessage: isToday
              ? 'Nothing yet. Add a check-in, log an activity, write, or add a photo.'
              : 'Nothing was recorded on this day.',
        ),
      ],
    );
  }
}
