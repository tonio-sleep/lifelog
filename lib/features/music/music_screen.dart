import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/music.dart';
import '../insights/charts.dart';
import 'lastfm_screen.dart';
import 'music_dialogs.dart';
import 'music_sync.dart';

/// "1h 12m 4s", "12m 4s" or "4s": always largest unit first, then down to
/// seconds.
String formatGap(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (d.inMinutes > 0) return '${m}m ${s}s';
  return '${s}s';
}

enum _Scope { day, week }

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key, this.day});

  final DateTime? day;

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> {
  late DateTime _day;
  _Scope _scope = _Scope.day;
  int _limit = 40;

  @override
  void initState() {
    super.initState();
    _day = dayStart(widget.day ?? DateTime.now());
  }

  void _shift(int delta) => setState(() {
    _day = DateTime(_day.year, _day.month, _day.day + delta);
    _limit = 40;
  });

  Future<void> _refresh() async {
    final result = await syncLastfmRecent(ref, days: 3);
    if (mounted) showSnack(context, result.message);
  }

  void _openLastfm() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const LastfmScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final settings = ref.watch(settingsProvider);
    final palette = context.palette;

    return ScreenFrame(
      title: 'Music',
      onRefresh: settings.lastfmConnected ? _refresh : null,
      actions: [
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'Add a track by hand',
          onPressed: () => showManualScrobbleDialog(context, ref, day: _day),
        ),
        HeaderButton(
          icon: settings.lastfmConnected ? Icons.sync_rounded : Icons.link_rounded,
          tooltip: 'Last.fm',
          onPressed: _openLastfm,
          color: settings.lastfmConnected ? null : palette.music,
        ),
      ],
      children: [
        if (archive.scrobbles.isEmpty)
          EmptyState(
            icon: Icons.graphic_eq_rounded,
            color: palette.music,
            title: 'No music yet',
            message: 'Connect Last.fm to import your listening, or add a track by hand.',
            actionLabel: 'Connect Last.fm',
            onAction: _openLastfm,
          )
        else ...[
          DayNavigator(
            day: _day,
            onChanged: (value) => setState(() {
              _day = value;
              _limit = 40;
            }),
          ),
          const SizedBox(height: Insets.md),
          SegmentedPills<_Scope>(
            values: _Scope.values,
            selected: _scope,
            labelFor: (scope) => scope == _Scope.day ? 'Day' : 'Past 7 days',
            onChanged: (value) => setState(() {
              _scope = value;
              _limit = 40;
            }),
          ),
          const SizedBox(height: Insets.lg),
          DaySwitcher(
            day: _day,
            onSwipe: _shift,
            builder: (context, day) => _MusicBody(
              day: day,
              scope: _scope,
              limit: _limit,
              onMore: () => setState(() => _limit += 40),
              onAdd: () => showManualScrobbleDialog(context, ref, day: day),
            ),
          ),
        ],
      ],
    );
  }
}

class _MusicBody extends ConsumerWidget {
  const _MusicBody({
    required this.day,
    required this.scope,
    required this.limit,
    required this.onMore,
    required this.onAdd,
  });

  final DateTime day;
  final _Scope scope;
  final int limit;
  final VoidCallback onMore;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final text = context.text;

    final start = scope == _Scope.day
        ? day
        : DateTime(day.year, day.month, day.day - 6);
    final end = DateTime(day.year, day.month, day.day + 1);
    final inRange = archive.scrobbles
        .where((s) => !s.playedAt.isBefore(start) && s.playedAt.isBefore(end))
        .toList();

