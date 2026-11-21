import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/journal.dart';
import '../memories/day_detail_screen.dart';
import 'journal_widgets.dart';

enum _JournalFilter { active, drafts, archived }

const _faces = <String>[
  '😖',
  '😞',
  '😟',
  '😕',
  '😐',
  '🙂',
  '😊',
  '😄',
  '😁',
  '🤩',
];
String _face(int mood) => _faces[mood.clamp(1, 10) - 1];

int _words(String text) => RegExp(r'\S+').allMatches(text).length;

bool _metricsOnly(JournalEntry e) {
  if (e.title.trim().isNotEmpty ||
      e.body.trim().isNotEmpty ||
      e.hasVocabContent ||
      e.highlight.trim().isNotEmpty ||
      e.mood != null ||
      e.energy != null) {
    return false;
  }
  return e.sleepHours != null || e.steps != null || e.meals.trim().isNotEmpty;
}

/// Everything shown for one day in the list.
class _DayData {
  _DayData(this.key) : day = parseDayKey(key);

  final String key;
  final DateTime day;
  final List<JournalEntry> entries = [];
  int photos = 0;
  int meals = 0;
  int songs = 0;

  List<JournalEntry> get writing =>
      entries.where((e) => !e.isCheckinEntry && !_metricsOnly(e)).toList();
  List<JournalEntry> get checkins =>
      entries.where((e) => e.isCheckinEntry).toList();

  int? get mood {
    final moods = entries.where((e) => e.mood != null).toList();
    if (moods.isEmpty) return null;
    final total = moods.fold<int>(0, (s, e) => s + e.mood!);
    return (total / moods.length).round().clamp(1, 10);
  }
}

class _MonthRow {
  const _MonthRow(this.month, this.days);
  final DateTime month;
  final int days;
}

class _JournalView {
  const _JournalView({
    required this.rows,
    required this.data,
    required this.wordCount,
    required this.dayCount,
    required this.entryCount,
  });

  /// Month headers interleaved with day keys, newest first.
  final List<Object> rows;
  final Map<String, _DayData> data;
  final int wordCount;
  final int dayCount;
  final int entryCount;

