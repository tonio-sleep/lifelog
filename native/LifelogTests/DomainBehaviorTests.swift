import Foundation
import XCTest
@testable import Lifelog

final class DomainBehaviorTests: XCTestCase {
    func testSearchIsCappedAt250Hits() {
        var archive = Archive.empty
        for index in 0..<260 {
            archive.entries.append(JournalEntry(
                id: "entry-\(index)",
                createdAt: Dates.addingDays(-index, to: Date()),
                title: "Needle \(index)",
                body: "A searchable needle"
            ))
        }
        XCTAssertEqual(searchArchive(archive, rawQuery: "needle").count, 250)
    }

    func testTrackerRecordSearchHitsUseTrackerIDAsSourceID() {
        let tracker = TrackerDefinition(id: "tracker-42", name: "Meditation", type: .duration)
        let archive = Archive(
            trackers: [tracker],
            trackerRecords: [TrackerRecord(
                id: "record-1",
                trackerId: tracker.id,
                note: "quiet morning"
            )]
        )
        let hits = searchArchive(archive, rawQuery: "quiet")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .tracker)
        XCTAssertEqual(hits.first?.sourceId, "tracker-42")
    }

    func testOnThisDayFindsEarlierYearsOnly() {
        let today = Date()
        let year = Dates.component(.year, of: today)
        let oldDay = Dates.date(
            year: year - 2,
            month: Dates.component(.month, of: today),
            day: Dates.component(.day, of: today),
            hour: 12
        )
        let archive = Archive(entries: [
            JournalEntry(createdAt: oldDay, title: "Two years ago", body: "A remembered day")
        ])
        let memories = onThisDay(archive, today)
        XCTAssertEqual(memories.count, 1)
        XCTAssertTrue(memories.first?.description.contains("1 journal entry") ?? false)
    }

    func testCurrentStreakCountsManualMusicButNotImportedMusic() {
        let today = Dates.dayStart(Date())
        let archive = Archive(
            entries: [
                JournalEntry(createdAt: today, title: "Today"),
                JournalEntry(createdAt: Dates.addingDays(-1, to: today), title: "Yesterday"),
            ],
            scrobbles: [
                MusicScrobble(artist: "A", title: "B", playedAt: Dates.addingDays(-2, to: today), source: "manual"),
                MusicScrobble(artist: "C", title: "D", playedAt: Dates.addingDays(-3, to: today), source: "lastfm"),
            ]
        )
        XCTAssertEqual(currentStreak(archive, Date()), 3)
    }

    func testSafeNumberDoesNotTrapOnExtremeJSONValues() {
        XCTAssertNil(SafeNumber.int(Double.infinity))
        XCTAssertNil(SafeNumber.int(Double.nan))
        XCTAssertNil(SafeNumber.int(1e300))
        XCTAssertEqual(SafeNumber.int(7.6), 8)
        XCTAssertEqual(SafeNumber.truncatingInt(7.9), 7)
    }
}
