import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import 'location_tracking.dart';

final locationTrackingControllerProvider =
    Provider<LocationTrackingController>((ref) {
  final controller = LocationTrackingController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Samples the device location while the app is in use (when enabled) and
/// derives on-device visits like "where we were for most of the day".
///
/// Tracking is local-only: samples and derived visits are stored in the
/// encrypted archive. No coordinates are sent to third parties by this feature.
class LocationTrackingController with WidgetsBindingObserver {
  LocationTrackingController(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    // React to enable/disable changes.
    ref.listen<bool>(
      settingsProvider.select((s) => s.locationTrackingEnabled),
      (prev, next) {
        if (next) {
          unawaited(_startOrRefresh(requestPermission: false));
        } else {
          _stopTimer();
        }
      },
      fireImmediately: false,
    );
  }

  final Ref ref;
  Timer? _timer;
  bool _sampling = false;
  DateTime? _lastSampleAt;
  bool _started = false;

  /// Call once after app startup to begin tracking if enabled.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    final enabled = ref.read(settingsProvider).locationTrackingEnabled;
    if (enabled) {
      await _startOrRefresh(requestPermission: false);
    }
  }

  Future<void> setEnabled(bool enabled, {bool requestPermission = true}) async {
    await ref.read(settingsProvider.notifier).setLocationTrackingEnabled(enabled);
    if (enabled) {
      await _startOrRefresh(requestPermission: requestPermission);
    } else {
      _stopTimer();
    }
  }

  /// Capture a sample now (if possible) and refresh today's auto visits.
  Future<bool> recordNow({bool requestPermission = true}) async {
    return _captureAndUpdate(force: true, requestPermission: requestPermission);
  }

  Future<void> _startOrRefresh({required bool requestPermission}) async {
    final enabled = ref.read(settingsProvider).locationTrackingEnabled;
    if (!enabled) return;
    await _captureAndUpdate(force: false, requestPermission: requestPermission);
    _ensureTimer();
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_tick());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final enabled = ref.read(settingsProvider).locationTrackingEnabled;
    if (!enabled) {
      _stopTimer();
      return;
    }
    // Only sample at the configured interval.
    final last = _lastSampleAt;
    if (last != null &&
        DateTime.now().difference(last) < LocationTracking.sampleInterval) {
      // Still refresh visits in case day rolled over/time progressed.
      await _refreshVisitsForDay(DateTime.now());
      return;
    }
    await _captureAndUpdate(force: false, requestPermission: false);
  }

  Future<bool> _captureAndUpdate({
    required bool force,
    required bool requestPermission,
  }) async {
    final enabled = ref.read(settingsProvider).locationTrackingEnabled;
    if (!enabled) return false;
    if (_sampling) return false;
    final last = _lastSampleAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < LocationTracking.sampleInterval) {
      await _refreshVisitsForDay(DateTime.now());
      return false;
    }
    _sampling = true;
    try {
      final position = await LocationTracking.getCurrentPosition(
        requestPermission: requestPermission,
      );
      if (position == null) return false;
      final sample = LocationTracking.sampleFromPosition(position);
      if (sample == null) return false;
      _lastSampleAt = sample.recordedAt;
      await ref.read(archiveProvider.notifier).addLocationSample(sample);
      await _refreshVisitsForDay(sample.recordedAt);
      return true;
    } finally {
      _sampling = false;
    }
  }

  Future<void> _refreshVisitsForDay(DateTime day) async {
    final archive = ref.read(archiveProvider);
    final visits = LocationTracking.computeAutoVisitsForDay(archive, day);
    await ref
        .read(archiveProvider.notifier)
        .replaceAutoVisitsForDay(dayStart(day), visits);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startOrRefresh(requestPermission: false));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Keep timer cheap; it will be checked on resume. We don't stop entirely
      // so a quick return can still tick, but sampling is interval-gated.
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
  }
}

class LocationTrackingHost extends ConsumerStatefulWidget {
  const LocationTrackingHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LocationTrackingHost> createState() =>
      _LocationTrackingHostState();
}

class _LocationTrackingHostState extends ConsumerState<LocationTrackingHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(locationTrackingControllerProvider).ensureStarted());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