  factory _JournalView.build(
    Archive archive,
    _JournalFilter filter,
    String query,
  ) {
    final all = [...archive.entries];

    final filtered = all.where((entry) {
      switch (filter) {
        case _JournalFilter.active:
          if (entry.archived) return false;
        case _JournalFilter.drafts:
          if (!entry.draft || entry.archived) return false;
        case _JournalFilter.archived:
          if (!entry.archived) return false;
      }
      if (query.isEmpty) return true;
      final vocab = entry.vocabItems
          .map((v) => '${v.term} ${v.meaning}')
          .join(' ');
      final haystack = [
        entry.title,
        entry.body,
        vocab,
        entry.placeLabel ?? '',
        entry.tags.join(' '),
        entry.mood == null ? '' : MoodScore.label(entry.mood!),
        entry.kind.label,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final data = <String, _DayData>{};
    _DayData dayFor(DateTime at) =>
        data.putIfAbsent(dayKey(at), () => _DayData(dayKey(at)));

    for (final entry in filtered) {
      dayFor(entry.createdAt).entries.add(entry);
    }

    // The plain journal lists every day with anything recorded, so days with
    // only photos, meals or music are not missing.
    final showAll = filter == _JournalFilter.active && query.isEmpty;
    if (showAll) {
      for (final m in archive.media) {
        dayFor(m.createdAt).photos++;
      }
      for (final m in archive.meals) {
        dayFor(m.at).meals++;
      }
      for (final s in archive.scrobbles) {
        dayFor(s.playedAt).songs++;
      }
      for (final v in archive.visits) {
        dayFor(v.startAt);
      }
      for (final e in archive.events) {
        if (!e.hidden) dayFor(e.occurredAt);
      }
      for (final r in archive.trackerRecords) {
        dayFor(r.recordedAt);
      }
    }

    final keys = data.keys.toList()..sort((a, b) => b.compareTo(a));
    final monthCounts = <String, int>{};
    for (final key in keys) {
      final m = key.length >= 7 ? key.substring(0, 7) : key;
      monthCounts[m] = (monthCounts[m] ?? 0) + 1;
    }
    final rows = <Object>[];
    String? lastMonth;
    for (final key in keys) {
      final m = key.length >= 7 ? key.substring(0, 7) : key;
      if (m != lastMonth) {
        rows.add(_MonthRow(parseDayKey(key), monthCounts[m] ?? 0));
        lastMonth = m;
      }
      rows.add(key);
    }

    final wordCount = all.fold<int>(
      0,
      (sum, e) =>
          sum +
          _words(e.body) +
          e.vocabItems.fold<int>(
            0,
            (s, v) => s + _words(v.term) + _words(v.meaning),
          ),
    );
    final published = archive.entries.where((e) => !e.archived).toList();
    return _JournalView(
      rows: rows,
      data: data,
      wordCount: wordCount,
      dayCount: published.map((e) => dayKey(e.createdAt)).toSet().length,
      entryCount: published.length,
    );
  }
}

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

  Archive? _viewArchive;
  _JournalFilter? _viewFilter;
  String? _viewQuery;
  _JournalView? _view;

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _searching = false;
      _filter = _JournalFilter.active;
    });
  }

  _JournalView _viewFor(Archive archive) {
    final cached = _view;
    if (cached != null &&
        identical(archive, _viewArchive) &&
        _filter == _viewFilter &&
        _query == _viewQuery) {
      return cached;
    }
    _viewArchive = archive;
    _viewFilter = _filter;
    _viewQuery = _query;
    return _view = _JournalView.build(archive, _filter, _query);
  }

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

  void _openDay(DateTime day) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DayDetailScreen(day: day)));
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final view = _viewFor(archive);
    final rows = view.rows;

    final frameChildren = <Widget>[
      const DraftRecoveryBanner(),
      if (_searching)
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search writing, vocab, tags and places',
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
      FilterRow<_JournalFilter>(
        values: _JournalFilter.values,
        selected: _filter,
        labelFor: (value) => switch (value) {
          _JournalFilter.active => 'All',
          _JournalFilter.drafts => 'Drafts',
          _JournalFilter.archived => 'Archive',
        },
        onChanged: (value) => setState(() => _filter = value),
      ),
      if (rows.isEmpty)
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
              ? 'Add journal notes, quick entries, or a vocab list for any day. Entries stay grouped together by day.'
              : 'Nothing in the $_filterLabel matches "$_query".',
          actionLabel: _query.isEmpty && _filter == _JournalFilter.active
              ? 'New entry'
              : null,
          onAction: _query.isEmpty && _filter == _JournalFilter.active
              ? () => createJournalEntry(
                  context,
                  focusBody: true,
                  createNew: true,
                )
              : null,
        ),
    ];

    return ScreenFrame(
      title: 'Journal',
      subtitle: view.dayCount == 0
          ? null
          : '${view.entryCount} ${plural(view.entryCount, 'entry', 'entries')} in ${view.dayCount} ${plural(view.dayCount, 'day')} · ${formatCompactNumber(view.wordCount)} ${plural(view.wordCount, 'word')}',
      actions: [
        if (_query.isNotEmpty || _filter != _JournalFilter.active || _searching)
          HeaderButton(
            icon: Icons.filter_alt_off_outlined,
            tooltip: 'Clear filters',
            onPressed: _clearFilters,
          ),
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
          icon: Icons.note_add_outlined,
          tooltip: 'New entry for today',
          filled: true,
          onPressed: () =>
              createJournalEntry(context, focusBody: true, createNew: true),
        ),
      ],
      slivers: [
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _MonthRow) {
              return Padding(
                padding: const EdgeInsets.only(
                  top: Insets.lg,
                  bottom: Insets.sm,
                  left: Insets.xs,
                ),
                child: Row(
                  children: [
                    Text(
                      formatMonthYear(row.month),
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      '${row.days} ${plural(row.days, 'day')}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.palette.mutedText,
                      ),
                    ),
                  ],
                ),
              );
            }
            final data = view.data[row as String];
            if (data == null) return const SizedBox.shrink();
            return _DayCard(
              key: ValueKey(data.key),
              data: data,
              onOpenDay: () => _openDay(data.day),
              onAdd: () => createJournalEntry(
                context,
                date: data.day,
                createNew: true,
                focusBody: true,
              ),
            );
          },
        ),
      ],
      children: frameChildren,
    );
  }
}

