import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/models/places.dart';
import '../../integrations/maps/map_models.dart';
import '../../integrations/maps/map_platform.dart';

/// A deliberately schematic map. Lifelog does not send precise location
/// history to a tile provider in this build, so saved places, tracked samples
/// and unsaved stops are plotted on a local canvas instead.
class SchematicMap extends StatelessWidget {
  const SchematicMap({
    super.key,
    required this.places,
    required this.visits,
    required this.privateMode,
    this.samples = const [],
    this.height = 230,
  });

  final List<Place> places;
  final List<Visit> visits;
  final List<LocationSample> samples;
  final bool privateMode;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final located = places.where((p) => p.hasCoordinates).toList();
    if (located.isEmpty && samples.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.subtle,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public_off_rounded, color: scheme.primary, size: 30),
              const SizedBox(height: Insets.md),
              Text(
                'No location on this day',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: Insets.xs),
              Text(
                'Turn on day tracking or allow background visits to see the places you went. Named places work without coordinates too.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: palette.mutedText),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: palette.subtle,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: CustomPaint(
          painter: _MapPainter(
            places: located,
            visits: visits,
            samples: privateMode ? const [] : samples,
            privateMode: privateMode,
            gridColor: palette.border,
            surface: palette.subtle,
            accent: scheme.primary,
            textColor: palette.mutedText,
            labelStyle: Theme.of(context).textTheme.labelSmall!,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.places,
    required this.visits,
    required this.samples,
    required this.privateMode,
    required this.gridColor,
    required this.surface,
    required this.accent,
    required this.textColor,
    required this.labelStyle,
  });

