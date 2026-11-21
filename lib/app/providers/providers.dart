import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/backup/backup_service.dart';
import '../../core/util/dates.dart';
import '../../domain/meals_migration.dart';
import '../../integrations/cloudflare/cloud_sync_engine.dart';
import '../../integrations/cloudflare/cloudflare_sync_service.dart';
import '../../domain/models/archive.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/media.dart';
import '../../domain/models/meals.dart';
import '../../domain/models/music.dart';
import '../../domain/models/places.dart';
import '../../domain/models/timeline.dart';
import '../../domain/models/trackers.dart';
import '../app_services.dart';
import 'settings_provider.dart';

final appServicesProvider = Provider<AppServices>((ref) {
  throw UnimplementedError('AppServices must be overridden at bootstrap.');
});

enum CloudAutoSyncPhase { idle, syncing, saved, failed }

class CloudAutoSyncState {
  const CloudAutoSyncState({
    this.phase = CloudAutoSyncPhase.idle,
    this.error,
    this.lastAttempt,
  });

  final CloudAutoSyncPhase phase;
  final String? error;
  final DateTime? lastAttempt;
}

final cloudAutoSyncProvider =
    NotifierProvider<CloudAutoSyncController, CloudAutoSyncState>(
      CloudAutoSyncController.new,
    );

/// Debounced, retrying cloud-primary sync. Local writes remain fast; the
/// encrypted archive and media objects are pushed in the background with an
/// honest status that never claims success before the Worker accepts bytes.
class CloudAutoSyncController extends Notifier<CloudAutoSyncState> {
  Timer? _debounce;
  Timer? _retry;
  CloudSyncEngine? _engine;
  int _failures = 0;
  bool _disposed = false;

  @override
  CloudAutoSyncState build() {
    final services = ref.watch(appServicesProvider);
    final engine = CloudSyncEngine(
      api: services.cloudflareSync,
      backup: services.backup,
      mediaStore: services.mediaStore,
      credentials: _loadCredentials,
      archive: () async => ref.read(archiveProvider),
      recordSync: (at) =>
          ref.read(settingsProvider.notifier).recordCloudflareSync(at),
    );
    _engine = engine;
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _retry?.cancel();
      services.mediaStore.remoteSource = null;
    });
    return const CloudAutoSyncState();
  }

  Future<CloudSyncCredentials?> _loadCredentials() async {
    final settings = ref.read(settingsProvider);
    if (!settings.cloudflareConnected) return null;
    final workerUrl = settings.cloudflareWorkerUrl?.trim() ?? '';
    final sessionJson = await ref
        .read(settingsProvider.notifier)
        .cloudflareSessionJson();
    final passphrase = await ref
        .read(settingsProvider.notifier)
        .cloudflareBackupPassphrase();
    if (sessionJson == null ||
        passphrase == null ||
        passphrase.trim().isEmpty) {
      throw CloudflareSyncException(
        'Cloud sync is connected but its passphrase is unavailable. Reconnect in Settings.',
      );
    }
    try {
      final map = jsonDecode(sessionJson) as Map<String, dynamic>;
      final token = map['token'] as String? ?? '';
      if (token.isEmpty) {
        throw CloudflareSyncException(
          'Cloud sync session is unavailable. Sign in again.',
        );
      }
      return CloudSyncCredentials(
        workerUrl: workerUrl,
        token: token,
        passphrase: passphrase,
      );
    } on CloudflareSyncException {
      rethrow;
    } catch (_) {
      throw CloudflareSyncException(
        'Cloud sync session could not be read. Sign in again.',
      );
    }
  }

  /// Called after a successful local archive save.
  void schedule({Duration delay = const Duration(milliseconds: 900)}) {
    if (_disposed) return;
    _debounce?.cancel();
    _retry?.cancel();
    _debounce = Timer(delay, () {
      unawaited(_run());
    });
  }

  Future<void> syncNow() => _run();

  Future<void> _run() async {
    final engine = _engine;
    if (_disposed || engine == null) return;
    if (state.phase == CloudAutoSyncPhase.syncing) return;
    if (!ref.read(settingsProvider).cloudflareConnected) {
      // Local-only saves are durable on disk; they are not cloud saves and
      // must not be reported as one.
      if (state.phase != CloudAutoSyncPhase.idle) {
        state = const CloudAutoSyncState();
      }
      return;
    }

    state = CloudAutoSyncState(
      phase: CloudAutoSyncPhase.syncing,
      lastAttempt: DateTime.now(),
    );
    try {
      await engine.syncNow();
      if (_disposed) return;
      _failures = 0;
      state = CloudAutoSyncState(
        phase: CloudAutoSyncPhase.saved,
        lastAttempt: DateTime.now(),
      );
    } catch (error) {
      if (_disposed) return;
      _failures++;
      state = CloudAutoSyncState(
        phase: CloudAutoSyncPhase.failed,
        error: '$error',
        lastAttempt: DateTime.now(),
      );
      final backoff = Duration(seconds: (2 * _failures).clamp(2, 30));
      _retry = Timer(backoff, () {
        unawaited(_run());
      });
    }
  }
}

