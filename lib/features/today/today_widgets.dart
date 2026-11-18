import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/music.dart';

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour < 5) return 'Late night';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Two colours that follow the hour: dawn, day, golden hour, dusk, night.
List<Color> dayGlowColors(DateTime now) {
  final h = now.hour + now.minute / 60;
  if (h < 5 || h >= 22) return const [Color(0xFF4B55C8), Color(0xFF1B1F4A)];
  if (h < 9) return const [Color(0xFFFFA97A), Color(0xFFF6C7E0)];
  if (h < 16) return const [Color(0xFF7DB6FF), Color(0xFFBFE0FF)];
  if (h < 19.5) return const [Color(0xFFFFB35E), Color(0xFFFF9EC4)];
  return const [Color(0xFF8A78FF), Color(0xFF4A3C9C)];
}

/// A soft wash behind the Today header. For today it follows the time of
/// day; for any other day it is a quiet tint of the brand colour.
class TodayGlow extends StatelessWidget {
  const TodayGlow({super.key, required this.isToday});

  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final colors = isToday
        ? dayGlowColors(DateTime.now())
        : [context.scheme.primary, context.scheme.primary];
    final strength = dark ? 0.26 : 0.34;
    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: Motion.slow,
        height: 320,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.7, -1.15),
            radius: 1.25,
            colors: [
              colors[0].withValues(alpha: isToday ? strength : strength * 0.5),
              colors[1].withValues(alpha: isToday ? strength * 0.45 : strength * 0.2),
              Colors.transparent,
            ],
            stops: const [0, 0.55, 1],
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
    this.onAdd,
  });

  final DateTime day;
  final int streak;
  final bool calendarOpen;
  final VoidCallback onToggleCalendar;
  final VoidCallback onSearch;
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
              ],
            ),
          ),
          if (streak >= 2)
            Tooltip(
              message: '$streak days in a row with something recorded',
              child: Container(
                margin: const EdgeInsets.only(right: Insets.xs, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.scheme.secondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: context.scheme.secondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$streak',
                      style: text.labelLarge?.copyWith(
                        color: context.scheme.secondary,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
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
                if (onAdd != null)
                  HeaderButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Add',
                    onPressed: onAdd,
                    filled: true,
                  ),
              ],
            ),
          ),
        ],
      ),
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

class ComposerCard extends StatelessWidget {
  const ComposerCard({
    super.key,
    required this.onTap,
    required this.isToday,
    this.entry,
  });

  final VoidCallback onTap;
  final bool isToday;
  final JournalEntry? entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final e = entry;
    final hasCheckin = e != null &&
        (e.mood != null ||
            e.energy != null ||
            e.sleepHours != null ||
            e.steps != null ||
            e.meals.trim().isNotEmpty ||
            e.highlight.trim().isNotEmpty);
    return QuietCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.tracker.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.favorite_border_rounded,
                  size: 18,
                  color: palette.tracker,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  hasCheckin
                      ? (isToday ? 'Daily check-in' : 'This day\'s check-in')
                      : (isToday ? 'How was your day?' : 'Log this day'),
                  style: AppTheme.serif(text.bodyLarge, size: 16).copyWith(
                    color: hasCheckin ? text.bodyLarge?.color : palette.mutedText,
                    fontWeight: hasCheckin ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                hasCheckin ? 'Edit' : 'Start',
                style: text.labelMedium?.copyWith(color: palette.tracker),
              ),
            ],
          ),
          if (e != null && hasCheckin) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.xs,
              children: [
                if (e.mood != null) _checkChip(context, Icons.sentiment_satisfied_alt_rounded, e.mood!.label, palette.journal),
                if (e.energy != null) _checkChip(context, Icons.bolt_rounded, 'Energy ${e.energy}/5', palette.tracker),
                if (e.sleepHours != null) _checkChip(context, Icons.bedtime_outlined, '${_fmt(e.sleepHours!)}h sleep', palette.place),
                if (e.steps != null) _checkChip(context, Icons.directions_walk_rounded, '${e.steps} steps', palette.music),
                if (e.meals.trim().isNotEmpty) _checkChip(context, Icons.restaurant_outlined, _short(e.meals), palette.photo),
              ],
            ),
          ],
          if (e != null && e.highlight.trim().isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Text(
              e.highlight,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: palette.mutedText, height: 1.5),
            ),
          ] else if (!hasCheckin) ...[
            const SizedBox(height: 4),
            Text(
              isToday
                  ? 'Sleep, steps, meals, mood, energy and more — all optional.'
                  : 'Add sleep, steps, meals, mood and notes for this day.',
              style: text.bodySmall?.copyWith(color: palette.dimText),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
  }

  static String _short(String t) {
    final s = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= 22 ? s : '${s.substring(0, 21)}...';
  }

  static Widget _checkChip(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.palette.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class JournalWriteCard extends StatelessWidget {
  const JournalWriteCard({
    super.key,
    required this.onTap,
    required this.isToday,
    this.entry,
    this.entryCount = 0,
    this.onAdd,
  });

  final VoidCallback onTap;
  final bool isToday;
  final JournalEntry? entry;
  final int entryCount;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final e = entry;
    final hasWriting = e != null &&
        (e.title.trim().isNotEmpty ||
            e.body.trim().isNotEmpty ||
            e.hasVocabContent);
    final multiple = entryCount > 1;
    final title = multiple
        ? '${isToday ? 'Today' : 'This day'} · $entryCount entries'
        : hasWriting
            ? (isToday ? 'Journal' : 'Journal entry')
            : (isToday ? 'Write about today' : 'Write about this day');
    final subtitle = multiple
        ? 'Entries, notes, and vocab lists kept together for this day.'
        : hasWriting
            ? (e.excerpt == 'No text' ? e.displayTitle : e.excerpt)
            : 'Thoughts, notes, or a simple vocab list.';

    return QuietCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.journal.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              multiple ? Icons.folder_outlined : Icons.edit_note_rounded,
              size: 20,
              color: palette.journal,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.serif(text.bodyLarge, size: 16).copyWith(
                    color: (hasWriting || multiple)
                        ? text.bodyLarge?.color
                        : palette.mutedText,
                    fontWeight: (hasWriting || multiple)
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: (hasWriting || multiple)
                        ? palette.mutedText
                        : palette.dimText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (onAdd != null)
            IconButton(
              tooltip: 'Add another entry',
              onPressed: onAdd,
              icon: Icon(Icons.add_circle_outline_rounded,
                  color: palette.journal),
            )
          else
            Icon(Icons.chevron_right_rounded, color: palette.dimText),
        ],
      ),
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
