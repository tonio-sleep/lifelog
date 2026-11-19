import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/music.dart';
import '../../integrations/cloudflare/sync_status.dart';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return 'Late night';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// One quiet wash of the accent colour behind today's header. Other days get
/// none, which is itself the cue that you are looking at the past.
class TodayGlow extends StatelessWidget {
  const TodayGlow({super.key, required this.isToday});

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final accent = context.scheme.primary;
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: context.reduceMotion ? Duration.zero : Motion.slow,
        opacity: isToday ? 1 : 0,
        child: Container(
          height: 280,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.8, -1.2),
              radius: 1.2,
              colors: [
                accent.withValues(alpha: dark ? 0.14 : 0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TodayHeader extends StatelessWidget {
  const TodayHeader({
    super.key,
    required this.day,
    required this.streak,
    required this.calendarOpen,
    required this.onToggleCalendar,
    required this.onSearch,
    required this.onAccount,
    this.onAdd,
  });

  final DateTime day;
  final int streak;
  final bool calendarOpen;
  final VoidCallback onToggleCalendar;
  final VoidCallback onSearch;
  final VoidCallback onAccount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final palette = context.palette;
    final now = DateTime.now();
    final isToday = sameDay(day, now);
    final dateFormat = DateFormat(day.year == now.year ? 'MMMM d' : 'MMMM d, y');
    final eyebrow = isToday
        ? '${DateFormat('EEEE').format(day)}, ${greetingFor(now).toLowerCase()}'
        : DateFormat('EEEE').format(day);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Text(
                    eyebrow,
                    key: ValueKey<String>(eyebrow),
                    style: text.labelLarge?.copyWith(color: palette.mutedText),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: Motion.base,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    dateFormat.format(day),
                    key: ValueKey<String>(dateFormat.format(day)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.displaySmall,
                  ),
                ),
                // A fact, not a reward: no icon, no colour.
                if (streak >= 2)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.xs),
                    child: Text(
                      '$streak days in a row',
                      style: text.labelMedium?.copyWith(
                        color: palette.mutedText,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HeaderButton(
                icon: Icons.search_rounded,
                tooltip: 'Search',
                onPressed: onSearch,
              ),
              HeaderButton(
                icon: calendarOpen
                    ? Icons.calendar_view_week_rounded
                    : Icons.calendar_month_rounded,
                tooltip: calendarOpen ? 'Show week' : 'Show month',
                onPressed: onToggleCalendar,
              ),
              _AccountButton(onPressed: onAccount),
              if (onAdd != null)
                HeaderButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Add',
                  onPressed: onAdd,
                  filled: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens Settings, and carries a small dot when the cloud session needs
/// attention so that state is visible without opening anything.
class _AccountButton extends ConsumerWidget {
  const _AccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = watchSyncStatus(ref).phase;
    final attention =
        phase == SyncPhase.expired || phase == SyncPhase.expiresSoon;
    return Stack(
      alignment: Alignment.center,
      children: [
        HeaderButton(
          icon: Icons.person_outline_rounded,
          tooltip: attention ? 'Settings, sync needs attention' : 'Settings',
          onPressed: onPressed,
        ),
        if (attention)
          Positioned(
            top: 10,
            right: 10,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: context.palette.warning,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.scheme.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Seven days around the selected one. Selection slides; days with records
/// carry a small dot.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.hasActivity,
    required this.weekStartsMonday,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final bool Function(DateTime day) hasActivity;
  final bool weekStartsMonday;

  @override
  Widget build(BuildContext context) {
    final offset = weekStartsMonday
        ? selected.weekday - 1
        : selected.weekday % 7;
    final start = DateTime(selected.year, selected.month, selected.day - offset);
    final today = dayStart(DateTime.now());
    final scheme = context.scheme;
    final palette = context.palette;
    final text = context.text;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final date = DateTime(start.year, start.month, start.day + i);
                final isSelected = sameDay(date, selected);
                final isToday = sameDay(date, today);
                final active = hasActivity(date);
                return Pressable(
                  scale: 0.92,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  onTap: () => onSelect(date),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('E').format(date).substring(0, 1),
                          style: text.labelSmall?.copyWith(
                            color: palette.dimText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: Motion.base,
                          curve: Motion.out,
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? scheme.primary : Colors.transparent,
                            border: isToday && !isSelected
                                ? Border.all(color: scheme.primary, width: 1.5)
                                : null,
                          ),
                          child: Text(
                            '${date.day}',
                            style: text.bodyMedium?.copyWith(
                              fontFeatures: tabularFigures,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: Motion.base,
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active ? scheme.primary : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

String _ago(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${relativeDayLabel(at)}, ${formatTime(at)}';
}

/// The most recent play. This app only learns about a track after it is
/// scrobbled, so it says "just played" rather than claiming to know what is
/// playing right now.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key, required this.scrobble, required this.onTap});

  final MusicScrobble scrobble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final recent = DateTime.now().difference(scrobble.playedAt).inMinutes < 5;
    return QuietCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          Artwork(
            url: scrobble.artworkUrl,
            size: 64,
            radius: 14,
            seed: scrobble.displayArtist,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Equalizer(color: palette.music, size: 12, active: recent),
                    const SizedBox(width: 6),
                    Text(
                      recent ? 'Just played' : 'Last played',
                      style: text.labelSmall?.copyWith(
                        color: palette.music,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _ago(scrobble.playedAt),
                      style: text.labelSmall?.copyWith(color: palette.dimText),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  scrobble.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                Text(
                  scrobble.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// For days other than today: overlapping artwork of the most played artists
/// and a one-line summary.
class DayListeningCard extends StatelessWidget {
  const DayListeningCard({super.key, required this.summary, required this.onTap});

  final MusicDaySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final shown = summary.topArtists.take(3).toList();
    String? artFor(String artist) {
      for (final s in summary.scrobbles) {
        if (s.displayArtist == artist && Artwork.usable(s.artworkUrl)) {
          return s.artworkUrl;
        }
      }
      return null;
    }

    return QuietCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          SizedBox(
            width: 44.0 + (shown.length - 1) * 26,
            height: 44,
            child: Stack(
              children: [
                for (var i = shown.length - 1; i >= 0; i--)
                  Positioned(
                    left: i * 26.0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.card, width: 2),
                      ),
                      child: Artwork(
                        url: artFor(shown[i].name),
                        size: 44,
                        circle: true,
                        seed: shown[i].name,
                      ),
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
                Text('Listening', style: text.titleSmall),
                Text(
                  '${summary.total} ${plural(summary.total, 'track')}, '
                  '${summary.uniqueArtists} ${plural(summary.uniqueArtists, 'artist')}',
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.dimText),
        ],
      ),
    );
  }
}