final archiveProvider = NotifierProvider<ArchiveController, Archive>(
  ArchiveController.new,
);

/// Readable save state for screens that only watch providers. The controller's
/// plain fields are not notifiable, so they are mirrored here.
class ArchiveSaveStatus {
  const ArchiveSaveStatus({this.isSaving = false, this.error});

  final bool isSaving;
  final String? error;
}

class ArchiveSaveStatusController extends Notifier<ArchiveSaveStatus> {
  @override
  ArchiveSaveStatus build() => const ArchiveSaveStatus();

  void update({required bool isSaving, String? error}) {
    state = ArchiveSaveStatus(isSaving: isSaving, error: error);
  }
}

final archiveSaveStatusProvider =
    NotifierProvider<ArchiveSaveStatusController, ArchiveSaveStatus>(
      ArchiveSaveStatusController.new,
    );

/// Incremented whenever media bytes on disk may have changed (for example a
/// restore). Image widgets watch this so they reload cached bytes.
final mediaRevisionProvider = NotifierProvider<MediaRevisionController, int>(
  MediaRevisionController.new,
);

class MediaRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

class MediaWriteException implements Exception {
  MediaWriteException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message Cause: $cause';
}

class ArchiveController extends Notifier<Archive> {
  Future<void> _writeQueue = Future.value();
  int _pendingWrites = 0;

  /// True while any write is queued or in flight, not just the current one.
  bool get isSaving => _pendingWrites > 0;
  String? lastSaveError;

  AppServices get _services => ref.read(appServicesProvider);

  @override
  Archive build() => ref.watch(appServicesProvider).archive;

  void _publishSaveStatus() {
    ref
        .read(archiveSaveStatusProvider.notifier)
        .update(isSaving: isSaving, error: lastSaveError);
  }

  Future<void> _persist(Archive next) {
    state = next;
    final snapshot = next;
    _pendingWrites++;
    _publishSaveStatus();
    final write = _writeQueue.then((_) async {
      try {
        await _services.archiveStore.save(snapshot);
        lastSaveError = null;
        // Local data is now a cache of the new state; push it promptly.
        ref.read(cloudAutoSyncProvider.notifier).schedule();
      } catch (error) {
        lastSaveError = error.toString();
        rethrow;
      } finally {
        _pendingWrites--;
        _publishSaveStatus();
      }
    });
    _writeQueue = write.catchError((_) {});
    return write;
  }

  // ---------------------------------------------------------------------------
  // Journal
  // ---------------------------------------------------------------------------

