import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/app/providers/providers.dart';
import 'package:lifelog/app/theme/app_theme.dart';
import 'package:lifelog/app/widgets/components.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/music.dart';
import 'package:lifelog/domain/models/settings.dart';
import 'package:lifelog/domain/models/timeline.dart';
import 'package:lifelog/features/insights/insights_screen.dart';
import 'package:lifelog/features/journal/day_overview.dart';
import 'package:lifelog/features/places/map_screen.dart';

import 'helpers/widget_test_services.dart';

void main() {
  test('day summary keeps artwork for the headline artist and song', () {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final scrobbles = [
      MusicScrobble(
        id: '1',
        artist: 'Test Artist',
        title: 'Seed Song',
        playedAt: day.add(const Duration(hours: 9)),
        artworkUrl: 'https://example.com/song.png',
      ),
      MusicScrobble(
        id: '2',
        artist: 'Test Artist',
        title: 'Seed Song',
        playedAt: day.add(const Duration(hours: 10)),
        artworkUrl: 'https://example.com/song.png',
      ),
      MusicScrobble(
        id: '3',
        artist: 'Test Artist',
        title: 'Other Song',
        playedAt: day.add(const Duration(hours: 11)),
        artworkUrl: 'https://example.com/artist.png',
      ),
    ];
    final stats = DayStats.of(Archive(scrobbles: scrobbles), day);

    expect(stats.topTrack!.name, 'Seed Song');
    expect(stats.topArtist!.name, 'Test Artist');
    expect(Artwork.usable(stats.topTrackArtworkUrl), isTrue);
    expect(stats.topTrackArtworkUrl, contains('song.png'));
    expect(Artwork.usable(stats.topArtistArtworkUrl), isTrue);
    expect(stats.summary, contains('3 songs'));
  });

  test('auto-detected is the shared label for inferred timeline items', () {
    expect(TimelineConfidence.suggested.label, 'Auto-detected');
    expect(TimelineConfidence.suggested.label, isNot('Suggested'));
  });

  test('journey titles follow the selected day', () {
    final now = DateTime.now();
    expect(journeyTitleFor(now), 'Today’s journey');
    expect(
      journeyTitleFor(now.subtract(const Duration(days: 1))),
      'Yesterday’s journey',
    );
    final older = now.subtract(const Duration(days: 9));
    expect(journeyTitleFor(older), isNot(contains('Today')));
    expect(journeyTitleFor(older), startsWith('Journey on '));
  });

  testWidgets('Insights explains an empty range instead of rendering blank', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('lifelog-insights-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            createWidgetTestServices(directory: dir, archive: Archive.empty()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing recorded in this range'), findsOneWidget);
    expect(find.text('Show all time'), findsOneWidget);
    expect(find.text('Choose range'), findsOneWidget);
  });

  testWidgets('a reset action turns all hidden Insights sections back on', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('lifelog-insights-hidden-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final archive = Archive(
      entries: [
        JournalEntry(
          id: 'entry',
          createdAt: day.add(const Duration(hours: 8)),
          updatedAt: day.add(const Duration(hours: 8)),
          title: 'A note',
          body: 'Some writing.',
        ),
      ],
    );
    final settings = const AppSettings(
      onboardingComplete: true,
      hiddenInsightCategories: [
        'Activity',
        'Journal',
        'Trackers',
        'Weekday',
        'Places',
        'Music',
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(
            createWidgetTestServices(
              directory: dir,
              archive: archive,
              settings: settings,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All sections are hidden'), findsOneWidget);
    await tester.tap(find.text('Show all sections'));
    await tester.pumpAndSettle();

    expect(find.text('All sections are hidden'), findsNothing);
    expect(find.text('Daily activity'), findsOneWidget);
  });
}
