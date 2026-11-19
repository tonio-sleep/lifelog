import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/util/dates.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/places.dart';
import '../../domain/models/timeline.dart';

const _uuid = Uuid();

enum DayLocationKind { stay, travel }

class DayLocationSegment {
  const DayLocationSegment({
    required this.kind,
    required this.label,
    required this.startAt,
    required this.endAt,
    required this.isCurrent,
    this.placeId,
    this.distanceMeters,
    this.detail,
  });

  final DayLocationKind kind;
  final String label;
  final DateTime startAt;
  final DateTime endAt;
  final bool isCurrent;
  final String? placeId;
  final double? distanceMeters;
  final String? detail;

  Duration get duration =>
      endAt.isAfter(startAt) ? endAt.difference(startAt) : Duration.zero;

  bool get isTravel => kind == DayLocationKind.travel;
}

class DayLocationStatus {
  const DayLocationStatus({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.since,
    required this.lastUpdated,
    this.placeId,
    this.isCurrent = true,
  });

  final DayLocationKind kind;
  final String title;
  final String subtitle;
  final DateTime since;
  final DateTime lastUpdated;
  final String? placeId;
  final bool isCurrent;

  Duration get duration => lastUpdated.isAfter(since)
      ? lastUpdated.difference(since)
      : Duration.zero;
}

class DayLocationSummary {
  const DayLocationSummary({
    required this.day,
    required this.segments,
    required this.sampleCount,
    this.status,
    this.mostStayLabel,
    this.mostStayDuration = Duration.zero,
    this.mostStayPlaceId,
  });

  final DateTime day;
  final List<DayLocationSegment> segments;
  final int sampleCount;
  final DayLocationStatus? status;
  final String? mostStayLabel;
  final Duration mostStayDuration;
  final String? mostStayPlaceId;

  Duration get travelDuration => segments
      .where((s) => s.isTravel)
      .fold(Duration.zero, (sum, s) => sum + s.duration);

  Duration get stayDuration => segments
      .where((s) => !s.isTravel)
      .fold(Duration.zero, (sum, s) => sum + s.duration);

  int get placeCount => segments
      .where((s) => !s.isTravel)
      .map((s) => s.placeId ?? 'label:${s.label}')
      .toSet()
      .length;
}

class LocationTracking {
  const LocationTracking._();

  /// Minimum interval between stored samples when tracking periodically.
  static const sampleInterval = Duration(minutes: 10);

  /// Capture the current device position, if permission/services allow.
  /// Returns null when unavailable or denied.
  static Future<Position?> getCurrentPosition({
    bool requestPermission = false,
  }) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // Allow while-in-use as well as always for foreground sampling.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static LocationSample? sampleFromPosition(Position position) {
    final accuracy = position.accuracy;
    // Ignore very inaccurate fixes (> 1km) when possible.
    if (accuracy.isFinite && accuracy > 1000) return null;
    final speed = position.speed;
    final speedMps = speed.isFinite && speed >= 0 ? speed : null;
    return LocationSample(
      id: _uuid.v4(),
      recordedAt: DateTime.now(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: accuracy.isFinite ? accuracy : null,
      speedMps: speedMps,
    );
  }

