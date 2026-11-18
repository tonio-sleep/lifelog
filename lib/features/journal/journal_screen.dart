import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/journal.dart';
import 'journal_widgets.dart';

enum _JournalFilter { active, drafts, archived }

int _words(String text) => RegExp(r'\S+').allMatches(text).length;

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final _search = TextEditingController();
  _JournalFilter _filter = _JournalFilter.active;
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _filterLabel => switch (_filter) {
    _JournalFilter.active => 'journal',
    _JournalFilter.drafts => 'drafts',
    _JournalFilter.archived => 'archive',
  };

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;

    final all = [...archive.entries]
      ..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.updatedAt.compareTo(a.updatedAt);
      });

    final filtered = all.where((entry) {
      switch (_filter) {
        case _JournalFilter.active:
          if (entry.draft || entry.archived) return false;
        case _JournalFilter.drafts:
          if (!entry.draft || entry.archived) return false;
        case _JournalFilter.archived:
          if (!entry.archived) return false;
      }
      if (_query.isEmpty) return true;
      final haystack = [
        entry.title,
        entry.body,
        entry.placeLabel ?? '',
        entry.tags.join(' '),
        entry.mood?.label ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(_query);
    }).toList();

    // One entry per day (daily log). Prefer the primary/daily entry for each day.
    final byDay = <String, JournalEntry>{};
    for (final entry in filtered) {
      final key = dayKey(entry.createdAt);
      final existing = byDay[key];
      if (existing == null) {
        byDay[key] = entry;
      } else {
        // pick better representative: non-draft over draft, then newer update
        int rank(JournalEntry e) => e.draft ? 1 : 0;
        final r = rank(entry).compareTo(rank(existing));
        if (r < 0 || (r == 0 && entry.updatedAt.isAfter(existing.updatedAt))) {
          byDay[key] = entry;
        }
      }
    }
    final dailyEntries = byDay.entries.toList()
      ..sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));

    final rows = <Object>[];
    for (final e in dailyEntries) {
      rows.add(e.key);
      rows.add(e.value);
    }

    final wordCount = all.fold<int>(0, (sum, entry) => sum + _words(entry.body));
    final dayCount = archive.entries.where((e) => !e.draft && !e.archived).map((e) => dayKey(e.createdAt)).toSet().length;

    return ScreenFrame(
      title: 'Journal',
      subtitle: dayCount == 0
          ? null
          : '$dayCount ${plural(dayCount, 'day')} · ${formatCompactNumber(wordCount)} ${plural(wordCount, 'word')}',
      actions: [
        HeaderButton(
          icon: _searching ? Icons.search_off_rounded : Icons.search_rounded,
          tooltip: _searching ? 'Close search' : 'Search',
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) {
              _search.clear();
              _query = '';
            }
          }),
        ),
        HeaderButton(
          icon: Icons.edit_rounded,
          tooltip: 'Write today',
          filled: true,
          onPressed: () => createJournalEntry(context, focusBody: true),
        ),
      ],
      children: [
        const DraftRecoveryBanner(),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.out,
          alignment: Alignment.topCenter,
          child: !_searching
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search writing, tags and places',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  ),
                ),
        ),
        FilterRow<_JournalFilter>(
          values: _JournalFilter.values,
          selected: _filter,
          labelFor: (value) => switch (value) {
            _JournalFilter.active => 'Entries',
            _JournalFilter.drafts => 'Drafts',
            _JournalFilter.archived => 'Archive',
          },
          onChanged: (value) => setState(() => _filter = value),
        ),
        if (filtered.isEmpty)
          EmptyState(
            icon: _query.isEmpty
                ? Icons.menu_book_outlined
                : Icons.search_off_rounded,
            title: _query.isEmpty
                ? switch (_filter) {
                    _JournalFilter.active => 'No entries yet',
                    _JournalFilter.drafts => 'No drafts waiting',
                    _JournalFilter.archived => 'Nothing archived',
                  }
                : 'No matches',
            message: _query.isEmpty
                ? 'Start with a sentence. Moods, places and photos can come later.'
                : 'Nothing in the $_filterLabel matches “$_query”.',
            actionLabel: _query.isEmpty && _filter == _JournalFilter.active
                ? 'Write an entry'
                : null,
            onAction: _query.isEmpty && _filter == _JournalFilter.active
                ? () => createJournalEntry(context, focusBody: true)
                : null,
          ),
      ],
      slivers: [
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is String) {
              final day = parseDayKey(row);
              return Padding(
                padding: const EdgeInsets.only(
                  top: Insets.lg,
                  bottom: Insets.sm,
                  left: Insets.xs,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      relativeDayLabel(day),
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      formatDayHeader(day),
                      style: context.text.labelSmall?.copyWith(
                        color: palette.dimText,
                      ),
                    ),
                  ],
                ),
              );
            }
            final card = JournalEntryCard(
              key: ValueKey((row as JournalEntry).id),
              entry: row,
              showDate: false,
            );
            return revealAt(index, card, limit: 6);
          },
        ),
      ],
    );
  }
}
