import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class DailyHealthSummary {
  const DailyHealthSummary({
    this.steps,
    this.sleepHours,
    this.sleepSampleCount = 0,
    this.syncedAt,
  });

  final int? steps;
  final double? sleepHours;
  final int sleepSampleCount;
  final DateTime? syncedAt;

  bool get hasData => steps != null || sleepHours != null;

  DailyHealthSummary copyWith({
    int? steps,
    double? sleepHours,
    int? sleepSampleCount,
    DateTime? syncedAt,
  }) {
    return DailyHealthSummary(
      steps: steps ?? this.steps,
      sleepHours: sleepHours ?? this.sleepHours,
      sleepSampleCount: sleepSampleCount ?? this.sleepSampleCount,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }
}

/// Reads daily health data from Apple Health (iOS) / Health Connect (Android)
/// when available. On unsupported platforms this is a no-op.
///
/// Notes:
/// - On iOS, HealthKit does not reveal read-permission status for privacy.
///   A successful authorization request or a readable query is the best signal.
/// - Sleep can be reported as multiple/overlapping samples and stages; we merge
///   overlapping intervals to estimate total sleep more accurately.
class HealthStepsService {
  final Health _health = Health();

  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static const _stepTypes = <HealthDataType>[HealthDataType.STEPS];

  // Request a broad set of sleep types where supported by the package/platform.
  // Unsupported types may be ignored by the platform/package at runtime.
  static const _sleepTypes = <HealthDataType>[
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
  ];

  static List<HealthDataType> get _allTypes => [
        ..._stepTypes,
        ..._sleepTypes,
      ];

  static List<HealthDataAccess> _readPermissionsFor(List<HealthDataType> types) =>
      List<HealthDataAccess>.filled(types.length, HealthDataAccess.READ);

  Future<bool?> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _health.hasPermissions(
        _allTypes,
        permissions: _readPermissionsFor(_allTypes),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> configureIfNeeded() async {
    if (!isSupported) return;
    try {
      await _health.configure();
    } catch (_) {
      // Best effort; some platforms/configurations may not require/support this.
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      await configureIfNeeded();
      final granted = await _health.requestAuthorization(
        _allTypes,
        permissions: _readPermissionsFor(_allTypes),
      );
      if (granted) return true;
      // iOS read permissions are privacy-restricted; hasPermissions may be null.
      final status = await hasPermission();
      if (status == true) return true;
      // As a fallback, try a lightweight read to infer access.
      final probe = await getDailySummary(DateTime.now());
      return probe.hasData;
    } catch (_) {
      return false;
    }
  }

  /// Returns total steps for [day] (local day), or null if unavailable.
  Future<int?> getStepsForDay(DateTime day) async {
    final summary = await getDailySummary(day, includeSleep: false);
    return summary.steps;
  }

  /// Returns total sleep duration in hours for [day], or null if unavailable.
  /// Includes sleep sessions that overlap the local day window.
  Future<double?> getSleepHoursForDay(DateTime day) async {
    final summary = await getDailySummary(day, includeSteps: false);
    return summary.sleepHours;
  }

  /// Reads steps and/or sleep for [day] from Health. Returns available values;
  /// missing data remains null.
  Future<DailyHealthSummary> getDailySummary(
    DateTime day, {
    bool includeSteps = true,
    bool includeSleep = true,
  }) async {
    if (!isSupported) return const DailyHealthSummary();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final now = DateTime.now();
    final effectiveEnd = end.isAfter(now) ? now : end;

    int? steps;
    double? sleepHours;
    var sleepSampleCount = 0;

    if (includeSteps) {
      try {
        if (effectiveEnd.isAfter(start)) {
          steps = await _health.getTotalStepsInInterval(start, effectiveEnd);
          if (steps != null && steps < 0) steps = 0;
        } else {
          steps = 0;
        }
      } catch (_) {
        steps = null;
      }
    }

    if (includeSleep) {
      try {
        final points = await _health.getHealthDataFromTypes(
          types: _sleepTypes,
          startTime: start.subtract(const Duration(hours: 18)),
          endTime: end.add(const Duration(hours: 12)),
        );

        // Prefer detailed asleep-stage samples when present, else generic asleep,
        // else in-bed as a fallback estimate.
        final stageTypes = <HealthDataType>{
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_REM,
        };
        final stageSamples = points.where((p) => stageTypes.contains(p.type)).toList();
        final asleepSamples =
            points.where((p) => p.type == HealthDataType.SLEEP_ASLEEP).toList();
        final inBedSamples =
            points.where((p) => p.type == HealthDataType.SLEEP_IN_BED).toList();

        final source = stageSamples.isNotEmpty
            ? stageSamples
            : (asleepSamples.isNotEmpty ? asleepSamples : inBedSamples);
        sleepSampleCount = source.length;

        final mergedMinutes = _mergedOverlapMinutes(source, start, end);
        if (mergedMinutes > 0) {
          sleepHours = (mergedMinutes / 60.0 * 100).roundToDouble() / 100.0;
        } else if (points.isNotEmpty || steps != null) {
          // If we queried successfully but found no sleep in window, keep null
          // (unknown/not recorded) rather than forcing 0.
          sleepHours = null;
        }
      } catch (_) {
        sleepHours = null;
        sleepSampleCount = 0;
      }
    }

    return DailyHealthSummary(
      steps: steps,
      sleepHours: sleepHours,
      sleepSampleCount: sleepSampleCount,
      syncedAt: DateTime.now(),
    );
  }

  double _mergedOverlapMinutes(
    List<HealthDataPoint> points,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final intervals = <({DateTime from, DateTime to})>[];
    for (final p in points) {
      var from = p.dateFrom;
      var to = p.dateTo;
      if (!to.isAfter(from)) continue;
      if (from.isBefore(windowStart)) from = windowStart;
      if (to.isAfter(windowEnd)) to = windowEnd;
      if (!to.isAfter(from)) continue;
      intervals.add((from: from, to: to));
    }
    if (intervals.isEmpty) return 0;

    intervals.sort((a, b) => a.from.compareTo(b.from));
    var totalMinutes = 0.0;
    var curStart = intervals.first.from;
    var curEnd = intervals.first.to;
    for (var i = 1; i < intervals.length; i++) {
      final it = intervals[i];
      if (!it.from.isAfter(curEnd)) {
        if (it.to.isAfter(curEnd)) curEnd = it.to;
        continue;
      }
      totalMinutes += curEnd.difference(curStart).inMinutes;
      curStart = it.from;
      curEnd = it.to;
    }
    totalMinutes += curEnd.difference(curStart).inMinutes;
    return math.max(0.0, totalMinutes);
  }
}
