import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/places.dart';
import 'place_dialogs.dart';
import 'place_map.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  late DateTime _day;
  bool _privateMode = false;

  @override
  void initState() {
    super.initState();
    _day = dayStart(DateTime.now());
  }

  void _shift(int delta) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));

  void _showPrivacy() {
    showLifelogSheet<void>(
      context,
      builder: (sheetContext) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(title: 'How places work here'),
          _PrivacyPoint(
            icon: Icons.location_disabled_outlined,
            title: 'No background tracking',
            body: 'Nothing runs in the background. A position is only read '
                'when you tap “Use current position”.',
          ),
          SizedBox(height: Insets.lg),
          _PrivacyPoint(
            icon: Icons.cloud_off_outlined,
            title: 'No map tiles',
            body: 'The map is drawn on this device from your saved places. '
                'Your coordinates are not sent to a mapping provider.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final palette = context.palette;
    final places = [...archive.places]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ScreenFrame(
      title: 'Places',
      actions: [
        HeaderButton(
          icon: _privateMode
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          tooltip: _privateMode ? 'Show place names' : 'Hide place names',
          onPressed: () => setState(() => _privateMode = !_privateMode),
        ),
        HeaderButton(
          icon: Icons.info_outline_rounded,
          tooltip: 'How places work',
          onPressed: _showPrivacy,
        ),
        HeaderButton(
          icon: Icons.add_location_alt_outlined,
          tooltip: 'Log a visit',
          filled: true,
          onPressed: () => showVisitEditor(context, ref, day: _day),
        ),
      ],
      children: [
        DayNavigator(
          day: _day,
          onChanged: (value) => setState(() => _day = value),
        ),
        const SizedBox(height: Insets.md),
        DaySwitcher(
          day: _day,
          onSwipe: _shift,
          builder: (context, day) {
            final visits = archive.visitsOn(day);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SchematicMap(
                  places: places,
                  visits: visits,
                  privateMode: _privateMode,
                ),
                const SectionHeader(title: 'Visits'),
                if (visits.isEmpty)
                  EmptyState(
                    icon: Icons.route_outlined,
                    color: palette.place,
                    title: 'No visits this day',
                    message: 'Log a visit after you arrive.',
                    actionLabel: 'Log a visit',
                    onAction: () => showVisitEditor(context, ref, day: day),
                    compact: true,
                  )
                else
                  for (final visit in visits)
                    _VisitCard(visit: visit, day: day),
              ],
            );
          },
        ),
        SectionHeader(
          title: 'Saved places',
          actionLabel: 'New',
          onAction: () => showPlaceEditor(context, ref),
        ),
        if (places.isEmpty)
          EmptyState(
            icon: Icons.place_outlined,
            color: palette.place,
            title: 'No saved places',
            message: 'Save Home, Work or anywhere you go often. Coordinates are optional.',
            actionLabel: 'Add a place',
            onAction: () => showPlaceEditor(context, ref),
            compact: true,
          )
        else
          ListGroup(
            children: [
              for (final place in places)
                _PlaceRow(
                  place: place,
                  visits: archive.visits.where((v) => v.placeId == place.id).length,
                  privateMode: _privateMode,
                  onVisit: () => showVisitEditor(
                    context,
                    ref,
                    day: _day,
                    initialPlace: place,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _VisitCard extends ConsumerWidget {
  const _VisitCard({required this.visit, required this.day});

  final Visit visit;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(archiveProvider).placeById(visit.placeId);
    final palette = context.palette;
    final text = context.text;
    final accent = place == null ? palette.place : Color(place.colorValue);
    final duration = visit.duration;
    final suggested = visit.confidence.name != 'confirmed';
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: QuietCard(
        padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.sm, Insets.md),
        onTap: () => showVisitEditor(context, ref, existing: visit, day: day),
        child: Row(
          children: [
            IconBadge(icon: Icons.place_rounded, color: accent, size: 40, iconSize: 20),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          visit.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall,
                        ),
                      ),
                      if (suggested) ...[
                        const SizedBox(width: Insets.sm),
                        Text(
                          visit.confidence.label,
                          style: text.labelSmall?.copyWith(
                            color: context.scheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [
                      formatTimeRange(visit.startAt, visit.endAt),
                      if (duration != null) formatDurationMinutes(duration.inMinutes),
                    ].join(', '),
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                  if (visit.notes.trim().isNotEmpty)
                    Text(
                      visit.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: palette.dimText),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Visit actions',
              icon: Icon(Icons.more_horiz_rounded, color: palette.dimText),
              onSelected: (value) async {
                if (value == 'edit') {
                  await showVisitEditor(context, ref, existing: visit, day: day);
                } else if (value == 'delete') {
                  final ok = await confirm(
                    context,
                    title: 'Delete this visit?',
                    message: 'The visit will be removed. The saved place remains.',
                  );
                  if (ok) {
                    if (!context.mounted) return;
                    await guard(
                      context,
                      ref.read(archiveProvider.notifier).deleteVisit(visit.id),
                      errorPrefix: 'Could not delete visit',
                    );
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends ConsumerWidget {
  const _PlaceRow({
    required this.place,
    required this.visits,
    required this.privateMode,
    required this.onVisit,
  });

  final Place place;
  final int visits;
  final bool privateMode;
  final VoidCallback onVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return ListRow(
      icon: Icons.place_rounded,
      iconColor: Color(place.colorValue),
      title: privateMode ? 'Saved place' : place.name,
      subtitle: [
        '$visits ${plural(visits, 'visit')}',
        if (place.hasCoordinates && !privateMode) 'Has coordinates',
      ].join(', '),
      onTap: () => showPlaceEditor(context, ref, existing: place),
      trailing: PopupMenuButton<String>(
        tooltip: 'Place actions',
        icon: Icon(Icons.more_horiz_rounded, color: palette.dimText),
        onSelected: (value) async {
          if (value == 'edit') {
            await showPlaceEditor(context, ref, existing: place);
          } else if (value == 'visit') {
            onVisit();
          } else if (value == 'delete') {
            final ok = await confirm(
              context,
              title: 'Delete “${place.name}”?',
              message:
                  'Visits that mention this place will remain, but will no longer be linked to it.',
            );
            if (ok) {
              if (!context.mounted) return;
              await guard(
                context,
                ref.read(archiveProvider.notifier).deletePlace(place.id),
                errorPrefix: 'Could not delete place',
              );
            }
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'visit', child: Text('Log a visit')),
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(icon: icon, color: palette.place, size: 38, iconSize: 19),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text(
                body,
                style: context.text.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
