import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/search.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/timeline.dart';
import '../journal/journal_widgets.dart';
import '../meals/meal_dialogs.dart';
import '../music/music_screen.dart';
import '../photos/photo_widgets.dart';
import '../places/place_dialogs.dart';
import '../timeline/event_dialogs.dart';
import '../timeline/timeline_screen.dart';
import '../trackers/tracker_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  SearchKind? _kind;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final text = context.text;
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    final trimmed = _query.trim();
    final allHits = trimmed.isEmpty
        ? const <SearchHit>[]
        : searchArchive(archive, _query);
    final hits = _kind == null
        ? allHits
        : allHits.where((hit) => hit.kind == _kind).toList();

    final counts = <SearchKind, int>{};
    for (final hit in allHits) {
      counts[hit.kind] = (counts[hit.kind] ?? 0) + 1;
    }
    final grouped = <SearchKind, List<SearchHit>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.kind, () => []).add(hit);
    }

    // Tags people actually use, offered as one-tap searches.
    final tagCounts = <String, int>{};
    for (final entry in archive.entries.where((e) => !e.archived)) {
      for (final tag in entry.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    final suggestions = (tagCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .map((e) => e.key)
        .toList();

    return ScreenFrame(
      title: 'Search',
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: pushed,
          onChanged: (value) => setState(() => _query = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Entries, tags, places, tracks',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _setQuery('');
                      _focus.requestFocus();
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: Insets.md),
        FilterRow<SearchKind?>(
          values: <SearchKind?>[null, ...SearchKind.values],
          selected: _kind,
          labelFor: (kind) {
            if (kind == null) {
              return trimmed.isEmpty ? 'All' : 'All ${allHits.length}';
            }
            final n = counts[kind];
            return n == null ? kind.label : '${kind.label} $n';
          },
          onChanged: (value) => setState(() => _kind = value),
        ),
        const SizedBox(height: Insets.sm),
        if (trimmed.isEmpty) ...[
          if (suggestions.isNotEmpty) ...[
            const SectionHeader(title: 'Try a tag'),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final tag in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.tag_rounded, size: 15),
                    label: Text(tag),
                    onPressed: () => _setQuery(tag),
                  ),
              ],
            ),
          ],
          EmptyState(
            icon: Icons.search_rounded,
            title: 'Search your archive',
            message: 'Everything is searched on this device. Nothing you type leaves it.',
            compact: suggestions.isNotEmpty,
          ),
        ] else if (hits.isEmpty)
          EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'Nothing contains “$trimmed”. Search is literal and does not guess related words.',
            compact: true,
          )
        else ...[
          for (final kind in SearchKind.values)
            if (grouped[kind] != null) ...[
              SectionHeader(
                title: kind.label,
                padding: const EdgeInsets.only(top: Insets.lg, bottom: Insets.sm),
              ),
              for (final hit in grouped[kind]!)
                _SearchResult(
                  hit: hit,
                  query: trimmed,
                  onOpen: () => _openHit(hit),
                  onOpenDay: () => _openDay(hit.date),
                ),
            ],
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: Text(
              'Archived entries and hidden events are not included.',
              style: text.labelSmall?.copyWith(color: palette.dimText),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openHit(SearchHit hit) async {
    final archive = ref.read(archiveProvider);
    switch (hit.kind) {
      case SearchKind.journal:
        await openJournalEntry(context, hit.sourceId);
      case SearchKind.photo:
        final item = archive.mediaById(hit.sourceId);
        if (item != null && mounted) {
          await showMediaViewer(context, ref, item);
        }
      case SearchKind.tracker:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackerDetailScreen(trackerId: hit.sourceId),
          ),
        );
      case SearchKind.place:
        final place = archive.placeById(hit.sourceId);
        if (place != null && mounted) {
          await showPlaceEditor(context, ref, existing: place);
        }
      case SearchKind.visit:
        final visit = archive.visitById(hit.sourceId);
        if (visit != null && mounted) {
          await showVisitEditor(context, ref, existing: visit);
        }
      case SearchKind.music:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MusicScreen(day: hit.date),
          ),
        );
      case SearchKind.event:
        TimelineEvent? event;
        for (final candidate in archive.events) {
          if (candidate.id == hit.sourceId) {
            event = candidate;
            break;
          }
        }
        if (event != null && mounted) {
          await showTimelineEventEditor(context, ref, existing: event);
        }
      case SearchKind.meal:
        MealRecord? meal;
        for (final candidate in archive.meals) {
          if (candidate.id == hit.sourceId) {
            meal = candidate;
            break;
          }
        }
        if (meal != null && mounted) {
          await showMealEditor(context, ref, hit.date, existing: meal);
        }
    }
  }

  Future<void> _openDay(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimelineScreen(initialDate: date),
      ),
    );
  }
}

class _SearchResult extends StatelessWidget {
  const _SearchResult({
    required this.hit,
    required this.query,
    required this.onOpen,
    required this.onOpenDay,
  });

  final SearchHit hit;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final (icon, color) = switch (hit.kind) {
      SearchKind.journal => (Icons.menu_book_rounded, palette.journal),
      SearchKind.photo => (Icons.photo_rounded, palette.photo),
      SearchKind.tracker => (Icons.task_alt_rounded, palette.tracker),
      SearchKind.place => (Icons.place_rounded, palette.place),
      SearchKind.visit => (Icons.directions_walk_rounded, palette.place),
      SearchKind.music => (Icons.graphic_eq_rounded, palette.music),
      SearchKind.event => (Icons.bolt_rounded, palette.manual),
      SearchKind.meal => (Icons.restaurant_rounded, palette.manual),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: QuietCard(
        padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.xs, Insets.md),
        onTap: onOpen,
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 40, iconSize: 20),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Highlight(
                    text: hit.title,
                    query: query,
                    maxLines: 1,
                    style: text.titleSmall,
                    color: color,
                  ),
                  if (hit.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _Highlight(
                      text: hit.subtitle,
                      query: query,
                      maxLines: 2,
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                      color: color,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${formatDayLong(hit.date)}, ${formatTime(hit.date)}',
                    style: text.labelSmall?.copyWith(color: palette.dimText),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open this day',
              onPressed: onOpenDay,
              icon: Icon(Icons.calendar_month_outlined, size: 20, color: palette.dimText),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bolds every occurrence of [query] in [text].
class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.text,
    required this.query,
    required this.maxLines,
    required this.style,
    required this.color,
  });

  final String text;
  final String query;
  final int maxLines;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final lower = text.toLowerCase();
    if (q.isEmpty || lower.length != text.length || !lower.contains(q)) {
      return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    }
    final spans = <TextSpan>[];
    var pos = 0;
    while (true) {
      final index = lower.indexOf(q, pos);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(pos)));
        break;
      }
      if (index > pos) spans.add(TextSpan(text: text.substring(pos, index)));
      spans.add(
        TextSpan(
          text: text.substring(index, index + q.length),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      );
      pos = index + q.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
