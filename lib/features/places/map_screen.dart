import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../app/theme/app_theme.dart';
import '../../app/widgets/common.dart';
import '../../app/widgets/components.dart';
import '../../core/util/dates.dart';
import '../../domain/models/places.dart';
import '../../integrations/location/background_location_channel.dart';
import '../../integrations/location/location_tracking.dart';
import '../../integrations/location/location_tracking_controller.dart';
import '../../integrations/maps/map_models.dart';
import '../../integrations/maps/map_platform.dart';
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
  BackgroundLocationStatus? _backgroundStatus;
  Timer? _liveTimer;
  MapPoint? _livePoint;
  DateTime? _liveCheckedAt;
  bool _refreshingLive = false;

  @override
  void initState() {
    super.initState();
    _day = dayStart(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshBackgroundStatus());
      unawaited(_refreshLiveLocation());
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) unawaited(_refreshLiveLocation());
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLiveLocation() async {
    if (_refreshingLive) return;
    _refreshingLive = true;
    final settings = ref.read(settingsProvider);
    if (settings.locationTrackingEnabled || settings.backgroundLocationEnabled) {
      final position = await LocationTracking.getCurrentPosition(
        requestPermission: false,
        attempts: 1,
      );
      final sample = position == null
          ? null
          : LocationTracking.sampleFromPosition(position);
      if (sample != null && mounted) {
        setState(() {
          _livePoint = MapPoint(
            latitude: sample.latitude,
            longitude: sample.longitude,
            kind: 'current',
            name: 'Current location',
          );
          _liveCheckedAt = DateTime.now();
        });
      }
    }
    _refreshingLive = false;
  }

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _refreshBackgroundStatus() async {
    final status =
        await ref.read(locationTrackingControllerProvider).backgroundStatus();
    if (!mounted) return;
    setState(() => _backgroundStatus = status);
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
            icon: Icons.my_location_rounded,
            title: 'Location tracking (optional)',
            body:
                'When you turn on day tracking, Lifelog records your location '
                'while the app is in use. With “Background visits” enabled and '
                'Location Access set to Always in iOS Settings, iOS also reports '
                'places you arrive at or leave even when the app is closed. '
                'No continuous GPS is used. Samples and visits stay in your '
                'encrypted local archive and are never uploaded.',
          ),
          SizedBox(height: Insets.lg),
          _PrivacyPoint(
            icon: Icons.map_outlined,
            title: 'Detailed Apple map',
            body:
                'The interactive map uses Apple MapKit, so map tiles and '
                'address searches are handled by Apple. Searching an address '
                'sends that query to Apple. Your saved coordinates, route '
                'history and visits are not uploaded by Lifelog and stay in '
                'the encrypted archive.',
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTracking(bool value) async {
    final controller = ref.read(locationTrackingControllerProvider);
    await controller.setEnabled(value, requestPermission: value);
    if (!mounted) return;
    if (value) {
      final ok = await controller.recordNow(requestPermission: false);
      if (!mounted) return;
      showSnack(
        context,
        ok
            ? 'Location tracking is on. Lifelog will record where you spend time while the app is in use.'
            : 'Location tracking is on. Allow location access to record where you spend time.',
      );
    } else {
      showSnack(context, 'Location tracking is off. Your saved visits remain.');
    }
  }

  Future<void> _toggleBackgroundTracking(bool value) async {
    final controller = ref.read(locationTrackingControllerProvider);
    final status = await controller.setBackgroundEnabled(value);
    if (!mounted) return;
    setState(() => _backgroundStatus = status);
    if (!value) {
      showSnack(context, 'Background visits are off. Saved places remain.');
      return;
    }
    if (status.isEffectivelyOn) {
      showSnack(
        context,
        'Background visits are on. iOS will add places you visit to your private map.',
      );
      return;
    }
    showSnack(context, _backgroundStatusMessage(status));
  }

  /// Honest label for the background row: never say "On" unless iOS is really
  /// monitoring with Always authorization.
  String _backgroundRowSubtitle(BackgroundLocationStatus status) {
    if (!status.enabled) return 'Off';
    if (!status.locationServicesEnabled) return 'Off · Location Services are off';
    switch (status.authorization) {
      case BackgroundLocationAuthorization.restricted:
        return 'Restricted · iOS does not allow location monitoring';
      case BackgroundLocationAuthorization.denied:
        return 'Needs Always · Location access is off';
      case BackgroundLocationAuthorization.whenInUse:
      case BackgroundLocationAuthorization.notDetermined:
      case BackgroundLocationAuthorization.unknown:
      case BackgroundLocationAuthorization.unavailable:
        return 'Needs Always · choose Always in iOS Settings';
      case BackgroundLocationAuthorization.always:
        if (!status.monitoringActive) {
          return 'Off · iOS monitoring is unavailable';
        }
        return 'On · iOS reports places you visit while the app is closed';
    }
  }

  String _backgroundStatusMessage(BackgroundLocationStatus status) {
    final label = _backgroundRowSubtitle(status);
    if (label.startsWith('Restricted')) {
      return 'Restricted · iOS won’t start background visits. Check Location privacy controls or Screen Time.';
    }
    if (label.startsWith('Needs Always')) {
      return 'Needs Always · Background visits will stay off until you open iOS Settings → Location → Always.';
    }
    return '$label · Background visits are paused until location access is fixed.';
  }

  Future<void> _openLocationSettings() =>
      ref.read(backgroundLocationChannelProvider).openSettings();

  Future<void> _recordLocationNow() async {
    final settings = ref.read(settingsProvider);
    final controller = ref.read(locationTrackingControllerProvider);
    if (!settings.locationTrackingEnabled) {
      await _toggleTracking(true);
      return;
    }
    final ok = await controller.recordNow(requestPermission: true);
    await _refreshLiveLocation();
    if (!mounted) return;
    showSnack(
      context,
      ok
          ? 'Current location recorded.'
          : 'Could not read your current location. Check location access in Settings.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final archive = ref.watch(archiveProvider);
    final settings = ref.watch(settingsProvider);
    final palette = context.palette;
    final places = [...archive.places]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final backgroundStatus = _backgroundStatus ??
        BackgroundLocationStatus(
          enabled: settings.backgroundLocationEnabled,
          authorization: BackgroundLocationAuthorization.unknown,
          monitoringActive: false,
          locationServicesEnabled: true,
        );

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
          icon: Icons.my_location_rounded,
          tooltip: 'Record current location',
          onPressed: _recordLocationNow,
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
        ListGroup(
          title: 'Day tracking',
          footer: _isIOS
              ? 'Day tracking records your route while the app is in use. Background visits use iOS place monitoring (not continuous GPS) and need Location Access set to Always in iOS Settings. All of it stays on this device in your encrypted archive — nothing is sent to a server.'
              : 'Day tracking records your route while the app is in use. Background visits are an iOS-only feature. All of it stays on this device in your encrypted archive — nothing is sent to a server.',
          children: [
            ListRow(
              icon: Icons.location_searching_rounded,
              iconColor: palette.place,
              title: 'Track where I spend time',
              subtitle: settings.locationTrackingEnabled
                  ? 'On · records location while the app is in use'
                  : 'Off',
              trailing: Switch.adaptive(
                value: settings.locationTrackingEnabled,
                onChanged: _toggleTracking,
              ),
            ),
            if (settings.locationTrackingEnabled)
              ListRow(
                icon: Icons.pin_drop_outlined,
                iconColor: palette.place,
                title: 'Record now',
                subtitle: 'Capture your current location and update today',
                chevron: true,
                onTap: _recordLocationNow,
              ),
            if (_isIOS) ...[
              ListRow(
                icon: Icons.hourglass_top_rounded,
                iconColor: palette.place,
                title: 'Background visits',
                subtitle: _backgroundRowSubtitle(backgroundStatus),
                trailing: Switch.adaptive(
                  value: settings.backgroundLocationEnabled,
                  onChanged: _toggleBackgroundTracking,
                ),
              ),
              if (settings.backgroundLocationEnabled)
                ListRow(
                  icon: Icons.settings_outlined,
                  iconColor: palette.place,
                  title: 'Location Access in iOS Settings',
                  subtitle: 'Choose Always for background visit tracking',
                  chevron: true,
                  onTap: () async {
                    await _openLocationSettings();
                    if (!mounted) return;
                    unawaited(_refreshBackgroundStatus());
                  },
                ),
            ],
          ],
        ),
        const SizedBox(height: Insets.md),
        DaySwitcher(
          day: _day,
          onSwipe: _shift,
          builder: (context, day) {
            final visits = archive.visitsOn(day);
            final summary = LocationTracking.summarizeDay(archive, day);
            final stops = LocationTracking.inferStops(archive, day);
            final isToday = sameDay(day, DateTime.now());
            final lastStayBeforeTravel = _lastStayBeforeCurrentTravel(summary);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary.status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.md),
                    child: _NowCard(
                      status: summary.status!,
                      isToday: isToday,
                      fromLabel: lastStayBeforeTravel?.label,
                      fromPlaceId: lastStayBeforeTravel?.placeId,
                    ),
                  ),
                if (summary.sampleCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.md),
                    child: _DaySummaryCard(summary: summary, isToday: isToday),
                  ),
                _buildMap(
                  places: places,
                  day: day,
                  summary: summary,
                ),
                if (_livePoint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: _LiveLocationLine(
                      point: _livePoint!,
                      checkedAt: _liveCheckedAt,
                    ),
                  ),
                const SizedBox(height: Insets.sm),
                _MapActions(
                  onDropPin: (point) => showPlaceEditor(
                    context,
                    ref,
                    initialLatitude: point.latitude,
                    initialLongitude: point.longitude,
                  ),
                  onPinHere: () async {
                    final point = _livePoint;
                    if (point == null) {
                      showSnack(
                        context,
                        'No precise current fix yet. Tap the pin button on the map instead.',
                      );
                      return;
                    }
                    await showPlaceEditor(
                      context,
                      ref,
                      initialLatitude: point.latitude,
                      initialLongitude: point.longitude,
                    );
                  },
                ),
                if (stops.isNotEmpty) ...[
                  const SectionHeader(title: 'Travel stops & possible destinations'),
                  for (final stop in stops)
                    _StopCard(
                      stop: stop,
                      privateMode: _privateMode,
                      onSave: () => showPlaceEditor(
                        context,
                        ref,
                        initialLatitude: stop.latitude,
                        initialLongitude: stop.longitude,
                        initialName: stop.placeId == null ? stop.label : null,
                      ),
                    ),
                ],
                const SectionHeader(title: 'Today\'s journey'),
                if (summary.segments.isEmpty)
                  EmptyState(
                    icon: Icons.route_outlined,
                    color: palette.place,
                    title: summary.sampleCount == 0
                        ? 'No location info for this day'
                        : 'Building your day',
                    message: summary.sampleCount == 0
                        ? (settings.locationTrackingEnabled
                            ? 'Keep the app open sometimes or tap Record now so Lifelog can see where you are.'
                            : 'Turn on day tracking or log a visit manually.')
                        : 'Location samples were recorded. Keep tracking to see more detail.',
                    actionLabel: settings.locationTrackingEnabled
                        ? 'Record now'
                        : 'Log a visit',
                    onAction: settings.locationTrackingEnabled
                        ? _recordLocationNow
                        : () => showVisitEditor(context, ref, day: day),
                    compact: true,
                  )
                else
                  for (final segment in summary.segments)
                    _JourneySegmentCard(
                      segment: segment,
                      isToday: isToday,
                    ),
                if (visits.any((v) => v.id.startsWith('auto-loc-'))) ...[
                  const SectionHeader(title: 'Auto-tracked places'),
                  for (final visit
                      in visits.where((v) => v.id.startsWith('auto-loc-')))
                    _VisitCard(visit: visit, day: day),
                ],
                if (visits.any((v) => !v.id.startsWith('auto-loc-'))) ...[
                  const SectionHeader(title: 'Manual visits'),
                  for (final visit
                      in visits.where((v) => !v.id.startsWith('auto-loc-')))
                    _VisitCard(visit: visit, day: day),
                ],
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
            message:
                'Save Home, Work or anywhere you go often. Coordinates help match tracked locations to places.',
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
                  visits:
                      archive.visits.where((v) => v.placeId == place.id).length,
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

  Widget _buildMap({
    required List<Place> places,
    required DateTime day,
    required DayLocationSummary summary,
  }) {
    final rawSamples = ref.read(archiveProvider).locationSamplesOn(day);
    final samples = rawSamples
        .where(
          (sample) =>
              sample.accuracyMeters == null ||
              sample.accuracyMeters! <=
                  LocationTracking.maxAcceptedAccuracyMeters,
        )
        .toList();
    final step = samples.isEmpty
        ? 1
        : (samples.length / 700).ceil().clamp(1, samples.length);
    final route = <MapPoint>[
      for (var i = 0; i < samples.length; i += step)
        MapPoint(
          id: samples[i].id,
          latitude: samples[i].latitude,
          longitude: samples[i].longitude,
          kind: 'route',
        ),
    ];
    if (samples.isNotEmpty && route.last.id != samples.last.id) {
      route.add(
        MapPoint(
          id: samples.last.id,
          latitude: samples.last.latitude,
          longitude: samples.last.longitude,
          kind: 'route',
        ),
      );
    }
    final stopPoints = LocationTracking.inferStops(ref.read(archiveProvider), day)
        .map(
          (stop) => MapPoint(
            latitude: stop.latitude,
            longitude: stop.longitude,
            name: _privateMode ? 'Hidden stop' : stop.label,
            radiusMeters: 120,
            kind: 'stop',
            notes: formatTimeRange(stop.startAt, stop.endAt),
          ),
        )
        .toList();
    final placePoints = places
        .where((place) => place.hasCoordinates)
        .map(
          (place) => MapPoint(
            id: place.id,
            latitude: place.latitude!,
            longitude: place.longitude!,
            name: _privateMode ? '' : place.name,
            color: place.colorValue,
            radiusMeters: place.radiusMeters,
            kind: 'place',
            notes: place.notes,
          ),
        )
        .toList();
    return DetailedMap(
      data: LifelogMapData(
        places: placePoints,
        stops: stopPoints,
        route: route,
        current: _livePoint,
        privateMode: _privateMode,
        followUser: summary.status?.isCurrent ?? true,
      ),
      onPinDropped: (point) => showPlaceEditor(
        context,
        ref,
        initialLatitude: point.latitude,
        initialLongitude: point.longitude,
      ),
    );
  }
}

DayLocationSegment? _lastStayBeforeCurrentTravel(DayLocationSummary summary) {
  final segments = summary.segments;
  for (var i = segments.length - 1; i >= 0; i--) {
    final seg = segments[i];
    if (seg.isCurrent && seg.isTravel) {
      for (var j = i - 1; j >= 0; j--) {
        if (!segments[j].isTravel) return segments[j];
      }
      return null;
    }
  }
  return null;
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.status,
    required this.isToday,
    this.fromLabel,
    this.fromPlaceId,
  });

  final DayLocationStatus status;
  final bool isToday;
  final String? fromLabel;
  final String? fromPlaceId;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final now = DateTime.now();
    final updatedAgo = now.difference(status.lastUpdated);
    final isTravel = status.kind == DayLocationKind.travel;
    final current = status.isCurrent && isToday;
    final icon = isTravel ? Icons.directions_car_rounded : Icons.place_rounded;
    final accent = isTravel ? palette.music : palette.place;
    final title = current
        ? status.title
        : isToday
            ? '${status.title} (last known)'
            : '${status.title} (last for this day)';
    final detailLines = <String>[
      if (isTravel && fromLabel != null && fromLabel!.isNotEmpty)
        'Left $fromLabel at ${formatTime(status.since)}',
      if (isTravel && (fromLabel == null || fromLabel!.isEmpty))
        'Started moving at ${formatTime(status.since)}',
      if (!isTravel)
        status.subtitle,
      if (isTravel) status.subtitle,
      'Last updated ${_agoText(updatedAgo)}',
    ];
    return QuietCard(
      color: accent.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: accent, size: 44, iconSize: 22),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current
                      ? 'Where you are now'
                      : isToday
                          ? 'Last known location'
                          : 'Last location this day',
                  style: text.labelMedium?.copyWith(
                    color: palette.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(title, style: text.titleMedium),
                const SizedBox(height: 4),
                for (final line in detailLines.toSet())
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: text.bodySmall?.copyWith(color: palette.mutedText),
                    ),
                  ),
                if (isTravel && current)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Where you\'re going: on the move right now (destination isn\'t known).',
                      style: text.bodySmall?.copyWith(color: palette.dimText),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.summary, required this.isToday});

  final DayLocationSummary summary;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final most = summary.mostStayLabel;
    final stats = <({IconData icon, String label, String value, Color color})>[
      if (most != null)
        (
          icon: Icons.star_rounded,
          label: 'Most time',
          value:
              '$most · ${formatDurationMinutes(summary.mostStayDuration.inMinutes)}',
          color: palette.place,
        ),
      if (summary.travelDuration.inMinutes > 0)
        (
          icon: Icons.directions_car_rounded,
          label: 'Traveling',
          value: formatDurationMinutes(summary.travelDuration.inMinutes),
          color: palette.music,
        ),
      if (summary.stayDuration.inMinutes > 0)
        (
          icon: Icons.schedule_rounded,
          label: 'Time at places',
          value: formatDurationMinutes(summary.stayDuration.inMinutes),
          color: palette.tracker,
        ),
      (
        icon: Icons.place_outlined,
        label: 'Places',
        value: '${summary.placeCount}',
        color: palette.journal,
      ),
    ];
    return QuietCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? 'Today at a glance' : 'This day at a glance',
            style: text.titleSmall,
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final stat in stats)
                _StatChip(
                  icon: stat.icon,
                  label: stat.label,
                  value: stat.value,
                  color: stat.color,
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(
            '${summary.sampleCount} ${summary.sampleCount == 1 ? 'location check' : 'location checks'} recorded on this device.',
            style: text.bodySmall?.copyWith(color: palette.dimText),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              '$label: $value',
              style: text.bodySmall?.copyWith(
                color: context.scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneySegmentCard extends StatelessWidget {
  const _JourneySegmentCard({required this.segment, required this.isToday});

  final DayLocationSegment segment;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.text;
    final travel = segment.isTravel;
    final icon = travel ? Icons.directions_car_rounded : Icons.place_rounded;
    final accent = travel ? palette.music : palette.place;
    final dur = segment.duration;
    final timeText = formatTimeRange(segment.startAt, segment.endAt);
    final title = travel
        ? (segment.isCurrent && isToday ? 'On the road now' : 'Traveling')
        : (segment.isCurrent && isToday ? '${segment.label} (now)' : segment.label);
    final subtitleParts = <String>[
      timeText,
      if (dur.inMinutes > 0) formatDurationMinutes(dur.inMinutes),
      if (travel && segment.distanceMeters != null && segment.distanceMeters! >= 100)
        '~${_distanceText(segment.distanceMeters!)}',
    ];
    final explanation = travel
        ? (segment.isCurrent && isToday
            ? 'You are moving between places.'
            : 'Time spent on the move.')
        : (segment.placeId == null
            ? 'Stopped at a location not saved as a place.'
            : 'Time spent here.');
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: QuietCard(
        padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.md, Insets.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: accent, size: 40, iconSize: 20),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: text.titleSmall)),
                      if (segment.isCurrent && isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Now',
                            style: text.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleParts.join(' · '),
                    style: text.bodySmall?.copyWith(color: palette.mutedText),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    explanation,
                    style: text.bodySmall?.copyWith(color: palette.dimText),
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

String _distanceText(double meters) {
  if (meters >= 1000) {
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }
  return '${meters.round()} m';
}

String _agoText(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
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
        padding:
            const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.sm, Insets.md),
        onTap: () => showVisitEditor(context, ref, existing: visit, day: day),
        child: Row(
          children: [
            IconBadge(icon: Icons.edit_location_alt_outlined, color: accent, size: 40, iconSize: 20),
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
                      if (duration != null)
                        formatDurationMinutes(duration.inMinutes),
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
                    message:
                        'The visit will be removed. The saved place remains.',
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



class _LiveLocationLine extends StatelessWidget {
  const _LiveLocationLine({required this.point, required this.checkedAt});

  final MapPoint point;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final ago = checkedAt == null
        ? ''
        : ' · updated ${_agoText(DateTime.now().difference(checkedAt!))}';
    return Row(
      children: [
        Icon(
          Icons.gps_fixed_rounded,
          size: 16,
          color: context.palette.place,
        ),
        const SizedBox(width: Insets.xs),
        Expanded(
          child: Text(
            'Live fix ${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)}$ago',
            style: context.text.labelSmall?.copyWith(
              color: context.palette.mutedText,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapActions extends StatelessWidget {
  const _MapActions({required this.onDropPin, required this.onPinHere});

  final ValueChanged<MapPoint> onDropPin;
  final VoidCallback onPinHere;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.sm,
      children: [
        OutlinedButton.icon(
          onPressed: onPinHere,
          icon: const Icon(Icons.my_location_rounded, size: 16),
          label: const Text('Pin my current spot'),
        ),
        OutlinedButton.icon(
          onPressed: () => showMapPinPicker(context).then((point) {
            if (point != null) onDropPin(point);
          }),
          icon: const Icon(Icons.add_location_alt_outlined, size: 16),
          label: const Text('Choose a point on the map'),
        ),
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.stop,
    required this.privateMode,
    required this.onSave,
  });

  final TravelStop stop;
  final bool privateMode;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = privateMode ? 'Hidden stop' : stop.label;
    final duration = stop.duration;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: QuietCard(
        child: Row(
          children: [
            IconBadge(
              icon: Icons.hourglass_top_rounded,
              color: palette.place,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.titleSmall),
                  Text(
                    [
                      formatTimeRange(stop.startAt, stop.endAt),
                      if (duration.inMinutes > 0)
                        formatDurationMinutes(duration.inMinutes),
                      '${stop.sampleCount} GPS checks',
                    ].join(' · '),
                    style: context.text.bodySmall?.copyWith(
                      color: palette.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            if (stop.placeId == null)
              TextButton(onPressed: onSave, child: const Text('Save')),
          ],
        ),
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
