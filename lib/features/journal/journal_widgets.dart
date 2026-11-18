import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import '../photos/photo_widgets.dart';
import 'journal_editor_screen.dart';

/// One entry as a small piece of the day's story: when it was written, what
/// was said, and, directly beneath, the moments that belong to it.
class JournalEntryCard extends ConsumerWidget {
  const JournalEntryCard({
    super.key,
    required this.entry,
    this.showDate = true,
    this.compact = false,
    this.showActions = true,
    this.heroScope = 'journal',
  });

  final JournalEntry entry;
  final bool showDate;
  final bool compact;
  final bool showActions;

  /// Distinguishes this card's media hero tags from other screens'.
  final String heroScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider);
    final media = archive.mediaForEntry(entry.id);
    final palette = context.palette;
    final text = context.text;
    final when = showDate
        ? '${formatShortDate(entry.createdAt)}, ${formatTime(entry.createdAt)}'
        : formatTime(entry.createdAt);

    return QuietCard(
      margin: const EdgeInsets.only(bottom: Insets.md),
      padding: EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.md,
        showActions ? Insets.sm : Insets.lg,
        compact ? Insets.md : Insets.lg,
      ),
      onTap: () => openJournalEntry(context, entry.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                when,
                style: text.labelMedium?.copyWith(color: palette.mutedText),
              ),
              if (entry.kind != JournalEntryKind.journal) ...[
                const SizedBox(width: Insets.sm),
                SourceChip(
                  label: entry.kind.label,
                  dense: true,
                  color: entry.isVocab ? palette.tracker : palette.place,
                ),
              ],
              if (entry.draft) ...[
                const SizedBox(width: Insets.sm),
                SourceChip(
                  label: 'Draft',
                  dense: true,
                  color: context.scheme.secondary,
                ),
              ],
              if (entry.archived) ...[
                const SizedBox(width: Insets.sm),
                SourceChip(
                  label: 'Archived',
                  dense: true,
                  color: palette.manual,
                ),
              ],
              const Spacer(),
              if (entry.mood != null) MoodBadge(entry.mood!),
              if (showActions)
                _EntryMenu(entry: entry)
              else
                const SizedBox(height: 32),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Padding(
            padding: EdgeInsets.only(right: showActions ? Insets.md : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    text.headlineSmall,
                    size: compact ? 18 : 20,
                  ),
                ),
                if (entry.isVocab && entry.hasVocabContent) ...[
                  const SizedBox(height: Insets.xs),
                  _VocabPreview(items: entry.vocabItems, compact: compact),
                ] else if (entry.excerpt != 'No text') ...[
                  const SizedBox(height: Insets.xs),
                  Text(
                    entry.excerpt,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      text.bodyMedium,
                      size: 15,
                    ).copyWith(color: palette.mutedText, height: 1.55),
                  ),
                ],
              ],
            ),
          ),
          if (entry.energy != null ||
              entry.sleepHours != null ||
              entry.steps != null ||
              entry.meals.trim().isNotEmpty ||
              entry.highlight.trim().isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (entry.energy != null)
                  _MetaChip(
                    icon: Icons.bolt_rounded,
                    label: 'Energy ${entry.energy}/5',
                    color: palette.tracker,
                  ),
                if (entry.sleepHours != null)
                  _MetaChip(
                    icon: Icons.bedtime_outlined,
                    label: '${_fmtNum(entry.sleepHours!)}h sleep',
                    color: palette.place,
                  ),
                if (entry.steps != null)
                  _MetaChip(
                    icon: Icons.directions_walk_rounded,
                    label: '${entry.steps} steps',
                    color: palette.music,
                  ),
                if (entry.meals.trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.restaurant_outlined,
                    label: _shortText(entry.meals),
                    color: palette.journal,
                  ),
                if (entry.highlight.trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.wb_sunny_outlined,
                    label: _shortText(entry.highlight),
                    color: palette.photo,
                  ),
              ],
            ),
          ],
          if (media.isNotEmpty) ...[
            const SizedBox(height: Insets.md),
            StoryStrip(
              items: media,
              scope: '$heroScope:${entry.id}',
              height: compact ? 104 : 128,
            ),
          ],
          if (entry.placeLabel != null || entry.tags.isNotEmpty) ...[
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.md,
              runSpacing: Insets.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (entry.placeLabel != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.place_outlined, size: 14, color: palette.place),
                      const SizedBox(width: 3),
                      Text(
                        entry.placeLabel!,
                        style: text.labelMedium?.copyWith(
                          color: palette.mutedText,
                        ),
                      ),
                    ],
                  ),
                for (final tag in entry.tags.take(4))
                  Text(
                    '#$tag',
                    style: text.labelMedium?.copyWith(color: palette.dimText),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryMenu extends ConsumerWidget {
  const _EntryMenu({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Entry actions',
      padding: EdgeInsets.zero,
      iconSize: 20,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      icon: Icon(Icons.more_horiz_rounded, color: context.palette.dimText),
      onSelected: (value) async {
        if (value == 'open') {
          await openJournalEntry(context, entry.id);
        } else if (value == 'archive') {
          await guard(
            context,
            ref.read(archiveProvider.notifier).archiveEntry(entry.id),
            errorPrefix: 'Could not update entry',
          );
        } else if (value == 'duplicate') {
          await guard(
            context,
            ref.read(archiveProvider.notifier).duplicateEntry(entry),
            errorPrefix: 'Could not duplicate entry',
          );
          if (context.mounted) showSnack(context, 'Duplicated as a new draft.');
        } else if (value == 'delete') {
          final ok = await confirm(
            context,
            title: 'Delete this entry?',
            message:
                'The entry and its encrypted attachments will be permanently removed.',
          );
          if (ok) {
            if (!context.mounted) return;
            await guard(
              context,
              ref.read(archiveProvider.notifier).deleteEntry(entry.id),
              errorPrefix: 'Could not delete entry',
            );
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate as draft')),
        PopupMenuItem(
          value: 'archive',
          child: Text(entry.archived ? 'Restore' : 'Archive'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

Future<void> openJournalEntry(BuildContext context, String entryId) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JournalEditorScreen(entryId: entryId),
    ),
  );
}

/// Opens a journal entry for [date] (or today). Multiple entries per day are
/// supported and grouped together by day. By default this resumes the day's
/// primary/check-in entry if one exists; pass [createNew] to always start a new
/// entry in that day's folder.
Future<void> createJournalEntry(
  BuildContext context, {
  DateTime? date,
  bool focusBody = false,
  bool createNew = false,
  JournalEntryKind kind = JournalEntryKind.journal,
}) async {
  final targetDay = date ?? DateTime.now();
  if (!createNew) {
    final archive = ProviderScope.containerOf(context).read(archiveProvider);
    final existing = archive.dailyEntryFor(targetDay);
    if (existing != null) {
      await openJournalEntry(context, existing.id);
      return;
    }
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JournalEditorScreen(
        initialDate: targetDay,
        focusBody: focusBody,
        initialKind: kind,
      ),
    ),
  );
}

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(v * 10 % 10 == 0 ? 1 : 2);
}

String _shortText(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= 28) return t;
  return '${t.substring(0, 27)}...';
}

class _VocabPreview extends StatelessWidget {
  const _VocabPreview({required this.items, this.compact = false});

  final List<VocabItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final pairs = items.where((v) => !v.isEmpty).take(compact ? 2 : 3).toList();
    final total = items.where((v) => !v.isEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in pairs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.translate_rounded, size: 14, color: palette.tracker),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.meaning.trim().isEmpty
                        ? item.term.trim()
                        : '${item.term.trim()}  —  ${item.meaning.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: palette.mutedText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (total > pairs.length)
          Text(
            '+${total - pairs.length} more ${plural(total - pairs.length, 'word')}',
            style: text.labelSmall?.copyWith(color: palette.dimText),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: palette.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DraftRecoveryBanner extends ConsumerWidget {
  const DraftRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(archiveProvider).drafts;
    if (drafts.isEmpty) return const SizedBox.shrink();
    final scheme = context.scheme;
    final first = drafts.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Pressable(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () => openJournalEntry(context, first.id),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.md,
          ),
          decoration: BoxDecoration(
            color: scheme.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 20, color: scheme.secondary),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  drafts.length == 1
                      ? 'Unfinished: ${first.displayTitle}'
                      : '${drafts.length} unfinished drafts',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'Resume',
                style: context.text.labelLarge?.copyWith(color: scheme.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
