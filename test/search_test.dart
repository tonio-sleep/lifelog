import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/domain/models/archive.dart';
import 'package:lifelog/domain/models/journal.dart';
import 'package:lifelog/domain/models/timeline.dart';
import 'package:lifelog/domain/search.dart';

void main() {
  final archive = Archive(
    entries: [
      JournalEntry(
        id: 'e1',
        createdAt: DateTime(2026, 5, 10, 9),
        updatedAt: DateTime(2026, 5, 10, 9),
        title: 'Harbour walk',
        body: 'Saw the fishing boats at the harbour.',
        tags: const ['outside'],
      ),
      JournalEntry(
        id: 'e2',
        createdAt: DateTime(2026, 5, 11, 9),
        updatedAt: DateTime(2026, 5, 11, 9),
        title: 'Archived note',
        body: 'harbour',
        archived: true,
      ),
    ],
    events: [
      TimelineEvent(
        id: 'm1',
        title: 'Evening',
        notes: 'Walked to the harbour',
        occurredAt: DateTime(2026, 5, 10, 19),
      ),
    ],
  );

  test('empty queries return no results', () {
    expect(searchArchive(archive, '   '), isEmpty);
  });

  test('search is literal, case-insensitive and skips archived entries', () {
    final hits = searchArchive(archive, 'HARBOUR');
    final ids = hits.map((hit) => hit.sourceId).toSet();

    expect(ids, containsAll(['e1', 'm1']));
    expect(ids.contains('e2'), isFalse);
  });

  test('search does not guess synonyms', () {
    expect(searchArchive(archive, 'river'), isEmpty);
  });

  test('tags and event notes are searchable', () {
    expect(searchArchive(archive, 'outside').single.sourceId, 'e1');
    expect(searchArchive(archive, 'walked').single.sourceId, 'm1');
  });
}
