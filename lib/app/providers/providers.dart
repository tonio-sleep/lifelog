import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/archive.dart';
import '../../domain/models/journal.dart';
import '../../domain/models/media.dart';
import '../../domain/models/music.dart';
import '../../domain/models/places.dart';
import '../../domain/models/timeline.dart';
import '../../domain/models/trackers.dart';
import '../app_services.dart';

final appServicesProvider = Provider<AppServices>((ref) {
  throw UnimplementedError('AppServices must be overridden at bootstrap.');
});

final archiveProvider = NotifierProvider<ArchiveController, Archive>(
  ArchiveController.new,
);

class ArchiveController extends Notifier<Archive> {
  Future<void> _writeQueue = Future.value();
  bool isSaving = false;
  String? lastSaveError;

  AppServices get _services => ref.read(appServicesProvider);

  @override
  Archive build() => ref.watch(appServicesProvider).archive;

  Future<void> _persist(Archive next) {
    state = next;
    final snapshot = next;
    isSaving = true;
    final write = _writeQueue.then((_) async {
      try {
        await _services.archiveStore.save(snapshot);
        lastSaveError = null;
      } catch (error) {
        lastSaveError = error.toString();
        rethrow;
      } finally {
        isSaving = false;
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
    next.entries.removeWhere((e) => e.id == id);
    if (deleteMedia) {
      final linked = next.media
          .where((m) => m.journalEntryId == id)
          .toList(growable: false);
      for (final item in linked) {
        await _services.mediaStore.delete(item);
      }
      next.media.removeWhere((m) => m.journalEntryId == id);
    } else {
      for (var i = 0; i < next.media.length; i++) {
        if (next.media[i].journalEntryId == id) {
          next.media[i] = next.media[i].copyWith(clearJournalEntry: true);
        }
      }
    }
    await _persist(next);
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
      mood: entry.mood,
      tags: [...entry.tags],
      placeId: entry.placeId,
      placeLabel: entry.placeLabel,
      draft: true,
    );
    await saveEntry(copy);
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
    await _services.mediaStore.delete(media);
    final next = state.copy()..media.removeWhere((m) => m.id == id);
    await _persist(next);
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

  Future<bool> restoreArchive(Archive restored) async {
    await _services.mediaStore.deleteAll();
    await _persist(restored);
    return true;
  }

  Future<bool> clearArchiveData() async {
    await _services.mediaStore.deleteAll();
    await _persist(Archive.empty());
    return true;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
