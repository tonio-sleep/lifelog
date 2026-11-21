import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/core/crypto/crypto_service.dart';
import 'package:lifelog/core/storage/archive_store.dart';
import 'package:lifelog/core/util/dates.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/places.dart';
import 'package:lifelog/domain/models/timeline.dart';
import 'package:lifelog/domain/models/trackers.dart';
import 'package:lifelog/domain/timeline_builder.dart';
import 'package:path/path.dart' as p;

void main() {
  final day = DateTime(2026, 5, 10);

  group('local day grouping', () {
    test('UTC timestamps use the device-local calendar day', () {
      final utc = DateTime.utc(2026, 5, 11, 1, 30);

      expect(dayKey(utc), dayKey(utc.toLocal()));
      expect(sameDay(utc, utc.toLocal()), isTrue);
      expect(dayStart(utc), dayStart(utc.toLocal()));
    });

    test('journal parser converts Z timestamps to local time', () {
      final entry = JournalEntry.fromJson({
        'id': 'e1',
        'createdAt': '2026-05-11T01:30:00.000Z',
        'updatedAt': '2026-05-11T01:30:00.000Z',
      });

      expect(entry.createdAt, DateTime.parse('2026-05-11T01:30:00.000Z').toLocal());
      expect(entry.updatedAt.isUtc, isFalse);
    });

    test('invalid day keys never silently become today', () {
      expect(parseDayKey('not-a-day'), DateTime(2000));
      expect(parseDayKey('2026-02-30'), DateTime(2000));
      expect(parseDayKey('2026-05-10'), DateTime(2026, 5, 10));
    });
  });

  group('journal and timeline visibility', () {
    test('drafts and orphan tracker records appear in the timeline', () {
      final archive = Archive(
        entries: [
          JournalEntry(
            id: 'draft-1',
            createdAt: DateTime(2026, 5, 10, 9),
            updatedAt: DateTime(2026, 5, 10, 9),
            title: 'Unfinished note',
            body: 'Saved automatically.',
            draft: true,
          ),
        ],
        trackerRecords: [
          TrackerRecord(
            id: 'orphan-1',
            trackerId: 'deleted-tracker',
            recordedAt: DateTime(2026, 5, 10, 10),
            text: 'Walked 2 km',
          ),
        ],
      );

      final items = buildTimelineForDay(archive, day);

      expect(items, hasLength(2));
      expect(items.first.subtitle, startsWith('Draft'));
      expect(items.first.metadata['draft'], 'true');
      final orphan = items.last;
      expect(orphan.source, TimelineSource.tracker);
      expect(orphan.metadata['missingTracker'], 'true');
      expect(orphan.subtitle, contains('Walked 2 km'));
    });

    test('activity markers include drafts, events and raw location samples', () {
      final archive = Archive(
        entries: [
          JournalEntry(
            id: 'draft-1',
            createdAt: DateTime(2026, 5, 10, 9),
            updatedAt: DateTime(2026, 5, 10, 9),
            title: 'Unfinished note',
            body: '',
            draft: true,
          ),
        ],
        events: [
          TimelineEvent(
            id: 'event-1',
            title: 'Manual event',
            occurredAt: DateTime(2026, 5, 11, 12),
          ),
        ],
        locationSamples: [
          LocationSample(
            id: 'sample-1',
            recordedAt: DateTime(2026, 5, 12, 8),
            latitude: 51.5,
            longitude: -0.12,
          ),
        ],
      );

      expect(archive.activityDaysIn(DateTime(2026, 5)), {10, 11, 12});
    });
  });

  group('archive envelope validation', () {
    test('malformed collections throw instead of returning an empty archive', () {
      expect(
        () => Archive.fromJson({
          'format': 'lifelog-archive',
          'version': 1,
          'entries': 'not a list',
        }),
        throwsFormatException,
      );
      expect(
        () => Archive.fromJson({
          'format': 'wrong-format',
          'version': 1,
        }),
        throwsFormatException,
      );
    });

    test('legacy archives without envelope keys remain readable', () {
      final archive = Archive.fromJson({
        'entries': [
          {
            'id': 'legacy-1',
            'createdAt': '2026-05-10T09:00:00.000',
            'updatedAt': '2026-05-10T09:00:00.000',
          },
        ],
      });

      expect(archive.entries, hasLength(1));
    });
  });

  group('archive storage safety', () {
    late Directory dir;
    late ArchiveStore store;

    setUp(() {
      dir = Directory(
        p.join(
          Directory.systemTemp.path,
          'lifelog-empty-regression-${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      store = ArchiveStore(
        directory: dir,
        crypto: CryptoService(
          SecretKey(List<int>.generate(32, (index) => index + 1)),
        ),
      );
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('unreadable archive files are reported and never removed', () async {
      final badBytes = <int>[1, 2, 3, 4, 5];
      await store.file.writeAsBytes(badBytes);

      expect(await ArchiveStore.hasAnyArchiveFile(dir), isTrue);
      expect(
        () => store.load(),
        throwsA(
          isA<ArchiveLoadException>()
              .having((e) => e.paths, 'paths', contains(store.file.path)),
        ),
      );
      expect(await store.file.readAsBytes(), badBytes);
    });

    test('a fresh directory has no archive artifacts', () async {
      expect(await ArchiveStore.hasAnyArchiveFile(dir), isFalse);
      expect(await store.load(), isNull);
    });
  });
}