/// One day: date, counts, and the day's entries listed inside it.
class _DayCard extends StatelessWidget {
  const _DayCard({
    super.key,
    required this.data,
    required this.onOpenDay,
    required this.onAdd,
  });

  final _DayData data;
  final VoidCallback onOpenDay;
  final VoidCallback onAdd;

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final day = data.day;
    final mood = data.mood;
    final accent = mood == null
        ? palette.mutedText
        : moodColor(mood, context.scheme);

    final writing = data.writing;
    final checkins = data.checkins;
    final listed = [...data.entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Pure health records are not shown as rows.
    listed.removeWhere((e) => !e.isCheckinEntry && _metricsOnly(e));
    final shown = listed.take(_maxShown).toList();
    final hidden = listed.length - shown.length;

    final chips = <Widget>[
      _Chip(
        icon: Icons.edit_note_rounded,
        color: palette.journal,
        label:
            '${writing.length} ${plural(writing.length, 'entry', 'entries')}',
        dim: writing.isEmpty,
      ),
      _Chip(
        icon: Icons.photo_outlined,
        color: palette.photo,
        label: '${data.photos} ${plural(data.photos, 'photo')}',
        dim: data.photos == 0,
      ),
      _Chip(
        icon: Icons.mood_outlined,
        color: palette.tracker,
        label: '${checkins.length} ${plural(checkins.length, 'check-in')}',
        dim: checkins.isEmpty,
      ),
      if (data.meals > 0)
        _Chip(
          icon: Icons.restaurant_outlined,
          color: palette.warning,
          label: '${data.meals} ${plural(data.meals, 'meal')}',
        ),
      if (data.songs > 0)
        _Chip(
          icon: Icons.music_note_rounded,
          color: palette.music,
          label: '${data.songs} ${plural(data.songs, 'song')}',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: QuietCard(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Pressable(
                    onTap: onOpenDay,
                    scale: 0.99,
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('EEE').format(day).toUpperCase(),
                                style: text.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${day.day}',
                                style: text.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                relativeDayLabel(day),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium,
                              ),
                              Text(
                                [
                                  DateFormat('MMMM d').format(day),
                                  if (mood != null)
                                    '${_face(mood)} ${MoodScore.label(mood)}',
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
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: palette.dimText,
                        ),
                      ],
                    ),
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
            Wrap(spacing: Insets.sm, runSpacing: Insets.sm, children: chips),
            const SizedBox(height: Insets.sm),
            Divider(height: 1, color: palette.border),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Insets.md),
                child: Text(
                  'No written entries. Tap the day to see everything else.',
                  style: text.bodySmall?.copyWith(color: palette.mutedText),
                ),
              )
            else
              for (final entry in shown)
                _EntryRow(
                  entry: entry,
                  onTap: () => openJournalEntry(context, entry.id),
                ),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: Pressable(
                  onTap: onOpenDay,
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                    child: Text(
                      'See $hidden more ${plural(hidden, 'entry', 'entries')}',
                      style: text.labelLarge?.copyWith(
                        color: context.scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onTap});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final isCheckin = entry.isCheckinEntry;

    final title = isCheckin
        ? [
            if (entry.mood != null)
              '${_face(entry.mood!)} ${MoodScore.label(entry.mood!)}'
            else
              'Check-in',
            if (entry.energy != null) 'Energy ${entry.energy}/5',
          ].join(' · ')
        : entry.displayTitle;
    final body = isCheckin
        ? entry.highlight.trim()
        : (entry.excerpt == 'No text' ? '' : entry.excerpt);

    return Pressable(
      onTap: onTap,
      scale: 0.99,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 62,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  formatTime(entry.createdAt),
                  style: text.labelMedium?.copyWith(
                    color: palette.mutedText,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                      ),
                      if (entry.draft) ...[
                        const SizedBox(width: Insets.sm),
                        Text(
                          'Draft',
                          style: text.labelSmall?.copyWith(
                            color: palette.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: palette.mutedText,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.dimText),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.color,
    required this.label,
    this.dim = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = dim ? palette.dimText : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: dim ? 0.06 : 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: dim ? palette.dimText : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