  /// Compute auto-tracked visits for [day] from stored location samples.
  /// Manual (non-auto) visits are preserved by the caller.
  static List<Visit> computeAutoVisitsForDay(Archive archive, DateTime day) {
    final summary = summarizeDay(archive, day);
    final segments = summary.segments;
    if (segments.isEmpty) return const [];
    final key = dayKey(day);

    // Find top stay segment key for "most time" note.
    final stayTotals = <String, Duration>{};
    for (final seg in segments.where((s) => !s.isTravel)) {
      final k = seg.placeId != null ? 'place:${seg.placeId}' : 'stay:${seg.label}';
      stayTotals[k] = (stayTotals[k] ?? Duration.zero) + seg.duration;
    }
    String? topKey;
    Duration topDur = Duration.zero;
    stayTotals.forEach((k, d) {
      if (d > topDur) {
        topDur = d;
        topKey = k;
      }
    });

    final visits = <Visit>[];
    var index = 0;
    for (final seg in segments) {
      final minutes = seg.duration.inMinutes;
      if (minutes < 3 && segments.length > 1) continue;
      final segKey = seg.placeId != null
          ? 'place:${seg.placeId}'
          : seg.isTravel
              ? 'travel'
              : 'stay:${seg.label}';
      final isTopStay = !seg.isTravel && segKey == topKey && topDur.inMinutes >= 10;
      final noteParts = <String>[
        'Auto-tracked from location samples',
        if (seg.isTravel) 'Time spent traveling/on the move',
        if (!seg.isTravel && seg.placeId == null) 'Location not matched to a saved place',
        if (isTopStay) 'Most time this day',
        if (seg.isTravel && seg.distanceMeters != null && seg.distanceMeters! >= 100)
          'About ${(seg.distanceMeters! / 1000).toStringAsFixed(seg.distanceMeters! >= 10000 ? 0 : 1)} km moved',
      ];
      visits.add(
        Visit(
          id: 'auto-loc-$key-$index',
          label: seg.label,
          startAt: seg.startAt,
          endAt: seg.endAt.isAfter(seg.startAt) ? seg.endAt : null,
          placeId: seg.placeId,
          confidence: TimelineConfidence.suggested,
          notes: noteParts.join(' · '),
        ),
      );
      index++;
    }

    if (visits.isEmpty && segments.isNotEmpty) {
      final first = segments.first;
      final last = segments.last;
      visits.add(
        Visit(
          id: 'auto-loc-$key-0',
          label: summary.mostStayLabel ?? first.label,
          startAt: first.startAt,
          endAt: last.endAt.isAfter(first.startAt) ? last.endAt : null,
          placeId: summary.mostStayPlaceId ?? first.placeId,
          confidence: TimelineConfidence.suggested,
          notes: 'Auto-tracked from location samples',
        ),
      );
    }
    return visits;
  }

  /// Summarize where most time was spent for [day] based on samples/auto visits.
  static ({String label, Duration duration, String? placeId})? mostOfDay(
    Archive archive,
    DateTime day,
  ) {
    final summary = summarizeDay(archive, day);
    if (summary.mostStayLabel == null || summary.mostStayDuration <= Duration.zero) {
      if (summary.segments.isEmpty) return null;
      // Fallback to any segment total if no stay segments.
      final totals = <String, Duration>{};
      final labels = <String, String>{};
      final placeIds = <String, String?>{};
      for (final seg in summary.segments) {
        final k = seg.placeId ?? seg.label;
        totals[k] = (totals[k] ?? Duration.zero) + seg.duration;
        labels[k] = seg.label;
        placeIds[k] = seg.placeId;
      }
      String top = totals.keys.first;
      for (final e in totals.entries) {
        if (e.value > totals[top]!) top = e.key;
      }
      return (label: labels[top] ?? top, duration: totals[top]!, placeId: placeIds[top]);
    }
    return (
      label: summary.mostStayLabel!,
      duration: summary.mostStayDuration,
      placeId: summary.mostStayPlaceId,
    );
  }

