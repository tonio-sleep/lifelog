import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/app/providers/providers.dart';
import 'package:lifelog/app/shell/app_shell.dart';
import 'package:lifelog/app/theme/app_theme.dart';
import 'package:lifelog/app/widgets/motion.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/media.dart';
import 'package:lifelog/domain/models/music.dart';
import 'package:lifelog/domain/models/places.dart';
import 'package:lifelog/domain/models/timeline.dart';
import 'package:lifelog/domain/models/trackers.dart';

import 'helpers/widget_test_services.dart';

Archive _seededArchive() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return Archive(
    entries: [
      JournalEntry(
        id: 'seed-entry',
        createdAt: day.add(const Duration(hours: 9)),
        updatedAt: day.add(const Duration(hours: 9)),
        title: 'Seeded journal note',
        body: 'A seeded journal note used by navigation tests.',
        mood: 7,
        energy: 4,
      ),
    ],
    media: [
      MediaItem(
        id: 'seed-photo',
        createdAt: day.add(const Duration(hours: 10)),
        mimeType: 'image/jpeg',
        bytes: 1024,
        caption: 'Seeded photo',
      ),
    ],
    trackers: [
      TrackerDefinition(
        id: 'walk',
        name: 'Walk',
        type: TrackerType.count,
        createdAt: day.subtract(const Duration(days: 7)),
      ),
    ],
    trackerRecords: [
      TrackerRecord(
        id: 'walk-record',
        trackerId: 'walk',
        recordedAt: day.add(const Duration(hours: 11)),
        count: 1,
      ),
    ],
    places: [
      Place(
        id: 'home',
        name: 'Home',
        createdAt: day.subtract(const Duration(days: 7)),
        latitude: 51.5,
        longitude: -0.12,
      ),
    ],
    visits: [
      Visit(
        id: 'home-visit',
        label: 'Home',
        placeId: 'home',
        startAt: day.add(const Duration(hours: 8)),
        endAt: day.add(const Duration(hours: 9, minutes: 30)),
      ),
    ],
    scrobbles: [
      MusicScrobble(
        id: 'song-1',
        artist: 'Test Artist',
        title: 'Seed Song',
        playedAt: day.add(const Duration(hours: 9, minutes: 5)),
        album: 'Seed Album',
      ),
      MusicScrobble(
        id: 'song-2',
        artist: 'Test Artist',
        title: 'Seed Song',
        playedAt: day.add(const Duration(hours: 9, minutes: 20)),
        album: 'Seed Album',
      ),
      MusicScrobble(
        id: 'song-3',
        artist: 'Other Artist',
        title: 'Another Song',
        playedAt: day.add(const Duration(hours: 9, minutes: 40)),
      ),
    ],
    events: [
      TimelineEvent(
        id: 'seed-event',
        title: 'Seeded event',
        occurredAt: day.add(const Duration(hours: 12)),
      ),
    ],
  );
}

/// Pumps a bounded number of frames instead of waiting for every ticker to
/// settle. Some host platforms keep a decorative animation alive forever, and
/// this smoke test cares about navigation and content, not animation completion.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 14; attempt++) {
    if (find.text(text).evaluate().isNotEmpty ||
        find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
    final scrollable = find.byType(CustomScrollView);
    if (scrollable.evaluate().isEmpty) return;
    await tester.drag(
      scrollable.first,
      const Offset(0, -360),
      warnIfMissed: false,
    );
    await _pumpFrames(tester);
  }
}

Future<void> _pumpShell(WidgetTester tester, {required Archive archive}) async {
  final dir = Directory.systemTemp.createTempSync('lifelog-nav-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(
          createWidgetTestServices(directory: dir, archive: archive),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const AppShell(),
      ),
    ),
  );
  await _pumpFrames(tester);
}

void main() {
  testWidgets(
    'mobile Journal tab shows seeded writing and opens a rich day summary',
    (tester) async {
      await _pumpShell(tester, archive: _seededArchive());

      await tester.tap(find.text('Journal'));
      await _pumpFrames(tester);

      expect(find.text('Seeded journal note'), findsOneWidget);
      expect(find.text('No entries yet'), findsNothing);

      // The entry row opens an editor; the day header opens the day summary.
      await tester.tap(
        find
            .ancestor(of: find.text('Today'), matching: find.byType(Pressable))
            .first,
      );
      await _pumpFrames(tester);

      expect(find.text('Day at a glance'), findsOneWidget);
      expect(find.text('Top artist'), findsOneWidget);
      expect(find.textContaining('Test Artist'), findsWidgets);
    },
  );

  testWidgets('mobile Library reaches Insights with seeded data', (
    tester,
  ) async {
    await _pumpShell(tester, archive: _seededArchive());

    await tester.tap(find.text('Library'));
    await _pumpFrames(tester);
    await tester.ensureVisible(find.text('Insights'));
    await _pumpFrames(tester);
    await tester.tap(
      find
          .ancestor(of: find.text('Insights'), matching: find.byType(Pressable))
          .first,
    );
    await _pumpFrames(tester);

    await _scrollToText(tester, 'Daily activity');
    expect(find.text('Daily activity'), findsOneWidget);
    await _scrollToText(tester, 'Writing');
    expect(find.text('Writing'), findsOneWidget);
    await _scrollToText(tester, 'Music');
    expect(find.text('Music'), findsOneWidget);
    expect(find.textContaining('Test Artist'), findsWidgets);
  });

  testWidgets('desktop side navigation reaches every main section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpShell(tester, archive: _seededArchive());

    for (final label in [
      'Today',
      'Journal',
      'Habits',
      'Timeline',
      'Memories',
      'Media',
      'Places',
      'Music',
      'Insights',
      'Search',
      'Settings',
    ]) {
      await tester.tap(find.text(label));
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull, reason: '$label threw');
    }
  });
}