    if (inRange.isEmpty) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        color: palette.music,
        title: scope == _Scope.day ? 'Nothing played' : 'Nothing this week',
        message: 'No listening is stored for this period.',
        actionLabel: 'Add a track',
        onAction: onAdd,
        compact: true,
      );
    }

    final summary = MusicDaySummary.fromScrobbles(inRange);
    final artByArtist = <String, String>{};
    final artByTrack = <String, String>{};
    for (final s in summary.scrobbles) {
      if (!Artwork.usable(s.artworkUrl)) continue;
      artByArtist[s.displayArtist] = s.artworkUrl!;
      artByTrack['${s.displayArtist}|${s.displayTitle}'.toLowerCase()] =
          s.artworkUrl!;
    }

    // Mini chart: plays per hour for a day, per day for the week.
    late final List<double> bars;
    late final List<String> barLabels;
    if (scope == _Scope.day) {
      bars = List<double>.filled(24, 0);
      for (final s in inRange) {
        bars[s.playedAt.hour] += 1;
      }
      barLabels = const ['12a', '6a', '12p', '6p', '12a'];
    } else {
      bars = List<double>.filled(7, 0);
      for (final s in inRange) {
        final index = DateTime(s.playedAt.year, s.playedAt.month, s.playedAt.day)
            .difference(start)
            .inDays;
        if (index >= 0 && index < 7) bars[index] += 1;
      }
      barLabels = [
        for (var i = 0; i < 7; i++)
          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime(
                    start.year,
                    start.month,
                    start.day + i,
                  ).weekday -
                  1],
      ];
    }

    final heroArt = summary.topArtists.isEmpty
        ? null
        : artByArtist[summary.topArtists.first.name];
    final maxTrack = summary.topTracks.isEmpty ? 1 : summary.topTracks.first.plays;
    final newestFirst = summary.scrobbles.reversed.toList();
    final shown = newestFirst.take(limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(
          scopeLabel: scope == _Scope.day ? relativeDayLabel(day) : 'Past 7 days',
          total: summary.total,
          artists: summary.uniqueArtists,
          tracks: summary.uniqueTracks,
          topArtist: summary.topArtistName,
          artUrl: heroArt,
          bars: bars,
          barLabels: barLabels,
          highlight: scope == _Scope.week ? 6 : null,
        ),
        if (summary.topArtists.isNotEmpty) ...[
          const SectionHeader(title: 'Top artists'),
          SizedBox(
            height: 142,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: summary.topArtists.take(12).length,
              separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
              itemBuilder: (context, index) {
                final artist = summary.topArtists[index];
                return SizedBox(
                  width: 92,
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Artwork(
                            url: artByArtist[artist.name],
                            size: 92,
                            circle: true,
                            seed: artist.name,
                          ),
                          Positioned(
                            left: -2,
                            bottom: -2,
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: palette.card,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.border),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: text.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Insets.sm),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: text.labelLarge,
                      ),
                      Text(
                        '${artist.plays} ${plural(artist.plays, 'play')}',
                        style: text.labelSmall?.copyWith(color: palette.dimText),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        if (summary.topTracks.isNotEmpty) ...[
          const SectionHeader(title: 'Top tracks'),
          QuietCard(
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: Column(
              children: [
                for (var i = 0; i < summary.topTracks.take(6).length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 76, color: palette.border),
                  _TrackRow(
                    rank: i + 1,
                    track: summary.topTracks[i],
                    maxPlays: maxTrack,
                    url: artByTrack[
                        '${summary.topTracks[i].artist}|${summary.topTracks[i].name}'
                            .toLowerCase()],
                  ),
                ],
              ],
            ),
          ),
        ],
        SectionHeader(
          title: 'Listening log',
          subtitle: 'Press and hold a play to remove it',
        ),
        _PlaysLog(
          plays: shown,
          weekScope: scope == _Scope.week,
        ),
        if (newestFirst.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Center(
              child: TextButton(
                onPressed: onMore,
                child: Text('Show more (${newestFirst.length - shown.length} left)'),
              ),
            ),
          ),
      ],
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.scopeLabel,
    required this.total,
    required this.artists,
    required this.tracks,
    required this.topArtist,
    required this.artUrl,
    required this.bars,
    required this.barLabels,
    this.highlight,
  });

  final String scopeLabel;
  final int total;
  final int artists;
  final int tracks;
  final String? topArtist;
  final String? artUrl;
  final List<double> bars;
  final List<String> barLabels;
  final int? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArt = ref.watch(settingsProvider.select((s) => s.showArtwork));
    final palette = context.palette;
    final text = context.text;
    final hue = (topArtist ?? 'music').codeUnits.fold<int>(7, (a, b) => (a * 31 + b) % 360);
    final a = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 50) % 360.0, 0.6, 0.22).toColor();

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.xl),
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [a, b],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showArt && Artwork.usable(artUrl))
              Transform.scale(
                scale: 1.5,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Image.network(
                    artUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 240,
                    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.graphic_eq_rounded, size: 16, color: palette.music.withValues(alpha: 1)),
                      const SizedBox(width: 6),
                      Text(
                        scopeLabel,
                        style: text.labelLarge?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    '$total ${plural(total, 'play')} across $artists ${plural(artists, 'artist')}',
                    style: AppTheme.serif(text.headlineMedium, size: 26)
                        .copyWith(color: Colors.white, height: 1.15),
                  ),
                  if (topArtist != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Most played: $topArtist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                  const Spacer(),
                  MiniBarChart(
                    values: bars,
                    color: Colors.white,
                    height: 54,
                    showBaseline: false,
                    labels: barLabels,
                    labelColor: Colors.white60,
                    trackColor: Colors.white.withValues(alpha: 0.16),
                    highlightIndex: highlight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.rank,
    required this.track,
    required this.maxPlays,
    required this.url,
  });

  final int rank;
  final ({String name, String artist, int plays}) track;
  final int maxPlays;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: text.labelMedium?.copyWith(
                color: palette.dimText,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          Artwork(url: url, size: 46, radius: 10, seed: track.artist),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
                const SizedBox(height: 5),
                AnimatedBar(
                  value: track.plays / maxPlays,
                  height: 3,
                  color: palette.music,
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.md),
          Text(
            '${track.plays}',
            style: text.titleSmall?.copyWith(fontFeatures: tabularFigures),
          ),
        ],
      ),
    );
  }
}