  /// Rich day summary including journey segments, travel/stay, and current status.
  static DayLocationSummary summarizeDay(Archive archive, DateTime day) {
    final samples = archive.locationSamplesOn(day);
    if (samples.isEmpty) {
      return DayLocationSummary(day: day, segments: const [], sampleCount: 0);
    }
    final places = archive.places.where((p) => p.hasCoordinates).toList();
    final now = DateTime.now();
    final isToday = sameDay(day, now);

    final raw = <_RawSegment>[];
    for (var i = 0; i < samples.length; i++) {
      final a = samples[i];
      final b = i + 1 < samples.length ? samples[i + 1] : null;
      final start = a.recordedAt;
      final end = b?.recordedAt ?? _endForLastSample(a, day);
      final attr = _attribute(a, places);
      final move = b == null ? _MoveInfo.stay() : _movement(a, b);
      final kind = move.traveling ? DayLocationKind.travel : DayLocationKind.stay;
      raw.add(
        _RawSegment(
          start: start,
          end: end,
          kind: kind,
          attr: attr,
          distanceMeters: move.distanceMeters,
        ),
      );
    }

    // Merge consecutive segments of same kind+place/label.
    final merged = <_RawSegment>[];
    for (final seg in raw) {
      if (merged.isEmpty) {
        merged.add(seg.copy());
        continue;
      }
      final last = merged.last;
      if (last.canMergeWith(seg)) {
        last.end = seg.end;
        last.distanceMeters = (last.distanceMeters ?? 0) + (seg.distanceMeters ?? 0);
      } else {
        merged.add(seg.copy());
      }
    }

    final segments = <DayLocationSegment>[];
    for (var i = 0; i < merged.length; i++) {
      final seg = merged[i];
      final isLast = i == merged.length - 1;
      final isCurrent = isToday && isLast;
      final end = seg.end;
      String label;
      String? detail;
      if (seg.kind == DayLocationKind.travel) {
        label = 'Traveling';
        detail = 'On the move';
      } else {
        label = seg.attr.label == 'Other location' ? 'Another location' : seg.attr.label;
        detail = seg.attr.place == null ? 'Stopped nearby' : 'At this saved place';
      }
      segments.add(
        DayLocationSegment(
          kind: seg.kind,
          label: label,
          startAt: seg.start,
          endAt: end,
          isCurrent: isCurrent,
          placeId: seg.kind == DayLocationKind.stay ? seg.attr.place?.id : null,
          distanceMeters: seg.kind == DayLocationKind.travel ? seg.distanceMeters : null,
          detail: detail,
        ),
      );
    }

    // Most stay
    final stayTotals = <String, Duration>{};
    final stayLabels = <String, String>{};
    final stayPlaceIds = <String, String?>{};
    for (final seg in segments.where((s) => !s.isTravel)) {
      final k = seg.placeId ?? seg.label;
      stayTotals[k] = (stayTotals[k] ?? Duration.zero) + seg.duration;
      stayLabels[k] = seg.label;
      stayPlaceIds[k] = seg.placeId;
    }
    String? topKey;
    Duration topDur = Duration.zero;
    stayTotals.forEach((k, d) {
      if (d > topDur) {
        topDur = d;
        topKey = k;
      }
    });

    final status = _currentStatus(segments, samples.last.recordedAt, isToday);

    return DayLocationSummary(
      day: day,
      segments: segments,
      sampleCount: samples.length,
      status: status,
      mostStayLabel: topKey == null ? null : stayLabels[topKey],
      mostStayDuration: topDur,
      mostStayPlaceId: topKey == null ? null : stayPlaceIds[topKey],
    );
  }

  static DayLocationStatus? _currentStatus(
    List<DayLocationSegment> segments,
    DateTime lastSampleAt,
    bool isToday,
  ) {
    if (segments.isEmpty) return null;
    final last = segments.last;
    final since = last.startAt;
    final updated = last.endAt.isAfter(lastSampleAt) ? last.endAt : lastSampleAt;
    if (last.kind == DayLocationKind.travel) {
      final mins = updated.difference(since).inMinutes;
      return DayLocationStatus(
        kind: DayLocationKind.travel,
        title: 'On the road',
        subtitle: isToday
            ? 'Traveling now${mins > 0 ? ' · for ${formatDurationMinutes(mins)}' : ''}'
            : 'Traveling${mins > 0 ? ' · ${formatDurationMinutes(mins)}' : ''}',
        since: since,
        lastUpdated: updated,
        isCurrent: isToday,
      );
    }
    final mins = updated.difference(since).inMinutes;
    final atLabel = last.label == 'Another location' ? 'At another location' : 'At ${last.label}';
    return DayLocationStatus(
      kind: DayLocationKind.stay,
      title: atLabel,
      subtitle: isToday
          ? (mins > 0 ? 'Here for about ${formatDurationMinutes(mins)}' : 'You are here now')
          : (mins > 0 ? 'For about ${formatDurationMinutes(mins)}' : 'Stopped here'),
      since: since,
      lastUpdated: updated,
      placeId: last.placeId,
      isCurrent: isToday,
    );
  }

