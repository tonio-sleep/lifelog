import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../domain/models/places.dart';

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
