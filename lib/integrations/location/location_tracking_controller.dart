import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import 'background_location_channel.dart';
import 'location_tracking.dart';

final backgroundLocationChannelProvider =
    Provider<BackgroundLocationChannel>((ref) => BackgroundLocationChannel());

final locationTrackingControllerProvider =
    Provider<LocationTrackingController>((ref) {
  final controller = LocationTrackingController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Samples location while the app is in use and flushes iOS visit events that
/// arrived while it was not. Everything is stored in the encrypted local
/// archive; no coordinates leave the device.
class LocationTrackingController with WidgetsBindingObserver {
  LocationTrackingController(this.ref) {
    WidgetsBinding.instance.addObserver(this);
    ref.listen<bool>(
      settingsProvider.select((s) => s.locationTrackingEnabled),
      (prev, next) {
        if (next) {
          unawaited(_startOrRefresh(requestPermission: false));
        } else {
          _stopTimer();
          _stopPositionStream();
        }
      },
      fireImmediately: false,
    );
    ref.listen<bool>(
      settingsProvider.select((s) => s.backgroundLocationEnabled),
      (prev, next) {
        if (next) {
          unawaited(_startBackground());
        } else {
          unawaited(_stopBackground());
        }
      },
      fireImmediately: false,
    );
  }

  final Ref ref;
  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<BackgroundVisitEvent>? _backgroundSub;
  Timer? _flushTimer;
  bool _sampling = false;
  bool _started = false;
  bool _backgroundStarted = false;
  DateTime? _lastSampleAt;
  DateTime? _lastStreamSampleAt;

  BackgroundLocationChannel get _channel =>
      ref.read(backgroundLocationChannelProvider);

  /// Call once after app startup to begin tracking if enabled.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    final settings = ref.read(settingsProvider);
    if (settings.locationTrackingEnabled) {
      await _startOrRefresh(requestPermission: false);
    }
    if (settings.backgroundLocationEnabled) {
      await _startBackground();
    } else {
      // Clear any events queued before the user disabled background tracking.
      unawaited(_channel.takePending());
    }
  }

  Future<void> setEnabled(bool enabled, {bool requestPermission = true}) async {
    await ref.read(settingsProvider.notifier).setLocationTrackingEnabled(enabled);
    if (enabled) {
      await _startOrRefresh(requestPermission: requestPermission);
    } else {
      _stopTimer();
      _stopPositionStream();
    }
  }

  Future<void> setBackgroundEnabled(bool enabled) async {
    await ref
        .read(settingsProvider.notifier)
        .setBackgroundLocationEnabled(enabled);
    if (enabled) {
      await _startBackground();
    } else {
      await _stopBackground();
    }
  }

  /// Capture a sample now (if possible) and refresh today's auto visits.
  Future<bool> recordNow({bool requestPermission = true}) async {
    return _captureAndUpdate(force: true, requestPermission: requestPermission);
  }

  /// Flush events collected by iOS while the app was suspended or terminated.
  Future<int> flushBackgroundEvents() async {
    final events = await _channel.takePending();
    final days = <DateTime>{};
    for (final event in events) {
      final touched = await _storeBackgroundEvent(event);
      days.addAll(touched);
    }
    for (final day in days) {
      await _refreshVisitsForDay(day);
    }
    return events.length;
  }

  Future<void> _startOrRefresh({required bool requestPermission}) async {
    final enabled = ref.read(settingsProvider).locationTrackingEnabled;
    if (!enabled) return;
    await _captureAndUpdate(force: false, requestPermission: requestPermission);
    _ensureTimer();
    await _startPositionStream();
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

  Future<void> _startPositionStream() async {
    if (_positionSub != null) return;
    if (!ref.read(settingsProvider).locationTrackingEnabled) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final LocationSettings settings =
        defaultTargetPlatform == TargetPlatform.iOS
            ? AppleSettings(
                accuracy: LocationAccuracy.medium,
                distanceFilter: 50,
                timeLimit: const Duration(seconds: 20),
                pauseLocationUpdatesAutomatically: true,
                // Continuous background GPS needs UIBackgroundModes; visits and
                // significant-change events are handled by the native manager.
                allowBackgroundLocationUpdates: false,
              )
            : AndroidSettings(
                accuracy: LocationAccuracy.medium,
                distanceFilter: 50,
                timeLimit: const Duration(seconds: 20),
              );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (position) => unawaited(_storeStreamPosition(position)),
      onError: (_) {
        // The periodic one-shot fallback keeps tracking usable.
      },
    );
  }

  void _stopPositionStream() {
    unawaited(_positionSub?.cancel());
    _positionSub = null;
  }

  Future<void> _storeStreamPosition(Position position) async {
    final now = DateTime.now();
    final last = _lastStreamSampleAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    final sample = LocationTracking.sampleFromPosition(position);
    if (sample == null) return;
    _lastStreamSampleAt = now;
    _lastSampleAt = now;
    await ref.read(archiveProvider.notifier).addLocationSample(sample);
    await _refreshVisitsForDay(now);
  }

  Future<void> _startBackground() async {
    if (_backgroundStarted) return;
    if (!ref.read(settingsProvider).backgroundLocationEnabled) return;
    _backgroundStarted = true;
    await _channel.setEnabled(true);
    _backgroundSub ??= _channel.events.listen(
      (event) => unawaited(_handleBackgroundEvent(event)),
      onError: (_) {},
    );
    _flushTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(flushBackgroundEvents());
    });
    await flushBackgroundEvents();
  }

  Future<void> _stopBackground() async {
    _backgroundStarted = false;
    await _channel.setEnabled(false);
    await _backgroundSub?.cancel();
    _backgroundSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<void> _handleBackgroundEvent(BackgroundVisitEvent event) async {
    final days = await _storeBackgroundEvent(event);
    for (final day in days) {
      await _refreshVisitsForDay(day);
    }
  }

  /// Turns one native event into one or two location samples. Arrival and
  /// departure samples let the existing stay/travel detector produce a visit.
  Future<Set<DateTime>> _storeBackgroundEvent(BackgroundVisitEvent event) async {
    final archive = ref.read(archiveProvider.notifier);
    final touched = <DateTime>{dayStart(event.startedAt)};

    await archive.addLocationSample(backgroundArrivalSample(event));
    final departure = backgroundDepartureSample(event);
    if (departure != null) {
      touched.add(dayStart(departure.recordedAt));
      await archive.addLocationSample(departure);
    }
    return touched;
  }

  Future<void> _tick() async {
    final settings = ref.read(settingsProvider);
    if (!settings.locationTrackingEnabled) {
      _stopTimer();
      _stopPositionStream();
      return;
    }
    if (settings.backgroundLocationEnabled) {
      await flushBackgroundEvents();
    }
    final last = _lastSampleAt;
    if (last != null &&
        DateTime.now().difference(last) < LocationTracking.sampleInterval) {
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
      if (ref.read(settingsProvider).backgroundLocationEnabled) {
        unawaited(flushBackgroundEvents());
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    _stopPositionStream();
    unawaited(_backgroundSub?.cancel());
    _backgroundSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
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
