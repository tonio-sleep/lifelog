import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class DailyHealthSummary {
  const DailyHealthSummary({this.steps, this.sleepHours});

  final int? steps;
  final double? sleepHours;

  bool get hasData => steps != null || sleepHours != null;
}

/// Reads daily health data from Apple Health (iOS) / Health Connect (Android)
/// when available. On unsupported platforms this is a no-op.
class HealthStepsService {
  final Health _health = Health();

  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static const _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
  ];
  static final _permissions = List<HealthDataAccess>.filled(
    _types.length,
    HealthDataAccess.READ,
  );

  Future<bool?> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _health.hasPermissions(_types, permissions: _permissions);
    } catch (_) {
      return null;
    }
  }

  Future<void> configureIfNeeded() async {
    if (!isSupported) return;
    try {
      await _health.configure();
    } catch (_) {
      // Best effort; some platforms/configurations may not require or support this.
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      await configureIfNeeded();
      final granted = await _health.requestAuthorization(
        _types,
        permissions: _permissions,
      );
      if (granted) return true;
      // iOS read permissions are privacy-restricted; hasPermissions may be null.
      final status = await hasPermission();
      return status == true;
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

    if (includeSteps) {
      try {
        if (effectiveEnd.isAfter(start)) {
          steps = await _health.getTotalStepsInInterval(start, effectiveEnd);
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
          types: const [HealthDataType.SLEEP_ASLEEP, HealthDataType.SLEEP_IN_BED],
          startTime: start.subtract(const Duration(hours: 12)),
          endTime: end.add(const Duration(hours: 12)),
        );
        // Prefer asleep samples when present, otherwise fall back to in-bed.
        final asleep = points
            .where((p) => p.type == HealthDataType.SLEEP_ASLEEP)
            .toList();
        final source = asleep.isNotEmpty
            ? asleep
            : points.where((p) => p.type == HealthDataType.SLEEP_IN_BED).toList();

        var totalMinutes = 0.0;
        for (final p in source) {
          final from = p.dateFrom.isAfter(start) ? p.dateFrom : start;
          final to = p.dateTo.isBefore(end) ? p.dateTo : end;
          if (!to.isAfter(from)) continue;
          totalMinutes += to.difference(from).inMinutes;
        }
        sleepHours = totalMinutes <= 0 ? null : totalMinutes / 60.0;
      } catch (_) {
        sleepHours = null;
      }
    }

    return DailyHealthSummary(steps: steps, sleepHours: sleepHours);
  }
}
