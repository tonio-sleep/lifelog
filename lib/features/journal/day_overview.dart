import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/memories.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/trackers.dart';

int _wordCount(String text) => RegExp(r'\S+').allMatches(text).length;

bool _metricsOnly(JournalEntry entry) {
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

/// Everything worth showing about one day, derived from stored records only.
class DayStats {
  const DayStats({
    required this.day,
    required this.writing,
    required this.words,
    required this.photos,
    required this.videos,
    required this.checkins,
    required this.meals,
    required this.events,
    required this.places,
    required this.songs,
    required this.habits,
    required this.mood,
    required this.energy,
    required this.steps,
    required this.sleepHours,
    required this.uniqueArtists,
    required this.topTrack,
    required this.topArtist,
    required this.topTrackArtworkUrl,
    required this.topArtistArtworkUrl,
    required this.topPlace,
    required this.topPlaceTime,
  });

  final DateTime day;

  /// Written entries (no check-ins or health-only records).
  final List<JournalEntry> writing;
  final int words;
  final int photos;
  final int videos;
  final int checkins;
  final int meals;
  final int events;
  final int places;
  final int songs;
  final int habits;
  final int? mood;
  final double? energy;
  final int? steps;
  final double? sleepHours;
  final int uniqueArtists;
  final ({String name, String artist, int plays})? topTrack;
  final ({String name, int plays})? topArtist;
  final String? topTrackArtworkUrl;
  final String? topArtistArtworkUrl;
  final String? topPlace;
  final Duration topPlaceTime;

  int get entries => writing.length;

  /// A one-line narrative built only from records that exist. It is a caption
  /// for the day, never a replacement for the underlying entries.
  String get summary {
    final highlights = <String>[];
    if (entries > 0) {
      highlights.add('$entries ${plural(entries, 'entry', 'entries')}');
    }
    if (photos + videos > 0) {
      highlights.add(
        '${photos + videos} ${plural(photos + videos, 'photo', 'photos')}',
      );
    }
    if (songs > 0) highlights.add('$songs ${plural(songs, 'song')}');
    if (meals > 0) highlights.add('$meals ${plural(meals, 'meal')}');
    if (topPlace != null) highlights.add('time at $topPlace');
    if (highlights.isEmpty) return 'Nothing recorded for this day.';
    if (highlights.length == 1) return '${highlights.first} recorded.';
    final last = highlights.removeLast();
    return '${highlights.join(', ')} and $last.';
  }

  bool get isEmpty =>
      entries == 0 &&
      photos == 0 &&
      videos == 0 &&
      checkins == 0 &&
      meals == 0 &&
      events == 0 &&
      places == 0 &&
      songs == 0 &&
      habits == 0;

  static DayStats of(Archive archive, DateTime day) {
    final entries = archive.entriesOn(day, includeDrafts: true);
    final writing = entries
        .where((e) => !e.isCheckinEntry && !_metricsOnly(e))
        .toList();
    final checkins = entries.where((e) => e.isCheckinEntry).toList();

    var words = 0;
    for (final entry in writing) {
      words += _wordCount(entry.body);
      for (final v in entry.vocabItems) {
        words += _wordCount(v.term) + _wordCount(v.meaning);
      }
    }

    final media = archive.mediaOn(day);
    final videos = media.where((m) => m.isVideo).length;

    final placeTime = <String, Duration>{};
    final placeNames = <String>{};
    for (final visit in archive.visitsOn(day)) {
      final label = visit.label.trim();
      if (label.isEmpty || label == 'Traveling') continue;
      placeNames.add(label);
      final d = visit.duration;
      if (d == null || label == 'Another location') continue;
      placeTime[label] = (placeTime[label] ?? Duration.zero) + d;
    }
    String? topPlace;
    var topPlaceTime = Duration.zero;
    placeTime.forEach((name, d) {
      if (d > topPlaceTime) {
        topPlace = name;
        topPlaceTime = d;
      }
    });

    final energies = entries.where((e) => e.energy != null).toList();
    final energy = energies.isEmpty
        ? null
        : energies.fold<int>(0, (s, e) => s + e.energy!) / energies.length;

    final metrics = archive.dayMetricsEntryFor(day);
    final music = archive.musicOn(day);
    final habits = archive.activeTrackers
        .where((t) => TrackerMath.loggedOn(archive.trackerRecords, t.id, day))
        .length;

    // Keep the cover that belongs to the headline artist/track rather than
    // whichever scrobble happened to be last.
    String? topTrackArtworkUrl;
    String? topArtistArtworkUrl;
    final topTrackKey = music.topTracks.isEmpty
        ? null
        : '${music.topTracks.first.artist}|${music.topTracks.first.name}'
              .toLowerCase();
    final topArtistKey = music.topArtists.isEmpty
        ? null
        : music.topArtists.first.name.toLowerCase();
    for (final scrobble in music.scrobbles) {
      if (!Artwork.usable(scrobble.artworkUrl)) continue;
      final key = '${scrobble.displayArtist}|${scrobble.displayTitle}'
          .toLowerCase();
      if (key == topTrackKey) topTrackArtworkUrl ??= scrobble.artworkUrl;
      if (scrobble.displayArtist.toLowerCase() == topArtistKey) {
        topArtistArtworkUrl ??= scrobble.artworkUrl;
      }
    }

    return DayStats(
      day: dayStart(day),
      writing: writing,
      words: words,
      photos: media.length - videos,
      videos: videos,
      checkins: checkins.length,
      meals: archive.mealsOn(day).length,
      events: archive.eventsOn(day).length,
      places: placeNames.length,
      songs: music.total,
      habits: habits,
      mood: dominantMood(archive, day),
      energy: energy,
      steps: metrics?.steps,
      sleepHours: metrics?.sleepHours,
      uniqueArtists: music.uniqueArtists,
      topTrack: music.topTracks.isEmpty ? null : music.topTracks.first,
      topArtist: music.topArtists.isEmpty ? null : music.topArtists.first,
      topTrackArtworkUrl: topTrackArtworkUrl,
      topArtistArtworkUrl: topArtistArtworkUrl,
      topPlace: topPlace,
      topPlaceTime: topPlaceTime,
    );
  }

  /// Stat tiles for this day. The first three are always present so the
  /// journal reads consistently; the rest only appear when there is data.
  List<_Stat> _stats(LifelogPalette palette) => [
    _Stat(
      Icons.edit_note_rounded,
      entries,
      'Entries',
      palette.journal,
      always: true,
    ),
    _Stat(
      Icons.photo_outlined,
      photos + videos,
      'Photos',
      palette.photo,
      always: true,
    ),
    _Stat(
      Icons.mood_outlined,
      checkins,
      'Check-ins',
      palette.tracker,
      always: true,
    ),
    _Stat(Icons.restaurant_outlined, meals, 'Meals', palette.warning),
    _Stat(Icons.music_note_rounded, songs, 'Songs', palette.music),
    _Stat(Icons.place_outlined, places, 'Places', palette.place),
    _Stat(Icons.task_alt_rounded, habits, 'Habits', palette.success),
    _Stat(Icons.bolt_rounded, events, 'Events', palette.manual),
  ];
}

class _Stat {
  const _Stat(
    this.icon,
    this.value,
    this.label,
    this.color, {
    this.always = false,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;
  final bool always;

  bool get visible => always || value > 0;
}

/// Horizontal strip of stat tiles, used on the Today screen.
class DayStatStrip extends StatelessWidget {
  const DayStatStrip({super.key, required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context) {
    final items = stats
        ._stats(context.palette)
        .where((s) => s.visible)
        .toList();
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
        itemBuilder: (context, i) => _StatTile(stat: items[i], width: 84),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat, this.width});

  final _Stat stat;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final empty = stat.value == 0;
    final color = empty ? palette.dimText : stat.color;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: empty ? 0.05 : 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stat.icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                '${stat.value}',
                style: text.titleMedium?.copyWith(
                  color: empty ? palette.dimText : null,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: palette.mutedText),
          ),
        ],
      ),
    );
  }
}