  final List<Place> places;
  final List<Visit> visits;
  final List<LocationSample> samples;
  final bool privateMode;
  final Color gridColor;
  final Color surface;
  final Color accent;
  final Color textColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = surface);

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      final y = size.height * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    var minLat = 90.0;
    var maxLat = -90.0;
    var minLon = 180.0;
    var maxLon = -180.0;
    for (final place in places) {
      minLat = math.min(minLat, place.latitude!);
      maxLat = math.max(maxLat, place.latitude!);
      minLon = math.min(minLon, place.longitude!);
      maxLon = math.max(maxLon, place.longitude!);
    }
    for (final sample in samples) {
      minLat = math.min(minLat, sample.latitude);
      maxLat = math.max(maxLat, sample.latitude);
      minLon = math.min(minLon, sample.longitude);
      maxLon = math.max(maxLon, sample.longitude);
    }
    final latSpan = math.max(maxLat - minLat, 0.01);
    final lonSpan = math.max(maxLon - minLon, 0.01);
    const padding = 46.0;
    final innerWidth = math.max(size.width - padding * 2, 1.0);
    final innerHeight = math.max(size.height - padding * 2, 1.0);

    Offset project(double lat, double lon) {
      final x = padding + ((lon - minLon) / lonSpan) * innerWidth;
      final y = padding + ((maxLat - lat) / latSpan) * innerHeight;
      return Offset(x, y);
    }

    final orderedSamples = [...samples]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    // Raw journey: one line through the actual samples, plus small dots.
    if (orderedSamples.isNotEmpty) {
      final pathPaint = Paint()
        ..color = accent.withValues(alpha: 0.38)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < orderedSamples.length; i++) {
        final point = project(
          orderedSamples[i].latitude,
          orderedSamples[i].longitude,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(
          point,
          2.4,
          Paint()..color = accent.withValues(alpha: 0.55),
        );
      }
      canvas.drawPath(path, pathPaint);
      _drawUnsavedStops(canvas, orderedSamples, project, accent);
    }

    final byPlace = <String, List<Visit>>{};
    for (final visit in visits) {
      if (visit.placeId == null) continue;
      byPlace.putIfAbsent(visit.placeId!, () => []).add(visit);
    }

    final visitPoints = <Offset>[];
    for (final place in places) {
      final dayVisits = byPlace[place.id];
      if (dayVisits == null) continue;
      final point = project(place.latitude!, place.longitude!);
      for (var i = 0; i < dayVisits.length; i++) {
        visitPoints.add(point);
      }
    }
    if (visitPoints.length > 1) {
      final path = Path()..moveTo(visitPoints.first.dx, visitPoints.first.dy);
      for (var i = 1; i < visitPoints.length; i++) {
        path.lineTo(visitPoints[i].dx, visitPoints[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    }

    for (final place in places) {
      final point = project(place.latitude!, place.longitude!);
      final accentColor = Color(place.colorValue);
      final dayVisits = byPlace[place.id] ?? const <Visit>[];
      final radius = 5.0 + math.min(dayVisits.length, 4) * 1.6;

      if (dayVisits.isNotEmpty) {
        canvas.drawCircle(
          point,
          radius + 7,
          Paint()..color = accentColor.withValues(alpha: 0.16),
        );
      }
      canvas.drawCircle(point, radius, Paint()..color = accentColor);
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      final label = privateMode ? 'Hidden place' : place.name;
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle.copyWith(color: textColor)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 132);
      final labelOffset = Offset(
        (point.dx - painter.width / 2).clamp(4.0, size.width - painter.width - 4),
        (point.dy + radius + 6).clamp(0.0, size.height - painter.height),
      );
      painter.paint(canvas, labelOffset);
    }

    final note = privateMode
        ? 'Privacy mode · exact coordinates hidden'
        : 'Schematic local map · ${samples.length} tracked points · no map tiles';
    final notePainter = TextPainter(
      text: TextSpan(
        text: note,
        style: labelStyle.copyWith(color: textColor.withValues(alpha: 0.7)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);
    notePainter.paint(canvas, Offset(8, size.height - notePainter.height - 6));
  }

  /// Highlights clusters where the device stayed put — including stops that
  /// were never matched to a saved place.
  void _drawUnsavedStops(
    Canvas canvas,
    List<LocationSample> samples,
    Offset Function(double, double) project,
    Color accent,
  ) {
    const clusterDegrees = 0.0012; // roughly 130 metres
    var clusterStart = 0;
    void drawCluster(int end) {
      final cluster = samples.sublist(clusterStart, end);
      if (cluster.length < 2) return;
      final duration = cluster.last.recordedAt.difference(cluster.first.recordedAt);
      if (duration.inMinutes < 4) return;
      final lat = cluster.map((s) => s.latitude).reduce((a, b) => a + b) /
          cluster.length;
      final lon = cluster.map((s) => s.longitude).reduce((a, b) => a + b) /
          cluster.length;
      final point = project(lat, lon);
      canvas.drawCircle(
        point,
        11,
        Paint()..color = accent.withValues(alpha: 0.14),
      );
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1];
      final current = samples[i];
      if ((current.latitude - previous.latitude).abs() > clusterDegrees ||
          (current.longitude - previous.longitude).abs() > clusterDegrees) {
        drawCluster(i);
        clusterStart = i;
      }
    }
    drawCluster(samples.length);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.places != places ||
        oldDelegate.visits != visits ||
        oldDelegate.samples != samples ||
        oldDelegate.privateMode != privateMode;
  }
}

/// Full MapKit map on iOS, with a local schematic fallback for tests and
/// non-Apple platforms. The native view supports pan, zoom, rotation, POIs,
/// saved pins, travel stops and the recorded route.
class DetailedMap extends StatefulWidget {
  const DetailedMap({
    super.key,
    required this.data,
    this.height = 320,
    this.onPinDropped,
    this.showDropPin = true,
    this.showControls = true,
  });

  final LifelogMapData data;
  final double height;
  final ValueChanged<MapPoint>? onPinDropped;
  final bool showDropPin;
  final bool showControls;

  @override
  State<DetailedMap> createState() => _DetailedMapState();
}

class _DetailedMapState extends State<DetailedMap> {
  LifelogMapController? _controller;
  late LifelogMapType _mapType;
  late bool _followUser;
  bool _fitPending = true;

  @override
  void initState() {
    super.initState();
    _mapType = widget.data.mapType;
    _followUser = widget.data.followUser;
  }

  @override
  void didUpdateWidget(covariant DetailedMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pushData();
  }

  LifelogMapData get _effectiveData => widget.data.copyWith(
        mapType: _mapType,
        followUser: _followUser,
        fitOnLoad: _fitPending,
      );

  void _pushData() {
    _controller?.update(_effectiveData);
    _fitPending = false;
  }

  void _onCreated(int viewId) {
    _controller = LifelogMapController(viewId, (point) {
      widget.onPinDropped?.call(point);
    });
    _pushData();
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _followUser = true);
    await _controller?.centerOnUser();
    _pushData();
  }

  void _cycleMapType() {
    setState(() {
      _mapType = LifelogMapType.values[
          (_mapType.index + 1) % LifelogMapType.values.length];
    });
    _pushData();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LifelogPalette.of(context);
    if (!isNativeMapAvailable) {
      return SizedBox(
        height: widget.height,
        child: _SchematicFromMapData(data: widget.data),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: UiKitView(
                viewType: 'lifelog/map',
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: _effectiveData.toJson(),
                onPlatformViewCreated: _onCreated,
              ),
            ),
            if (widget.data.crosshair)
              IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.center_focus_strong_rounded,
                    size: 36,
                    color: palette.place,
                  ),
                ),
              ),
            if (widget.showControls)
              Positioned(
                right: Insets.sm,
                top: Insets.sm,
                child: Column(
                  children: [
                    _MapButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Center on my location',
                      onPressed: _locate,
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.fit_screen_outlined,
                      tooltip: 'Show all places and route',
                      onPressed: () => _controller?.fitAll(),
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.layers_outlined,
                      tooltip: 'Change map style',
                      onPressed: _cycleMapType,
                    ),
                    if (widget.showDropPin && widget.onPinDropped != null) ...[
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.add_location_alt_outlined,
                        tooltip: 'Drop a pin at the map center',
                        onPressed: () => _controller?.dropPinAtCenter(),
                        filled: true,
                      ),
                    ],
                  ],
                ),
              ),
            Positioned(
              left: Insets.sm,
              bottom: Insets.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  widget.data.privateMode
                      ? 'Privacy mode · names hidden'
                      : 'Apple Maps · drag to explore · long-press to pin',
                  style: context.text.labelSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 10,
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

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: filled
            ? Theme.of(context).colorScheme.primary
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        child: IconButton(
          iconSize: 20,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: filled
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _SchematicFromMapData extends StatelessWidget {
  const _SchematicFromMapData({required this.data});

  final LifelogMapData data;

  @override
  Widget build(BuildContext context) {
    final places = data.places
        .where((point) => point.kind == 'place')
        .map(
          (point) => Place(
            id: point.id,
            name: data.privateMode ? 'Hidden place' : point.name,
            createdAt: DateTime.now(),
            latitude: point.latitude,
            longitude: point.longitude,
            radiusMeters: point.radiusMeters,
            notes: point.notes,
            colorValue: point.color,
          ),
        )
        .toList();
    final samples = data.route
        .map(
          (point) => LocationSample(
            id: point.id,
            recordedAt: DateTime.now(),
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        )
        .toList();
    return SchematicMap(
      places: places,
      visits: const [],
      samples: samples,
      privateMode: data.privateMode,
      height: double.infinity,
    );
  }
}

/// Opens a full-screen map for choosing an exact point. The person drags the
/// map until the crosshair is over the intended building or landmark, then
/// confirms. Reverse geocoding fills a useful default name.
Future<MapPoint?> showMapPinPicker(
  BuildContext context, {
  MapPoint? initial,
}) {
  return Navigator.of(context, rootNavigator: true).push<MapPoint>(
    MaterialPageRoute<MapPoint>(
      fullscreenDialog: true,
      builder: (_) => _MapPinPickerPage(initial: initial),
    ),
  );
}

class _MapPinPickerPage extends ConsumerStatefulWidget {
  const _MapPinPickerPage({this.initial});

  final MapPoint? initial;

  @override
  ConsumerState<_MapPinPickerPage> createState() => _MapPinPickerPageState();
}

class _MapPinPickerPageState extends ConsumerState<_MapPinPickerPage> {
  MapPoint? _picked;
  bool _lookingUp = false;

  Future<void> _namePoint(MapPoint point) async {
    if (!isNativeMapAvailable) return;
    setState(() => _lookingUp = true);
    try {
      final result = await ref
          .read(mapSearchServiceProvider)
          .reverseGeocode(point.latitude, point.longitude);
      if (!mounted || result == null) return;
      final title = result.title.trim().isEmpty ? point.name : result.title.trim();
      setState(() {
        _picked = MapPoint(
          latitude: point.latitude,
          longitude: point.longitude,
          id: point.id,
          name: title,
          color: point.color,
          radiusMeters: point.radiusMeters,
          kind: point.kind,
          notes: result.subtitle,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _lookingUp = false);
      return;
    }
    if (mounted) setState(() => _lookingUp = false);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    final picked = _picked;
    final data = LifelogMapData(
      places: initial == null ? const [] : [initial],
      stops: const [],
      route: const [],
      current: initial,
      crosshair: true,
      fitOnLoad: initial == null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose exact location'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Text(
                'Drag the map so the crosshair sits on the building, business '
                'or landmark, then tap the pin button. Long-press also works.',
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.mutedText,
                ),
              ),
            ),
            Expanded(
              child: DetailedMap(
                data: data,
                height: double.infinity,
                onPinDropped: (point) {
                  setState(() => _picked = point);
                  unawaited(_namePoint(point));
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: context.palette.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    picked == null
                        ? 'No point selected yet'
                        : '${picked.name.isEmpty ? 'Selected point' : picked.name}\n'
                            '${picked.latitude.toStringAsFixed(6)}, '
                            '${picked.longitude.toStringAsFixed(6)}',
                    style: context.text.bodyMedium,
                  ),
                  if (_lookingUp)
                    const Padding(
                      padding: EdgeInsets.only(top: Insets.xs),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  const SizedBox(height: Insets.sm),
                  FilledButton.icon(
                    onPressed: picked == null
                        ? null
                        : () => Navigator.of(context).pop(picked),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use this point'),
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
