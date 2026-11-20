import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/memories.dart';
import '../journal/journal_widgets.dart';
import '../photos/photo_widgets.dart';
import '../photos/photos_screen.dart';
import '../timeline/event_dialogs.dart';
import 'calendar.dart';
import 'day_detail_screen.dart';

void _openDay(BuildContext context, DateTime day) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DayDetailScreen(day: day)),
  );
}

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = dayStart(DateTime.now());
    _month = DateTime(now.year, now.month, 1);
    _selected = now;
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final text = context.text;
    final summary = DaySummary.of(archive, _selected);
    final memories = onThisDay(archive, DateTime.now());
    final recentPhotos = [...archive.media]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final monthDays = activeDaysInPreviousYears(archive, _selected);

    final counts = <({IconData icon, int count, Color color})>[
      (icon: Icons.menu_book_rounded, count: summary.entries.length, color: palette.journal),
      (icon: Icons.photo_rounded, count: summary.photos.length, color: palette.photo),
      (icon: Icons.place_rounded, count: summary.visits.length, color: palette.place),
      (icon: Icons.graphic_eq_rounded, count: summary.scrobbles.length, color: palette.music),
      (icon: Icons.task_alt_rounded, count: summary.trackerRecords.length, color: palette.tracker),
      (icon: Icons.restaurant_outlined, count: summary.meals.length, color: palette.tracker),
    ].where((c) => c.count > 0).toList();

    return ScreenFrame(
      title: 'Memories',
      actions: [
        HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'Add event',
          onPressed: () =>
              showTimelineEventEditor(context, ref, initialDate: _selected),
        ),
      ],
      children: [
        if (memories.isNotEmpty) ...[
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: memories.length.clamp(0, 6),
              separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
              itemBuilder: (context, index) =>
                  _MemoryCard(memory: memories[index]),
            ),
          ),
          const SizedBox(height: Insets.lg),
        ],
        QuietCard(
          padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, Insets.md),
          child: MonthCalendar(
            month: _month,
            selectedDay: _selected,
            onSelect: (day) => setState(() => _selected = day),
            onMonthChanged: (month) => setState(() => _month = month),
          ),
        ),
        const SizedBox(height: Insets.md),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: QuietCard(
            key: ValueKey<int>(_selected.millisecondsSinceEpoch),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            relativeDayLabel(_selected),
                            style: AppTheme.serif(text.headlineSmall),
                          ),
                          Text(
                            formatDayLong(_selected),
                            style: text.labelMedium?.copyWith(color: palette.mutedText),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openDay(context, _selected),
                      child: const Text('Open'),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                if (summary.isEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Nothing recorded.',
                          style: text.bodyMedium?.copyWith(color: palette.mutedText),
                        ),
                      ),
                      TextButton(
                        onPressed: () => createJournalEntry(
                          context,
                          date: _selected,
                          focusBody: true,
                        ),
                        child: const Text('Write about it'),
                      ),
                    ],
                  )
                else ...[
                  Wrap(
                    spacing: Insets.lg,
                    runSpacing: Insets.sm,
                    children: [
                      for (final c in counts)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(c.icon, size: 16, color: c.color),
                            const SizedBox(width: 5),
                            Text(
                              '${c.count}',
                              style: text.labelLarge?.copyWith(fontFeatures: tabularFigures),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (summary.entries.isNotEmpty) ...[
                    const SizedBox(height: Insets.md),
                    Text(
                      summary.entries.first.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(text.bodyLarge, size: 16).copyWith(height: 1.4),
                    ),
                  ],
                  if (summary.photos.isNotEmpty) ...[
                    const SizedBox(height: Insets.md),
                    StoryStrip(
                      items: summary.photos,
                      scope: 'memories',
                      height: 104,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        if (monthDays.isNotEmpty) ...[
          SectionHeader(
            title: 'Same date, other years',
            padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: monthDays.take(10).length,
              separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
              itemBuilder: (context, index) {
                final day = monthDays[index];
                return ActionChip(
                  label: Text('${formatShortDate(day.day)}, ${day.day.year}'),
                  onPressed: () => _openDay(context, day.day),
                );
              },
            ),
          ),
        ],
        if (recentPhotos.isNotEmpty) ...[
          SectionHeader(
            title: 'Recent media',
            actionLabel: 'See all',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PhotosScreen()),
            ),
          ),
          StoryStrip(
            items: recentPhotos.take(10).toList(),
            scope: 'memories-recent',
            height: 112,
          ),
        ],
      ],
    );
  }
}

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({required this.memory});

  final OnThisDayMemory memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = memory.summary.photos.where((p) => p.isImage).toList();
    final primary = context.scheme.primary;
    final music = context.palette.music;
    return Pressable(
      borderRadius: BorderRadius.circular(Radii.xl),
      scale: 0.98,
      onTap: () => _openDay(context, memory.day),
      child: Container(
        width: 288,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, Color.lerp(primary, music, 0.7)!],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isNotEmpty)
              EncryptedImage(
                item: photos.first,
                borderRadius: BorderRadius.zero,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: photos.isEmpty ? 0.0 : 0.05),
                    Colors.black.withValues(alpha: 0.62),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.relativeLabel,
                    style: context.text.labelMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    memory.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(context.text.titleMedium, size: 18)
                        .copyWith(color: Colors.white, height: 1.3),
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
