import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers/providers.dart';
import '../../app/providers/settings_provider.dart';
import '../../core/util/dates.dart';
import '../../domain/models/places.dart';
import 'background_location_channel.dart';
import 'location_tracking.dart';
import 'place_name_resolver.dart';

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
  LocationSample? _lastAcceptedSample;

  BackgroundLocationChannel get _channel =>
      ref.read(backgroundLocationChannelProvider);

  /// Call once after app startup to begin tracking if enabled.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    final settings = ref.read(settingsProvider);
    _lastAcceptedSample = ref
        .read(archiveProvider)
        .locationSamplesOn(DateTime.now())
        .fold<LocationSample?>(
          null,
          (previous, sample) =>
              previous == null || sample.recordedAt.isAfter(previous.recordedAt)
                  ? sample
                  : previous,
        );
    if (settings.locationTrackingEnabled) {
      await _startOrRefresh(requestPermission: false);
    }
    if (settings.backgroundLocationEnabled) {
      await _startBackground();
    } else {
      // Clear any events queued before the user disabled background tracking.
      unawaited(_channel.clearPending());
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

  /// Returns the effective native status so the UI can show Needs Always /
  /// Restricted / Off instead of blindly showing On.
  Future<BackgroundLocationStatus> setBackgroundEnabled(bool enabled) async {
    await ref
        .read(settingsProvider.notifier)
        .setBackgroundLocationEnabled(enabled);
    if (enabled) {
      return _startBackground();
    }
    return _stopBackground();
  }

  /// Current effective status, including in-app toggles and iOS authorization.
  Future<BackgroundLocationStatus> backgroundStatus() =>
      _channel.status(enabled: ref.read(settingsProvider).backgroundLocationEnabled);

  /// Capture a sample now (if possible) and refresh today's auto visits.
  Future<bool> recordNow({bool requestPermission = true}) async {
    return _captureAndUpdate(force: true, requestPermission: requestPermission);
  }

  /// Flush events collected by iOS while the app was suspended or terminated.
  ///
  /// [takePending] is a non-destructive peek. Only ids whose samples were
  /// successfully written to the archive are acked; failures stay queued for
  /// the next flush. Returns the number of saved events, not the number read.
  Future<int> flushBackgroundEvents() async {
    final events = await _channel.takePending();
    final persistedIds = <String>[];
    final days = <DateTime>{};
    for (final event in events) {
      try {
        final touched = await _storeBackgroundEvent(event);
        days.addAll(touched);
        if (event.id.isNotEmpty) persistedIds.add(event.id);
      } catch (_) {
        // Keep this event native-side so the next flush can retry it.
      }
    }
    final savedIds = ackableBackgroundEventIds(events, persistedIds);
    if (savedIds.isNotEmpty) {
      await _channel.ackPending(savedIds);
    }
    for (final day in days) {
      await _refreshVisitsForDay(day);
    }
    return savedIds.length;
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
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 10,
                timeLimit: const Duration(seconds: 15),
                pauseLocationUpdatesAutomatically: false,
                // Continuous background GPS needs UIBackgroundModes; visits and
                // significant-change events are handled by the native manager.
                allowBackgroundLocationUpdates: false,
              )
            : AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 10,
                timeLimit: const Duration(seconds: 15),
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
    final previous = _lastAcceptedSample;
    final sample = LocationTracking.sampleFromPosition(position, now: now);
    if (sample == null) return;
    if (previous != null &&
        !LocationTracking.isPlausiblePosition(position, previous, now: now)) {
      return;
    }
    final lastStream = _lastStreamSampleAt;
    final moved = previous == null ||
        LocationTracking.distanceMeters(
              previous.latitude,
              previous.longitude,
              sample.latitude,
              sample.longitude,
            ) >=
            15;
    if (lastStream != null &&
        now.difference(lastStream) < const Duration(seconds: 30) &&
        !moved) {
      return;
    }
    _lastStreamSampleAt = now;
    _lastSampleAt = now;
    _lastAcceptedSample = sample;
    await ref.read(archiveProvider.notifier).addLocationSample(sample);
    await _refreshVisitsForDay(sample.recordedAt);
  }

  Future<BackgroundLocationStatus> _startBackground() async {
    if (!ref.read(settingsProvider).backgroundLocationEnabled) {
      return _channel.status(enabled: false);
    }
    final status = await _channel.setEnabled(true);
    if (_backgroundStarted) return status;
    _backgroundStarted = true;
    _backgroundSub ??= _channel.events.listen(
      (event) => unawaited(_handleBackgroundEvent(event)),
      onError: (_) {},
    );
    _flushTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(flushBackgroundEvents());
    });
    await flushBackgroundEvents();
    return status;
  }

  Future<BackgroundLocationStatus> _stopBackground() async {
    _backgroundStarted = false;
    final status = await _channel.setEnabled(false);
    // The native side also clears on setEnabled(false); this makes the intent
    // explicit and covers older native builds.
    await _channel.clearPending();
    await _backgroundSub?.cancel();
    _backgroundSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    return status;
  }

  Future<void> _handleBackgroundEvent(BackgroundVisitEvent event) async {
    final days = await _storeBackgroundEvent(event);
    // Same ack path as the periodic flush: native queue entries are removed
    // only after the samples are in the encrypted archive.
    if (event.id.isNotEmpty) {
      await _channel.ackPending([event.id]);
    }
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
        previous: _lastAcceptedSample,
      );
      if (position == null) return false;
      final sample = LocationTracking.sampleFromPosition(position);
      if (sample == null) return false;
      if (_lastAcceptedSample != null &&
          !LocationTracking.isPlausiblePosition(
            position,
            _lastAcceptedSample!,
          )) {
        return false;
      }
      _lastSampleAt = sample.recordedAt;
      _lastAcceptedSample = sample;
      await ref.read(archiveProvider.notifier).addLocationSample(sample);
      await _refreshVisitsForDay(sample.recordedAt);
      return true;
    } finally {
      _sampling = false;
    }
  }

  Future<void> _refreshVisitsForDay(DateTime day) async {
    final lookup = ref.read(settingsProvider).placeLookupEnabled;
    if (lookup) {
      // Name unsaved stays of 5+ minutes (bounded, failures are ignored).
      final summary =
          LocationTracking.summarizeDay(ref.read(archiveProvider), day);
      var budget = 3;
      for (final seg in summary.segments) {
        if (!seg.wantsName || budget == 0) continue;
        final lat = seg.latitude!;
        final lon = seg.longitude!;
        if (PlaceNameResolver.instance.hasAttempted(lat, lon)) continue;
        budget--;
        try {
          await PlaceNameResolver.instance.resolve(lat, lon);
        } catch (_) {}
      }
    }
    final archive = ref.read(archiveProvider);
    final visits = LocationTracking.computeAutoVisitsForDay(
      archive,
      day,
      nameFor: lookup ? PlaceNameResolver.instance.cached : null,
    );
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