  static _MoveInfo _movement(LocationSample a, LocationSample b) {
    final dist = _distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);
    final dt = b.recordedAt.difference(a.recordedAt);
    final seconds = dt.inSeconds <= 0 ? 1 : dt.inSeconds;
    final impliedSpeed = dist / seconds;
    final reportedA = a.speedMps ?? -1;
    final reportedB = b.speedMps ?? -1;
    final reported = math.max(reportedA, reportedB);
    final traveling = (reported >= 2.0) ||
        (impliedSpeed >= 1.8) ||
        (dist >= 300 && seconds <= 20 * 60);
    // But if very close, treat as stay even if speed noisy.
    if (dist < 120 && impliedSpeed < 1.2) {
      return _MoveInfo(traveling: false, distanceMeters: dist);
    }
    return _MoveInfo(traveling: traveling, distanceMeters: dist);
  }

  static _Attr _attribute(LocationSample sample, List<Place> places) {
    Place? best;
    double bestDist = double.infinity;
    for (final place in places) {
      final d = _distanceMeters(
        sample.latitude,
        sample.longitude,
        place.latitude!,
        place.longitude!,
      );
      final radius = place.radiusMeters.isFinite && place.radiusMeters > 0
          ? place.radiusMeters
          : 120.0;
      if (d <= math.max(radius, 80.0) && d < bestDist) {
        best = place;
        bestDist = d;
      }
    }
    if (best != null) {
      return _Attr(place: best, label: best.name, sample: sample);
    }
    return _Attr(place: null, label: 'Other location', sample: sample);
  }

  /// Haversine distance in meters.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      _distanceMeters(lat1, lon1, lat2, lon2);

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  static DateTime _endForLastSample(LocationSample sample, DateTime day) {
    final now = DateTime.now();
    if (sameDay(day, now)) {
      return now.isAfter(sample.recordedAt)
          ? now
          : sample.recordedAt.add(const Duration(minutes: 10));
    }
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59);
    final guess = sample.recordedAt.add(const Duration(minutes: 30));
    if (guess.isBefore(sample.recordedAt)) return sample.recordedAt;
    return guess.isAfter(endOfDay) ? endOfDay : guess;
  }
}

class _MoveInfo {
  const _MoveInfo({required this.traveling, required this.distanceMeters});
  factory _MoveInfo.stay() => const _MoveInfo(traveling: false, distanceMeters: 0);
  final bool traveling;
  final double distanceMeters;
}

class _Attr {
  _Attr({required this.place, required this.label, required this.sample});
  final Place? place;
  final String label;
  final LocationSample sample;
}

class _RawSegment {
  _RawSegment({
    required this.start,
    required this.end,
    required this.kind,
    required this.attr,
    this.distanceMeters,
  });

  final DateTime start;
  DateTime end;
  final DayLocationKind kind;
  final _Attr attr;
  double? distanceMeters;

  _RawSegment copy() => _RawSegment(
        start: start,
        end: end,
        kind: kind,
        attr: attr,
        distanceMeters: distanceMeters,
      );

  bool canMergeWith(_RawSegment other) {
    if (kind != other.kind) return false;
    if (kind == DayLocationKind.travel) return true;
    final a = attr.place?.id;
    final b = other.attr.place?.id;
    if (a != null || b != null) return a != null && a == b;
    return attr.label == other.attr.label;
  }
}

