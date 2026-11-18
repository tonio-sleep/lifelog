import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/media.dart';
import '../../domain/models/timeline.dart';
import '../../domain/timeline_builder.dart';
import '../journal/journal_editor_screen.dart';
import '../music/music_screen.dart';
import '../photos/photo_widgets.dart';
import '../places/place_dialogs.dart';
import '../trackers/tracker_detail_screen.dart';
import 'event_dialogs.dart';

/// One day as a quiet vertical timeline: a time, a coloured dot, and the
/// record itself. Photos and music carry their own thumbnails.
class TimelineDayList extends ConsumerWidget {
  const TimelineDayList({
    super.key,
    required this.day,
    this.emptyMessage,
    this.compact = false,
    this.maxItems,
    this.showEmptyAction = true,
    this.sources,
    this.includeHidden = false,
  });

  final DateTime day;
  final String? emptyMessage;
  final bool compact;
  final int? maxItems;
  final bool showEmptyAction;
  final Set<TimelineSource>? sources;
  final bool includeHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    var items = buildTimelineForDay(archive, day, includeHidden: includeHidden);
    if (sources != null) {
      items = items.where((item) => sources!.contains(item.source)).toList();
    }
    if (maxItems != null && items.length > maxItems!) {
      items = items.sublist(items.length - maxItems!);
    }
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.timeline_rounded,
        title: 'Nothing recorded',
        message:
            emptyMessage ?? 'Gaps stay gaps. Add something when you want to.',
        actionLabel: showEmptyAction ? 'Add an event' : null,
        onAction: showEmptyAction
            ? () => showTimelineEventEditor(context, ref, initialDate: day)
            : null,
        compact: compact,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          _TimelineRow(
            item: items[index],
            first: index == 0,
            last: index == items.length - 1,
            compact: compact,
          ),
      ],
    );
  }
}

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({
    required this.item,
    required this.first,
    required this.last,
    required this.compact,
  });

  final TimelineItem item;
  final bool first;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final scheme = context.scheme;
    final text = context.text;
    final archive = ref.watch(archiveProvider);
    final style = sourceStyle(item.source, scheme);
    final hasSubtitle = item.subtitle.trim().isNotEmpty;

    TimelineEvent? manualEvent;
    if (item.source == TimelineSource.manual && item.sourceId != null) {
      for (final candidate in archive.events) {
        if (candidate.id == item.sourceId) {
          manualEvent = candidate;
          break;
        }
      }
    }

    MediaItem? media;
    if (item.source == TimelineSource.photo && item.sourceId != null) {
      media = archive.mediaById(item.sourceId!);
    }
    final artwork = item.source == TimelineSource.music
        ? item.metadata['artwork']
        : null;

    Widget? leading;
    if (media != null && media.isImage) {
      leading = SizedBox(
        width: compact ? 48 : 56,
        height: compact ? 48 : 56,
        child: EncryptedImage(
          item: media,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      );
    } else if (item.source == TimelineSource.music) {
      leading = Artwork(
        url: artwork,
        size: compact ? 44 : 52,
        radius: Radii.sm,
        seed: item.title,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: EdgeInsets.only(top: compact ? 11 : 13),
              child: Text(
                formatTime(item.at),
                textAlign: TextAlign.right,
                style: text.labelSmall?.copyWith(
                  color: palette.mutedText,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                SizedBox(
                  height: compact ? 14 : 16,
                  child: Container(
                    width: 1.5,
                    color: first ? Colors.transparent : palette.border,
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: style.color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: last ? Colors.transparent : palette.border,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Pressable(
              borderRadius: BorderRadius.circular(Radii.md),
              scale: 0.99,
              onTap: () => _open(context, ref, manualEvent),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 8 : 10,
                  horizontal: Insets.sm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (leading != null) ...[
                      leading,
                      const SizedBox(width: Insets.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (leading == null) ...[
                                Icon(style.icon, size: 15, color: style.color),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: compact ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall,
                                ),
                              ),
                              if (item.confidence ==
                                  TimelineConfidence.suggested)
                                Text(
                                  'Suggested',
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          if (hasSubtitle) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              maxLines: compact ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: palette.mutedText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (manualEvent != null)
                      _EventMenu(event: manualEvent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    TimelineEvent? event,
  ) async {
    switch (item.source) {
      case TimelineSource.journal:
        if (item.sourceId == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => JournalEditorScreen(entryId: item.sourceId),
          ),
        );
      case TimelineSource.tracker:
        final trackerId = item.metadata['trackerId'];
        if (trackerId == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackerDetailScreen(trackerId: trackerId),
          ),
        );
      case TimelineSource.location:
        final visitId = item.metadata['visitId'];
        if (visitId == null) return;
        final visit = ref.read(archiveProvider).visitById(visitId);
        if (visit == null) return;
        await showVisitEditor(context, ref, existing: visit, day: visit.startAt);
      case TimelineSource.photo:
        if (item.sourceId == null) return;
        final media = ref.read(archiveProvider).mediaById(item.sourceId!);
        if (media == null) return;
        await showMediaViewer(context, ref, media, heroScope: 'timeline');
      case TimelineSource.music:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => MusicScreen(day: item.at)),
        );
      case TimelineSource.manual:
        await showTimelineEventEditor(
          context,
          ref,
          existing: event,
          initialDate: item.at,
        );
    }
  }
}

class _EventMenu extends ConsumerWidget {
  const _EventMenu({required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Event actions',
      padding: EdgeInsets.zero,
      iconSize: 18,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(Icons.more_horiz_rounded, color: context.palette.dimText),
      onSelected: (value) async {
        if (value == 'edit') {
          await showTimelineEventEditor(context, ref, existing: event);
        } else if (value == 'hide') {
          await guard(
            context,
            ref.read(archiveProvider.notifier).toggleEventHidden(event.id),
            errorPrefix: 'Could not update event',
          );
        } else if (value == 'delete') {
          final ok = await confirm(
            context,
            title: 'Delete this event?',
            message: 'The event will be permanently removed from your archive.',
          );
          if (ok) {
            if (!context.mounted) return;
            await guard(
              context,
              ref.read(archiveProvider.notifier).deleteEvent(event.id),
              errorPrefix: 'Could not delete event',
            );
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
          value: 'hide',
          child: Text(event.hidden ? 'Show again' : 'Hide from timeline'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