/// The plays themselves, newest first. Time sits at the right edge as a small
/// number; gaps between plays are shown in hours, minutes and seconds.
class _PlaysLog extends ConsumerWidget {
  const _PlaysLog({required this.plays, required this.weekScope});

  final List<MusicScrobble> plays;
  final bool weekScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    final rows = <Widget>[];
    for (var i = 0; i < plays.length; i++) {
      final play = plays[i];
      final previous = i == 0 ? null : plays[i - 1];
      final newDay = previous == null || !sameDay(previous.playedAt, play.playedAt);
      if (weekScope && newDay) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Insets.lg, bottom: Insets.xs),
            child: Text(
              relativeDayLabel(play.playedAt),
              style: text.labelLarge?.copyWith(color: palette.mutedText),
            ),
          ),
        );
      }
      if (previous != null && !newDay) {
        final gap = previous.playedAt.difference(play.playedAt);
        if (gap.inMinutes >= 5) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_outline_rounded, size: 14, color: palette.dimText),
                  const SizedBox(width: 6),
                  Text(
                    formatGap(gap),
                    style: text.labelSmall?.copyWith(
                      color: palette.dimText,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
      rows.add(_PlayRow(play: play));
    }
    return Column(children: rows);
  }
}

class _PlayRow extends ConsumerWidget {
  const _PlayRow({required this.play});

  final MusicScrobble play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = context.text;
    return Pressable(
      borderRadius: BorderRadius.circular(Radii.md),
      scale: 0.99,
      onLongPress: () async {
        final ok = await confirm(
          context,
          title: 'Remove this play?',
          message: '“${play.displayTitle}” by ${play.displayArtist} will be '
              'removed from your archive.',
          confirmLabel: 'Remove',
        );
        if (ok) {
          if (!context.mounted) return;
          await guard(
            context,
            ref.read(archiveProvider.notifier).deleteScrobble(play.id),
            errorPrefix: 'Could not remove play',
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Artwork(
              url: play.artworkUrl,
              size: 44,
              radius: 10,
              seed: play.displayArtist,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    play.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    play.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.sm),
            if (play.source == 'manual')
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.edit_outlined, size: 11, color: palette.dimText),
              ),
            Text(
              formatTime(play.playedAt),
              style: text.labelSmall?.copyWith(
                color: palette.dimText,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