  Future<void> saveEntry(JournalEntry entry) async {
    final next = state.copy();
    final index = next.entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      next.entries[index] = entry;
    } else {
      next.entries.add(entry);
    }
    await _persist(next);
  }

  Future<void> deleteEntry(String id, {bool deleteMedia = true}) async {
    final next = state.copy();
    final linked = next.media
        .where((m) => m.journalEntryId == id)
        .toList(growable: false);
    next.entries.removeWhere((e) => e.id == id);
    if (deleteMedia) {
      next.media.removeWhere((m) => m.journalEntryId == id);
    } else {
      for (var i = 0; i < next.media.length; i++) {
        if (next.media[i].journalEntryId == id) {
          next.media[i] = next.media[i].copyWith(clearJournalEntry: true);
        }
      }
    }

    // Metadata first: a media file is only removed after the archive no
    // longer references it.
    await _persist(next);
    if (deleteMedia) {
      for (final item in linked) {
        try {
          await _services.mediaStore.delete(item);
        } catch (error) {
          throw MediaWriteException(
            'The entry was deleted, but an attached file could not be removed.',
            error,
          );
        }
      }
    }
  }

  Future<void> archiveEntry(String id) async {
    final existing = state.entryById(id);
    if (existing == null) return;
    await saveEntry(existing.copyWith(archived: !existing.archived));
  }

  Future<void> duplicateEntry(JournalEntry entry) async {
    final copy = JournalEntry(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      title: entry.title,
      body: entry.body,
      kind: entry.kind,
      vocabItems: entry.vocabItems.map((v) => v.copyWith()).toList(),
      mood: entry.mood,
      energy: entry.energy,
      sleepHours: entry.sleepHours,
      steps: entry.steps,
      meals: entry.meals,
      highlight: entry.highlight,
      tags: [...entry.tags],
      placeId: entry.placeId,
      placeLabel: entry.placeLabel,
      draft: true,
    );
    await saveEntry(copy);
  }

  // ---------------------------------------------------------------------------
  // Meals and drinks
  // ---------------------------------------------------------------------------

  Future<void> saveMeal(MealRecord meal) async {
    final next = state.copy();
    final index = next.meals.indexWhere((m) => m.id == meal.id);
    if (index >= 0) {
      next.meals[index] = meal;
    } else {
      next.meals.add(meal);
    }
    next.meals.sort((a, b) => a.at.compareTo(b.at));
    await _persist(next);
  }

  Future<void> deleteMeal(String id) async {
    final next = state.copy()..meals.removeWhere((m) => m.id == id);
    await _persist(next);
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  Future<MediaItem> importMedia({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String caption = '',
    List<String> tags = const [],
    String? journalEntryId,
    DateTime? createdAt,
  }) async {
    final item = await _services.mediaStore.importBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      caption: caption,
      tags: tags,
      journalEntryId: journalEntryId,
      createdAt: createdAt,
    );
    final next = state.copy();
    next.media.add(item);
    await _persist(next);
    return item;
  }

  Future<void> updateMedia(MediaItem item) async {
    final next = state.copy();
    final index = next.media.indexWhere((m) => m.id == item.id);
    if (index >= 0) {
      next.media[index] = item;
      await _persist(next);
    }
  }

  Future<void> deleteMedia(String id) async {
    final media = state.mediaById(id);
    if (media == null) return;
    final next = state.copy()..media.removeWhere((m) => m.id == id);
    await _persist(next);
    try {
      await _services.mediaStore.delete(media);
    } catch (error) {
      throw MediaWriteException(
        'The media record was removed, but its encrypted file could not be '
        'deleted.',
        error,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Trackers
  // ---------------------------------------------------------------------------

  Future<void> saveTracker(TrackerDefinition tracker) async {
    final next = state.copy();
    final index = next.trackers.indexWhere((t) => t.id == tracker.id);
    if (index >= 0) {
      next.trackers[index] = tracker;
    } else {
      final maxOrder = next.trackers.fold<int>(
        -1,
        (value, t) => t.sortOrder > value ? t.sortOrder : value,
      );
      next.trackers.add(tracker.copyWith(sortOrder: maxOrder + 1));
    }
    await _persist(next);
  }

  Future<void> addTrackers(Iterable<TrackerDefinition> trackers) async {
    final next = state.copy();
    for (final tracker in trackers) {
      if (next.trackers.any((t) => t.id == tracker.id)) continue;
      final maxOrder = next.trackers.fold<int>(
        -1,
        (value, t) => t.sortOrder > value ? t.sortOrder : value,
      );
      next.trackers.add(tracker.copyWith(sortOrder: maxOrder + 1));
    }
    await _persist(next);
  }

  Future<void> deleteTracker(String id, {bool deleteRecords = true}) async {
    final next = state.copy()..trackers.removeWhere((t) => t.id == id);
    if (deleteRecords) {
      next.trackerRecords.removeWhere((r) => r.trackerId == id);
    }
    await _persist(next);
  }

  Future<TrackerRecord> logTracker(
    TrackerDefinition tracker, {
    double? value,
    String text = '',
    String note = '',
    DateTime? at,
    DateTime? startedAt,
    DateTime? endedAt,
    double? durationMinutes,
    double? count,
  }) async {
    final record = TrackerRecord(
      id: const Uuid().v4(),
      trackerId: tracker.id,
      recordedAt: at ?? DateTime.now(),
      value: value,
      text: text,
      note: note,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMinutes: durationMinutes,
      count: count,
    );
    final next = state.copy()..trackerRecords.add(record);
    await _persist(next);
    return record;
  }

  /// Toggles a boolean tracker for today and returns whether it is now logged.
  Future<bool> toggleBoolean(TrackerDefinition tracker, DateTime day) async {
    final next = state.copy();
    final existing = next.trackerRecords
        .where((r) => r.trackerId == tracker.id && _sameDay(r.recordedAt, day))
        .toList();
    if (existing.isNotEmpty) {
      next.trackerRecords.remove(existing.last);
      await _persist(next);
      return false;
    }
    next.trackerRecords.add(
      TrackerRecord(
        id: const Uuid().v4(),
        trackerId: tracker.id,
        recordedAt: DateTime.now(),
        value: 1,
      ),
    );
    await _persist(next);
    return true;
  }

  /// Sets a boolean tracker to yes (true), no (false), or cleared (null) for
  /// the given day, replacing any existing record for that day.
  Future<void> setBoolean(
    TrackerDefinition tracker,
    DateTime day,
    bool? value,
  ) async {
    final next = state.copy();
    next.trackerRecords.removeWhere(
      (r) => r.trackerId == tracker.id && _sameDay(r.recordedAt, day),
    );
    if (value != null) {
      final recordedAt = _sameDay(day, DateTime.now())
          ? DateTime.now()
          : DateTime(day.year, day.month, day.day, 12);
      next.trackerRecords.add(
        TrackerRecord(
          id: const Uuid().v4(),
          trackerId: tracker.id,
          recordedAt: recordedAt,
          value: value ? 1 : 0,
        ),
      );
    }
    await _persist(next);
  }

  Future<void> updateRecord(TrackerRecord record) async {
    final next = state.copy();
    final index = next.trackerRecords.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      next.trackerRecords[index] = record;
      await _persist(next);
    }
  }

  Future<void> deleteRecord(String recordId) async {
    final next = state.copy()
      ..trackerRecords.removeWhere((r) => r.id == recordId);
    await _persist(next);
  }

  // ---------------------------------------------------------------------------
  // Timeline events
  // ---------------------------------------------------------------------------

  Future<void> saveEvent(TimelineEvent event) async {
    final next = state.copy();
    final index = next.events.indexWhere((e) => e.id == event.id);
    if (index >= 0) {
      next.events[index] = event;
    } else {
      next.events.add(event);
    }
    await _persist(next);
  }

  Future<void> deleteEvent(String id) async {
    final next = state.copy()..events.removeWhere((e) => e.id == id);
    await _persist(next);
  }

  Future<void> toggleEventHidden(String id) async {
    TimelineEvent? existing;
    for (final event in state.events) {
      if (event.id == id) {
        existing = event;
        break;
      }
    }
    if (existing == null) return;
    await saveEvent(existing.copyWith(hidden: !existing.hidden));
  }

  // ---------------------------------------------------------------------------
  // Places and visits
  // ---------------------------------------------------------------------------

  Future<void> savePlace(Place place) async {
    final next = state.copy();
    final index = next.places.indexWhere((p) => p.id == place.id);
    if (index >= 0) {
      next.places[index] = place;
    } else {
      next.places.add(place);
    }
    await _persist(next);
  }

  Future<void> deletePlace(String id) async {
    final next = state.copy()..places.removeWhere((p) => p.id == id);
    for (var i = 0; i < next.visits.length; i++) {
      if (next.visits[i].placeId == id) {
        next.visits[i] = next.visits[i].copyWith(clearPlace: true);
      }
    }
    await _persist(next);
  }

  Future<void> saveVisit(Visit visit) async {
    final next = state.copy();
    final index = next.visits.indexWhere((v) => v.id == visit.id);
    if (index >= 0) {
      next.visits[index] = visit;
    } else {
      next.visits.add(visit);
    }
    await _persist(next);
  }

  Future<void> deleteVisit(String id) async {
    final next = state.copy()..visits.removeWhere((v) => v.id == id);
    await _persist(next);
  }

  // ---------------------------------------------------------------------------
  // Location tracking
  // ---------------------------------------------------------------------------

  Future<void> addLocationSample(LocationSample sample) async {
    // Background events have deterministic ids and may arrive both from the
    // event stream and the pending queue. Never store the same event twice.
    if (state.locationSamples.any((existing) => existing.id == sample.id)) {
      return;
    }
    final next = state.copy();
    // Avoid exact duplicates in quick succession.
    final last = next.locationSamples.isEmpty
        ? null
        : next.locationSamples.last;
    if (last != null) {
      final dt = sample.recordedAt.difference(last.recordedAt).inSeconds.abs();
      final sameSpot =
          (sample.latitude - last.latitude).abs() < 0.00001 &&
          (sample.longitude - last.longitude).abs() < 0.00001;
      if (dt < 30 && sameSpot) return;
    }
    next.locationSamples.add(sample);
    // Keep samples bounded to avoid unbounded growth (retain ~90 days worth).
    const maxSamples = 20000;
    if (next.locationSamples.length > maxSamples) {
      next.locationSamples.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      next.locationSamples.removeRange(
        0,
        next.locationSamples.length - maxSamples,
      );
    }
    await _persist(next);
  }

  /// Replaces auto-tracked visits for [day] with [visits]. Manual visits are kept.
  Future<void> replaceAutoVisitsForDay(DateTime day, List<Visit> visits) async {
    final key = dayKey(day);
    final next = state.copy();
    next.visits.removeWhere(
      (v) => v.id.startsWith('auto-loc-$key') && _sameDay(v.startAt, day),
    );
    next.visits.addAll(visits);
    await _persist(next);
  }

  // ---------------------------------------------------------------------------
  // Music
  // ---------------------------------------------------------------------------

  Future<int> importScrobbles(List<MusicScrobble> incoming) async {
    if (incoming.isEmpty) return 0;
    final next = state.copy();
    final seen = next.scrobbles.map((s) => s.dedupeKey).toSet();
    final fresh = <MusicScrobble>[];
    for (final scrobble in incoming) {
      if (seen.add(scrobble.dedupeKey)) {
        fresh.add(scrobble);
      }
    }
    if (fresh.isEmpty) return 0;
    next.scrobbles.addAll(fresh);
    await _persist(next);
    return fresh.length;
  }

  Future<void> addManualScrobble(MusicScrobble scrobble) async {
    await importScrobbles([scrobble]);
  }

  Future<void> clearMusic() async {
    final next = state.copy()..scrobbles.clear();
    await _persist(next);
  }

  /// Removes imported Last.fm scrobbles while keeping manually added tracks.
  Future<void> removeImportedMusic() async {
    final next = state.copy()
      ..scrobbles.removeWhere((scrobble) => scrobble.source != 'manual');
    await _persist(next);
  }

  Future<void> deleteScrobble(String id) async {
    final next = state.copy()..scrobbles.removeWhere((s) => s.id == id);
    await _persist(next);
  }

  // ---------------------------------------------------------------------------
  // Restore and wipe
  // ---------------------------------------------------------------------------

  Future<bool> restoreArchive(
    Archive restored, {
    List<BackupMediaFile> mediaFiles = const [],
  }) async {
    // Restored archives can contain the legacy meal fields. Apply the same
    // additive migration used at startup before anything is persisted.
    final migrated = migrateLegacyMeals(restored);
    final byId = {for (final item in migrated.media) item.id: item};
    final failures = <String>[];

    // Never wipe the vault first: incoming metadata can reference media whose
    // bytes are still only on this device (the backup may omit media files).
    for (final file in mediaFiles) {
      final item = byId[file.id];
      if (item == null) continue;
      try {
        await _services.mediaStore.writeRestoredItem(
          item: item,
          originalBytes: file.originalBytes,
          thumbnailBytes: file.thumbnailBytes,
        );
      } catch (error) {
        failures.add('${item.originalName}: $error');
      }
    }

    await _persist(migrated);
    if (failures.isNotEmpty) {
      ref.read(mediaRevisionProvider.notifier).bump();
      throw MediaWriteException(
        'The archive was restored, but ${failures.length} media file(s) could '
        'not be written: ${failures.join('; ')}',
      );
    }
    if (mediaFiles.isNotEmpty) {
      ref.read(mediaRevisionProvider.notifier).bump();
    }
    return true;
  }

  Future<bool> clearArchiveData() async {
    await _persist(Archive.empty());
    try {
      await _services.mediaStore.deleteAll();
    } catch (error) {
      throw MediaWriteException(
        'The archive was cleared, but the media vault could not be removed.',
        error,
      );
    }
    ref.read(mediaRevisionProvider.notifier).bump();
    return true;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
