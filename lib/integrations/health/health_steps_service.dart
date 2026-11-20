import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

/// Small wrapper around the health plugin's native method channel.
///
/// The plugin itself does not expose an iOS availability API to Dart, but its
/// `flutter_health` channel handles `checkIfHealthDataAvailable`. We call it
/// directly and fall back to the previous configure-based heuristic if the
/// plugin is missing or the call fails.
class _HealthNativeAvailability {
  static const MethodChannel _channel = MethodChannel('flutter_health');

  Future<bool?> isHealthDataAvailableOnIOS() async {
    try {
      return await _channel.invokeMethod<bool>('checkIfHealthDataAvailable');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}

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

  bool get hasSteps => steps != null;
  bool get hasSleep => sleepHours != null;

  /// True only when at least one value was actually read from Health.
  bool get hasData => hasSteps || hasSleep;
  bool get hasAnyData => hasData;

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
///   A successful authorization request is only "requested"; an actual readable
///   value is the only honest "readable" signal.
/// - Sleep can be reported as multiple/overlapping samples and stages; we merge
///   overlapping intervals using exact durations and round only once.
enum HealthAccessState { unavailable, unknown, requested, readable }

/// A privacy-safe status snapshot for onboarding/settings.
class HealthAccessStatus {
  const HealthAccessStatus({
    required this.state,
    this.supported = false,
    this.available = false,
    this.stepsReadable = false,
    this.sleepReadable = false,
  });

  final HealthAccessState state;
  final bool supported;
  final bool available;
  final bool stepsReadable;
  final bool sleepReadable;

  bool get isReadable => state == HealthAccessState.readable;
  bool get canRequest => supported && available;

  HealthAccessStatus copyWith({
    HealthAccessState? state,
    bool? supported,
    bool? available,
    bool? stepsReadable,
    bool? sleepReadable,
  }) {
    return HealthAccessStatus(
      state: state ?? this.state,
      supported: supported ?? this.supported,
      available: available ?? this.available,
      stepsReadable: stepsReadable ?? this.stepsReadable,
      sleepReadable: sleepReadable ?? this.sleepReadable,
    );
  }
}

class HealthStepsService {
  final Health _health = Health();
  final _HealthNativeAvailability _native = _HealthNativeAvailability();

  HealthAccessState _lastAccessState = HealthAccessState.unknown;

  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Whether the platform's health store exists on this device. HealthKit is
  /// not available on iPad, and Health Connect may not be installed on Android.
  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    if (Platform.isAndroid) {
      try {
        return await _health.isHealthConnectAvailable();
      } catch (_) {
        return false;
      }
    }
    // Real iOS check via the plugin's native channel, with a safe fallback.
    final nativeAvailable = await _native.isHealthDataAvailableOnIOS();
    if (nativeAvailable != null) return nativeAvailable;
    try {
      await configureIfNeeded();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Requests read authorization and returns a clean status object.
  ///
  /// A successful request is always [HealthAccessState.requested]. iOS does not
  /// disclose read grants, so we never claim "readable" from a prompt result.
  Future<HealthAccessStatus> requestAccessDetailed() async {
    if (!await isAvailable()) {
      final status = HealthAccessStatus(
        state: HealthAccessState.unavailable,
        supported: isSupported,
      );
      _lastAccessState = status.state;
      return status;
    }
    try {
      await configureIfNeeded();
      await _health.requestAuthorization(
        _allTypes,
        permissions: _readPermissionsFor(_allTypes),
      );
      final status = HealthAccessStatus(
        state: HealthAccessState.requested,
        supported: true,
        available: true,
      );
      _lastAccessState = status.state;
      return status;
    } catch (_) {
      final status = HealthAccessStatus(
        state: HealthAccessState.unknown,
        supported: isSupported,
        available: true,
      );
      _lastAccessState = status.state;
      return status;
    }
  }

  /// Convenience wrapper returning only the state from [requestAccessDetailed].
  Future<HealthAccessState> requestAccess() async =>
      (await requestAccessDetailed()).state;

  /// Re-checks what can actually be observed. Only a readable value upgrades
  /// the state to [HealthAccessState.readable]; a prior request stays
  /// [HealthAccessState.requested] until data is actually available.
  Future<HealthAccessStatus> refreshAccessStatus() async {
    if (!await isAvailable()) {
      return HealthAccessStatus(
        state: HealthAccessState.unavailable,
        supported: isSupported,
      );
    }
    DailyHealthSummary summary;
    try {
      summary = await getDailySummary(DateTime.now());
    } catch (_) {
      summary = const DailyHealthSummary();
    }
    final state = summary.hasData
        ? HealthAccessState.readable
        : _lastAccessState;
    return HealthAccessStatus(
      state: state,
      supported: true,
      available: true,
      stepsReadable: summary.hasSteps,
      sleepReadable: summary.hasSleep,
    );
  }

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

  /// Raw plugin permission result. Returns null on iOS for read access because
  /// HealthKit intentionally hides it. Prefer [requestAccessDetailed] /
  /// [refreshAccessStatus] for UI state.
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

  /// Returns true only when the authorization request was successfully made.
  /// This is *not* a claim that data is readable; use [requestAccessDetailed]
  /// or [refreshAccessStatus] for status.
  Future<bool> requestPermission() async {
    final status = await requestAccessDetailed();
    return status.state == HealthAccessState.requested;
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

        final mergedMicroseconds = _mergedOverlapMicroseconds(source, start, end);
        if (mergedMicroseconds > 0) {
          // Accumulate exact microsecond durations and round once, so several
          // sub-minute stage samples are not silently truncated to zero.
          sleepHours = ((mergedMicroseconds / Duration.microsecondsPerHour) * 100)
              .roundToDouble() /
              100.0;
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

  int _mergedOverlapMicroseconds(
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
    var total = Duration.zero;
    var curStart = intervals.first.from;
    var curEnd = intervals.first.to;
    for (var i = 1; i < intervals.length; i++) {
      final it = intervals[i];
      if (!it.from.isAfter(curEnd)) {
        if (it.to.isAfter(curEnd)) curEnd = it.to;
        continue;
      }
      total += curEnd.difference(curStart);
      curStart = it.from;
      curEnd = it.to;
    }
    total += curEnd.difference(curStart);
    return math.max(0, total.inMicroseconds);
  }
}