/// "Day at a glance": counts, most-played music and where time went.
class DayOverviewCard extends StatelessWidget {
  const DayOverviewCard({super.key, required this.stats});

  final DayStats stats;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final items = stats._stats(palette).where((s) => s.visible).toList();
    final extras = <Widget>[
      if (stats.words > 0)
        SourceChip(
          label: '${formatCompactNumber(stats.words)} words',
          icon: Icons.notes_rounded,
          color: palette.journal,
          dense: true,
        ),
      if (stats.steps != null)
        SourceChip(
          label: '${stats.steps} steps',
          icon: Icons.directions_walk_rounded,
          color: palette.music,
          dense: true,
        ),
      if (stats.sleepHours != null)
        SourceChip(
          label:
              '${formatCompactNumber(double.parse(stats.sleepHours!.toStringAsFixed(1)))}h sleep',
          icon: Icons.bedtime_outlined,
          color: palette.place,
          dense: true,
        ),
      if (stats.energy != null)
        SourceChip(
          label: 'Energy ${stats.energy!.toStringAsFixed(1)}/5',
          icon: Icons.bolt_rounded,
          color: palette.tracker,
          dense: true,
        ),
    ];

    return QuietCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Day at a glance', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            stats.summary,
            style: text.bodyMedium?.copyWith(color: palette.mutedText),
          ),
          const SizedBox(height: Insets.md),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = Insets.sm;
              final width = (constraints.maxWidth - gap * 2) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items) _StatTile(stat: item, width: width),
                ],
              );
            },
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: Insets.md),
            Wrap(spacing: Insets.sm, runSpacing: Insets.xs, children: extras),
          ],
          if (stats.topTrack != null) ...[
            const SizedBox(height: Insets.md),
            _InsightRow(
              icon: Icons.music_note_rounded,
              color: palette.music,
              artworkUrl: stats.topTrackArtworkUrl,
              artworkSeed: '${stats.topTrack!.artist}|${stats.topTrack!.name}',
              title: 'Most played',
              body:
                  '${stats.topTrack!.name} · ${stats.topTrack!.artist}'
                  '${stats.topTrack!.plays > 1 ? ' (${stats.topTrack!.plays}×)' : ''}',
            ),
            if (stats.topArtist != null) ...[
              const SizedBox(height: Insets.sm),
              _InsightRow(
                icon: Icons.mic_external_on_outlined,
                color: palette.music,
                artworkUrl: stats.topArtistArtworkUrl,
                artworkSeed: stats.topArtist!.name,
                circle: true,
                title: 'Top artist',
                body:
                    '${stats.topArtist!.name} · ${stats.topArtist!.plays} '
                    '${plural(stats.topArtist!.plays, 'play')}'
                    ' · ${stats.songs} ${plural(stats.songs, 'song')}, '
                    '${stats.uniqueArtists} ${plural(stats.uniqueArtists, 'artist')}',
              ),
            ],
          ],
          if (stats.topPlace != null) ...[
            const SizedBox(height: Insets.sm),
            _InsightRow(
              icon: Icons.place_outlined,
              color: palette.place,
              title: 'Most time at',
              body:
                  '${stats.topPlace!} · ${formatDurationMinutes(stats.topPlaceTime.inMinutes)}',
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.artworkUrl,
    this.artworkSeed,
    this.circle = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? artworkUrl;
  final String? artworkSeed;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (artworkSeed != null)
          Artwork(
            url: artworkUrl,
            seed: artworkSeed!,
            size: 38,
            circle: circle,
            icon: icon,
          )
        else
          IconBadge(icon: icon, color: color, size: 34, iconSize: 17),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.labelSmall?.copyWith(color: palette.mutedText),
              ),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day in the Journal list: date, mood, counts, a preview of the writing
/// and the headline music/place. Tapping opens the full day summary.
class JournalDayCard extends StatelessWidget {
  const JournalDayCard({
    super.key,
    required this.stats,
    required this.onOpen,
    required this.onAdd,
    this.previews,
  });

  final DayStats stats;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  /// Entries to preview (e.g. search matches). Defaults to the day's writing.
  final List<JournalEntry>? previews;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final day = stats.day;
    final mood = stats.mood;
    final accent = mood == null
        ? palette.mutedText
        : moodColor(mood, context.scheme);
    final stat = stats._stats(palette).where((s) => s.visible).toList();
    final preview = previews ?? stats.writing;
    final first = preview.isEmpty ? null : preview.first;

    final footer = <Widget>[
      if (stats.topTrack != null)
        _FooterLine(
          icon: Icons.music_note_rounded,
          color: palette.music,
          artworkUrl: stats.topTrackArtworkUrl,
          artworkSeed: '${stats.topTrack!.artist}|${stats.topTrack!.name}',
          text: 'Top song: ${stats.topTrack!.name} · ${stats.topTrack!.artist}',
        ),
      if (stats.topPlace != null)
        _FooterLine(
          icon: Icons.place_outlined,
          color: palette.place,
          text:
              '${stats.topPlace!} · ${formatDurationMinutes(stats.topPlaceTime.inMinutes)}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: QuietCard(
        onTap: onOpen,
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('EEE').format(day).toUpperCase(),
                        style: text.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '${day.day}',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relativeDayLabel(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          DateFormat('MMMM d').format(day),
                          if (mood != null) MoodScore.label(mood),
                          if (stats.words > 0)
                            '${formatCompactNumber(stats.words)} words',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: palette.mutedText,
                        ),
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
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [for (final s in stat) _MiniStat(stat: s)],
            ),
            if (first != null) ...[
              const SizedBox(height: Insets.md),
              Text(
                first.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
              if (first.excerpt != 'No text')
                Text(
                  first.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: palette.mutedText,
                    height: 1.4,
                  ),
                ),
              if (preview.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+${preview.length - 1} more ${plural(preview.length - 1, 'entry', 'entries')}',
                    style: text.labelSmall?.copyWith(color: palette.dimText),
                  ),
                ),
            ],
            if (footer.isNotEmpty) ...[
              const SizedBox(height: Insets.sm),
              for (final line in footer) line,
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final empty = stat.value == 0;
    final color = empty ? palette.dimText : stat.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: empty ? 0.05 : 0.11),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stat.icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '${stat.value} ${stat.value == 1 ? _singular(stat.label) : stat.label}',
            style: context.text.labelMedium?.copyWith(
              color: empty ? palette.dimText : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _singular(String label) => switch (label) {
    'Entries' => 'Entry',
    'Photos' => 'Photo',
    'Check-ins' => 'Check-in',
    'Meals' => 'Meal',
    'Songs' => 'Song',
    'Places' => 'Place',
    'Habits' => 'Habit',
    'Events' => 'Event',
    _ => label,
  };
}

class _FooterLine extends StatelessWidget {
  const _FooterLine({
    required this.icon,
    required this.color,
    required this.text,
    this.artworkUrl,
    this.artworkSeed,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? artworkUrl;
  final String? artworkSeed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          if (artworkSeed != null)
            Artwork(url: artworkUrl, seed: artworkSeed!, size: 20, icon: icon)
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Overall journal numbers shown above the day list.
class JournalOverviewCard extends StatelessWidget {
  const JournalOverviewCard({super.key, required this.archive});

  final Archive archive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final live = archive.entries.where((e) => !e.archived).toList();
    final checkins = live.where((e) => e.isCheckinEntry).length;
    final writing = live
        .where((e) => !e.isCheckinEntry && !_metricsOnly(e))
        .length;
    final streak = currentStreak(archive, DateTime.now());
    final tiles = <_Stat>[
      _Stat(
        Icons.local_fire_department_rounded,
        streak,
        'Streak',
        palette.warning,
        always: true,
      ),
      _Stat(
        Icons.edit_note_rounded,
        writing,
        'Entries',
        palette.journal,
        always: true,
      ),
      _Stat(
        Icons.photo_outlined,
        archive.media.length,
        'Photos',
        palette.photo,
        always: true,
      ),
      _Stat(
        Icons.mood_outlined,
        checkins,
        'Check-ins',
        palette.tracker,
        always: true,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = Insets.sm;
          final width = (constraints.maxWidth - gap * 3) / 4;
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _StatTile(stat: tiles[i], width: width),
              ],
            ],
          );
        },
      ),
    );
  }
}
