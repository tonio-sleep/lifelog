import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/settings.dart';
import '../../domain/models/trackers.dart';
import '../../domain/tracker_stats.dart';
import '../trackers/tracker_dialogs.dart';
import 'charts.dart';

enum _Range {
  week,
  month,
  quarter,
  year,
  all,
  custom;

  String get label => switch (this) {
    _Range.week => '7 days',
    _Range.month => '30 days',
    _Range.quarter => '90 days',
    _Range.year => '1 year',
    _Range.all => 'All time',
    _Range.custom => 'Custom',
  };
}

const _weekdayLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  _Range _range = _Range.month;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _autoRangeChecked = false;

  DateTime get _end {
    if (_range == _Range.custom && _customEnd != null) {
      return dayStart(_customEnd!);
    }
    return dayStart(DateTime.now());
  }

  DateTime get _start {
    if (_range == _Range.custom && _customStart != null) {
      return dayStart(_customStart!);
    }
    if (_range == _Range.all) {
      return _earliestRecord(ref.read(archiveProvider)) ??
          _end.subtract(const Duration(days: 29));
    }
    final days = switch (_range) {
      _Range.week => 7,
      _Range.month => 30,
      _Range.quarter => 90,
      _Range.year => 365,
      _Range.all => 30,
      _Range.custom => 30,
    };
    return _end.subtract(Duration(days: days - 1));
  }

  static DateTime? _earliestRecord(Archive archive) {
    final times = <DateTime>[
      for (final entry in archive.entries) entry.createdAt,
      for (final item in archive.media) item.createdAt,
      for (final visit in archive.visits) visit.startAt,
      for (final scrobble in archive.scrobbles) scrobble.playedAt,
      for (final event in archive.events) event.occurredAt,
      for (final record in archive.trackerRecords) record.recordedAt,
    ];
    if (times.isEmpty) return null;
    var earliest = times.first;
    for (final time in times) {
      if (time.isBefore(earliest)) earliest = time;
    }
    final start = dayStart(earliest);
    return start.isAfter(dayStart(DateTime.now()))
        ? dayStart(DateTime.now())
        : start;
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final settings = ref.watch(settingsProvider);
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hidden = settings.hiddenInsightCategories.toSet();

    final start = _start;
    final end = _end;
    final days = math.max(1, end.difference(start).inDays + 1);
    final rangeEndExclusive = dayEnd(end);

    bool inRange(DateTime at) =>
        !at.isBefore(start) && at.isBefore(rangeEndExclusive);

    final entries = archive.entries
        .where((entry) => inRange(entry.createdAt) && !entry.archived)
        .toList();
    final published = entries.where((entry) => !entry.draft).toList();
    final drafts = entries.where((entry) => entry.draft).length;
    final media = archive.media
        .where((item) => inRange(item.createdAt))
        .toList();
    final visits = archive.visits
        .where((visit) => inRange(visit.startAt))
        .toList();
    final scrobbles = archive.scrobbles
        .where((scrobble) => inRange(scrobble.playedAt))
        .toList();
    final events = archive.events
        .where((event) => inRange(event.occurredAt))
        .toList();
    final hasAnyData =
        entries.isNotEmpty ||
        media.isNotEmpty ||
        visits.isNotEmpty ||
        scrobbles.isNotEmpty ||
        events.isNotEmpty ||
        archive.trackerRecords.any((record) => inRange(record.recordedAt));
    const allCategories = <String>[
      'Activity',
      'Journal',
      'Trackers',
      'Weekday',
      'Places',
      'Music',
    ];
    final allSectionsHidden =
        hasAnyData && allCategories.every(hidden.contains);

    // Older archives often have no records in the default 30-day window. Jump
    // to the full history once so Insights does not open as a blank page.
    if (!_autoRangeChecked &&
        _range == _Range.month &&
        !hasAnyData &&
        _earliestRecord(archive) != null) {
      _autoRangeChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _range = _Range.all);
      });
    }

    final countsByDay = <String, int>{};
    void addCount(DateTime at) {
      if (!inRange(at)) return;
      final key = dayKey(at);
      countsByDay[key] = (countsByDay[key] ?? 0) + 1;
    }

    for (final entry in published) {
      addCount(entry.createdAt);
    }
    for (final item in media) {
      addCount(item.createdAt);
    }
    for (final visit in visits) {
      addCount(visit.startAt);
    }
    for (final scrobble in scrobbles) {
      addCount(scrobble.playedAt);
    }
    for (final record in archive.trackerRecords) {
      addCount(record.recordedAt);
    }
    for (final event in events) {
      addCount(event.occurredAt);
    }

    final dailyTotals = List<int>.generate(days, (index) {
      final day = start.add(Duration(days: index));
      return countsByDay[dayKey(day)] ?? 0;
    });

    final words = published.fold<int>(
      0,
      (sum, entry) => sum + _wordCount(entry.body),
    );

    final tags = <String, int>{};
    for (final entry in published) {
      for (final tag in entry.tags) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }
    }
    final topTags = tags.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final moodValues = <int>[];
    final moodBuckets = <int, int>{for (var i = 1; i <= 10; i++) i: 0};
    for (final entry in published) {
      final mood = entry.mood;
      if (mood != null) {
        final s = mood.clamp(1, 10);
        moodValues.add(s);
        moodBuckets[s] = (moodBuckets[s] ?? 0) + 1;
      }
    }
    final moodTotal = moodValues.length;
    final moodAverage = moodValues.isEmpty
        ? null
        : moodValues.reduce((a, b) => a + b) / moodValues.length;

    final placeCounts = <String, int>{};
    for (final visit in visits) {
      placeCounts[visit.label] = (placeCounts[visit.label] ?? 0) + 1;
    }
    final topPlaces = placeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final artists = <String, int>{};
    for (final scrobble in scrobbles) {
      final artist = scrobble.displayArtist;
      artists[artist] = (artists[artist] ?? 0) + 1;
    }
    final topArtists = artists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final weekdayTotals = List<int>.filled(7, 0);
    final weekdayOccurrences = List<int>.filled(7, 0);
    for (var index = 0; index < days; index++) {
      final day = start.add(Duration(days: index));
      weekdayOccurrences[day.weekday - 1]++;
      weekdayTotals[day.weekday - 1] += dailyTotals[index];
    }
    final weekdayAverages = List<double>.generate(7, (index) {
      final occurrences = weekdayOccurrences[index];
      if (occurrences == 0) return 0;
      return weekdayTotals[index] / occurrences;
    });

    final activeTrackers = archive.activeTrackers;

    final text = context.text;
    final activeDays = dailyTotals.where((v) => v > 0).length;
    final avgWords = published.isEmpty ? 0 : (words / published.length).round();
    final rangeLabel =
        '${formatShortDate(start)} to ${formatShortDate(end)}, '
        '$days ${plural(days, 'day')}';
    final dayLabels = [
      formatShortDate(start),
      formatShortDate(start.add(Duration(days: days ~/ 2))),
      formatShortDate(end),
    ];
    final maxWeekday = weekdayAverages.fold<double>(0, math.max);
    final bestWeekday = maxWeekday <= 0
        ? null
        : weekdayAverages.indexOf(maxWeekday);

    // Music insight inputs. Artwork is keyed the same way in the day summary
    // and the Music screen so every surface shows the same cover.
    final scrobbleArt = <String, String>{};
    final trackArt = <String, String>{};
    final trackCounts = <String, ({String title, String artist, int plays})>{};
    for (final s in scrobbles) {
      final artistKey = s.displayArtist.toLowerCase();
      final trackKey = '${s.displayArtist}|${s.displayTitle}'.toLowerCase();
      if (Artwork.usable(s.artworkUrl)) {
        scrobbleArt.putIfAbsent(artistKey, () => s.artworkUrl!);
        trackArt.putIfAbsent(trackKey, () => s.artworkUrl!);
      }
      final existing = trackCounts[trackKey];
      trackCounts[trackKey] = (
        title: s.displayTitle,
        artist: s.displayArtist,
        plays: (existing?.plays ?? 0) + 1,
      );
    }
    final topTracks = trackCounts.values.toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
    final scrobblesByDay = List<double>.generate(days, (index) {
      final day = start.add(Duration(days: index));
      return scrobbles.where((s) => sameDay(s.playedAt, day)).length.toDouble();
    });
    final uniqueTracks = scrobbles
        .map((s) => '${s.displayArtist}|${s.displayTitle}'.toLowerCase())
        .toSet()
        .length;

    return ScreenFrame(
      title: 'Insights',
      actions: [
        HeaderButton(
          icon: Icons.tune_rounded,
          tooltip: 'Choose sections',
          onPressed: () => _chooseSections(context, settings, hidden),
        ),
      ],
      children: [
        FilterRow<_Range>(
          values: _Range.values,
          selected: _range,
          labelFor: (value) => value.label,
          onChanged: _selectRange,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xs,
            Insets.sm,
            0,
            Insets.md,
          ),
          child: Text(
            rangeLabel,
            style: text.labelMedium?.copyWith(color: palette.dimText),
          ),
        ),
        if (!hasAnyData || allSectionsHidden) ...[
          QuietCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights_outlined,
                      size: 28,
                      color: palette.mutedText,
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        allSectionsHidden
                            ? 'All sections are hidden'
                            : 'Nothing recorded in this range',
                        style: text.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  allSectionsHidden
                      ? 'Turn the sections back on with the button below, or '
                            'use the tune button above to choose individual ones.'
                      : 'Insights only use entries, media, visits, music and '
                            'check-ins that are actually stored on this device. '
                            'Try a wider range or add something first.',
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
                const SizedBox(height: Insets.md),
                Wrap(
                  spacing: Insets.sm,
                  children: [
                    if (allSectionsHidden)
                      FilledButton.icon(
                        onPressed: _resetSections,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Show all sections'),
                      ),
                    if (_range != _Range.all)
                      FilledButton.icon(
                        onPressed: () => setState(() => _range = _Range.all),
                        icon: const Icon(Icons.history_rounded),
                        label: const Text('Show all time'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _selectRange(_Range.custom),
                      icon: const Icon(Icons.date_range_rounded),
                      label: const Text('Choose range'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (hasAnyData && !allSectionsHidden) ...[
          QuietCard(
            child: Column(
              children: [
                Row(
                  children: [
                    ProgressRing(
                      value: activeDays / days,
                      size: 84,
                      stroke: 8,
                      child: Text(
                        '$activeDays',
                        style: text.titleLarge?.copyWith(
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$activeDays of $days ${plural(days, 'day')}',
                            style: text.headlineSmall,
                          ),
                          Text(
                            'had something recorded',
                            style: text.bodySmall?.copyWith(
                              color: palette.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.lg),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        compact: true,
                        value: '${published.length}',
                        label: 'Entries',
                        icon: Icons.menu_book_rounded,
                        accent: palette.journal,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: StatTile(
                        compact: true,
                        value: '${media.length}',
                        label: 'Media',
                        icon: Icons.photo_rounded,
                        accent: palette.photo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        compact: true,
                        value: '${visits.length}',
                        label: 'Visits',
                        icon: Icons.place_rounded,
                        accent: palette.place,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: StatTile(
                        compact: true,
                        value: '${scrobbles.length}',
                        label: 'Plays',
                        icon: Icons.graphic_eq_rounded,
                        accent: palette.music,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!hidden.contains('Activity')) ...[
            const SectionHeader(title: 'Daily activity'),
            QuietCard(
              child: MiniBarChart(
                values: dailyTotals.map((v) => v.toDouble()).toList(),
                labels: dayLabels,
                color: scheme.primary,
                height: 96,
                highlightIndex: dailyTotals.length - 1,
              ),
            ),
          ],
          if (!hidden.contains('Journal') && published.isNotEmpty) ...[
            const SectionHeader(title: 'Writing'),
            QuietCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Figure(
                          value: formatCompactNumber(words),
                          label: 'Words',
                        ),
                      ),
                      Expanded(
                        child: _Figure(value: '$avgWords', label: 'Per entry'),
                      ),
                      Expanded(
                        child: _Figure(value: '$drafts', label: 'Drafts'),
                      ),
                    ],
                  ),
                  if (moodTotal > 0) ...[
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Mood',
                            style: text.labelMedium?.copyWith(
                              color: palette.mutedText,
                            ),
                          ),
                        ),
                        if (moodAverage != null)
                          Text(
                            'Avg ${moodAverage.toStringAsFixed(1)}/10',
                            style: text.labelMedium?.copyWith(
                              color: moodColor(moodAverage.round(), scheme),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Insets.sm),
                    ...[
                      for (var score = 10; score >= 1; score--)
                        if ((moodBuckets[score] ?? 0) > 0)
                          _BreakdownRow(
                            label: '$score · ${MoodScore.label(score)}',
                            value: (moodBuckets[score] ?? 0).toDouble(),
                            maxValue: moodTotal.toDouble(),
                            color: moodColor(score, scheme),
                          ),
                    ],
                  ],
                  if (topTags.isNotEmpty) ...[
                    const SizedBox(height: Insets.lg),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final tag in topTags.take(8))
                          TagPill('${tag.key} ${tag.value}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (!hidden.contains('Trackers') && activeTrackers.isNotEmpty) ...[
            const SectionHeader(title: 'Habits'),
            QuietCard(
              padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              child: Column(
                children: [
                  for (var i = 0; i < activeTrackers.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 64, color: palette.border),
                    _HabitInsightRow(
                      tracker: activeTrackers[i],
                      start: start,
                      end: end,
                      days: days,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (!hidden.contains('Weekday') && dailyTotals.any((v) => v > 0)) ...[
            SectionHeader(
              title: 'Weekly rhythm',
              subtitle: bestWeekday == null
                  ? null
                  : 'Busiest on ${_weekdayLabels[bestWeekday]}',
            ),
            QuietCard(
              child: MiniBarChart(
                values: weekdayAverages,
                labels: _weekdayLabels,
                color: scheme.primary,
                height: 80,
                highlightIndex: bestWeekday,
              ),
            ),
          ],
          if (!hidden.contains('Places') && topPlaces.isNotEmpty) ...[
            const SectionHeader(title: 'Places'),
            QuietCard(
              child: Column(
                children: [
                  for (final place in topPlaces.take(5))
                    HorizontalMetricBar(
                      label: place.key,
                      value: place.value.toDouble(),
                      maxValue: topPlaces.first.value.toDouble(),
                      trailing: '${place.value}',
                      color: palette.place,
                    ),
                ],
              ),
            ),
          ],
          if (!hidden.contains('Music') && scrobbles.isNotEmpty) ...[
            const SectionHeader(title: 'Music'),
            QuietCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You listened to ${scrobbles.length} ${plural(scrobbles.length, 'play')}: '
                    '$uniqueTracks ${plural(uniqueTracks, 'track')} across '
                    '${artists.length} ${plural(artists.length, 'artist')}.',
                    style: AppTheme.serif(
                      text.titleLarge,
                      size: 19,
                    ).copyWith(height: 1.3),
                  ),
                  const SizedBox(height: Insets.lg),
                  MiniBarChart(
                    values: scrobblesByDay,
                    labels: dayLabels,
                    color: palette.music,
                    height: 64,
                    showBaseline: false,
                  ),
                  const SizedBox(height: Insets.lg),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: topArtists.take(8).length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: Insets.md),
                      itemBuilder: (context, index) {
                        final artist = topArtists[index];
                        return SizedBox(
                          width: 64,
                          child: Column(
                            children: [
                              Artwork(
                                url: scrobbleArt[artist.key.toLowerCase()],
                                size: 56,
                                circle: true,
                                seed: artist.key,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                artist.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: text.labelSmall,
                              ),
                              Text(
                                '${artist.value}',
                                style: text.labelSmall?.copyWith(
                                  color: palette.dimText,
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (topTracks.isNotEmpty) ...[
                    const SizedBox(height: Insets.lg),
                    Text('Top tracks', style: text.titleSmall),
                    const SizedBox(height: Insets.sm),
                    SizedBox(
                      height: 116,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: topTracks.take(8).length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: Insets.md),
                        itemBuilder: (context, index) {
                          final track = topTracks[index];
                          final key = '${track.artist}|${track.title}'
                              .toLowerCase();
                          return SizedBox(
                            width: 72,
                            child: Column(
                              children: [
                                Artwork(
                                  url: trackArt[key],
                                  size: 56,
                                  seed: key,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: text.labelSmall,
                                ),
                                Text(
                                  '${track.plays} ${plural(track.plays, 'play')}',
                                  style: text.labelSmall?.copyWith(
                                    color: palette.dimText,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _selectRange(_Range range) async {
    if (range == _Range.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: dayStart(DateTime.now()),
        initialDateRange: DateTimeRange(
          start: _customStart ?? _start,
          end: _customEnd ?? _end,
        ),
        helpText: 'Choose a range to count',
      );
      if (picked == null) return;
      setState(() {
        _range = _Range.custom;
        _customStart = dayStart(picked.start);
        _customEnd = dayStart(picked.end);
      });
      return;
    }
    setState(() => _range = range);
  }

  Future<void> _resetSections() async {
    final controller = ref.read(settingsProvider.notifier);
    for (final category in const <String>[
      'Activity',
      'Journal',
      'Trackers',
      'Weekday',
      'Places',
      'Music',
    ]) {
      await controller.hideInsightCategory(category, false);
    }
  }

  Future<void> _chooseSections(
    BuildContext context,
    AppSettings settings,
    Set<String> hidden,
  ) async {
    const categories = <String, String>{
      'Activity': 'Daily activity',
      'Journal': 'Writing',
      'Trackers': 'Habits',
      'Weekday': 'Weekly rhythm',
      'Places': 'Places',
      'Music': 'Music',
    };
    final local = {...hidden};
    final result = await showLifelogSheet<List<String>>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setLocal) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle(
              title: 'Sections',
              subtitle: 'Hidden sections stay hidden after restarting the app.',
            ),
            for (final entry in categories.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !local.contains(entry.key),
                title: Text(entry.value),
                onChanged: (value) => setLocal(() {
                  if (value) {
                    local.remove(entry.key);
                  } else {
                    local.add(entry.key);
                  }
                }),
              ),
            const SizedBox(height: Insets.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setLocal(() => local.clear()),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Show all sections'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(local.toList()),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final controller = ref.read(settingsProvider.notifier);
    for (final category in categories.keys) {
      await controller.hideInsightCategory(category, result.contains(category));
    }
  }

  int _wordCount(String body) {
    final clean = body.trim();
    if (clean.isEmpty) return 0;
    return clean.split(RegExp(r'\s+')).length;
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return HorizontalMetricBar(
      label: label,
      value: value,
      maxValue: maxValue,
      color: color,
      trailing: '${value.round()}',
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: context.text.titleLarge?.copyWith(
            fontFeatures: tabularFigures,
          ),
        ),
        Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: context.palette.dimText,
          ),
        ),
      ],
    );
  }
}

class _HabitInsightRow extends ConsumerWidget {
  const _HabitInsightRow({
    required this.tracker,
    required this.start,
    required this.end,
    required this.days,
  });

  final TrackerDefinition tracker;
  final DateTime start;
  final DateTime end;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final history = HabitHistory(tracker, archive.trackerRecords);
    final accent = trackerColor(tracker.colorValue);
    final palette = context.palette;
    var done = 0;
    for (var i = 0; i < days; i++) {
      if (history.doneOn(DateTime(start.year, start.month, start.day + i))) {
        done++;
      }
    }
    final series = TrackerMath.dailySeries(
      tracker,
      archive.trackerRecords,
      end,
      14,
    );
    final now = DateTime.now();
    var loggedInLast30 = 0;
    for (var i = 0; i < 30; i++) {
      final dayInWindow = DateTime(now.year, now.month, now.day - i);
      if (history.loggedOn(dayInWindow)) loggedInLast30++;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.sm,
      ),
      child: Row(
        children: [
          IconBadge(
            icon: trackerIcon(tracker.icon),
            color: accent,
            size: 36,
            iconSize: 18,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                Row(
                  children: [
                    Text(
                      'Logged $done of $days days · $loggedInLast30 of last 30',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.mutedText,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 92,
            child: MiniBarChart(
              values: series.map((p) => p.value).toList(),
              color: accent,
              height: 30,
              showBaseline: false,
            ),
          ),
        ],
      ),
    );
  }
}
