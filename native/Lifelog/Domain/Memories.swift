import Foundation

/// Counts for one day. Every count comes from a stored record; nothing is estimated.
struct DaySummary {
    var day: Date
    var entries: [JournalEntry]
    var photos: [MediaItem]
    var visits: [Visit]
    var scrobbles: [MusicScrobble]
    var trackerRecords: [TrackerRecord]
    var events: [TimelineEvent]

    var totalRecords: Int {
        entries.count + photos.count + visits.count + scrobbles.count +
        trackerRecords.count + events.count
    }
    var isEmpty: Bool { totalRecords == 0 }
    var music: MusicDaySummary { MusicDaySummary.fromScrobbles(scrobbles) }

    static func of(_ archive: Archive, _ day: Date) -> DaySummary {
        DaySummary(
            day: Dates.dayStart(day),
            entries: archive.entriesOn(day),
            photos: archive.mediaOn(day),
            visits: archive.visitsOn(day),
            scrobbles: archive.scrobblesOn(day),
            trackerRecords: archive.trackerRecordsOn(day),
            events: archive.eventsOn(day)
        )
    }
}

struct OnThisDayMemory: Identifiable {
    var id: String { Dates.dayKey(day) }
    var day: Date
    var summary: DaySummary

    /// Uses the current year, matching Dart's implementation.
    var yearsAgo: Int { Dates.component(.year, of: Date()) - Dates.component(.year, of: day) }

    var relativeLabel: String {
        if yearsAgo == 1 { return "One year ago today" }
        if yearsAgo > 1 { return "\(yearsAgo) years ago today" }
        return "Earlier today"
    }

    var description: String {
        var parts: [String] = []
        let s = summary
        if !s.entries.isEmpty {
            parts.append("\(s.entries.count) \(Dates.plural(s.entries.count, "journal entry", "journal entries"))")
        }
        if !s.photos.isEmpty { parts.append("\(s.photos.count) \(Dates.plural(s.photos.count, "photo"))") }
        if !s.visits.isEmpty {
            let uniquePlaces = Set(s.visits.map(\.label)).count
            parts.append("\(uniquePlaces) \(Dates.plural(uniquePlaces, "place")) visited")
        }
        if !s.scrobbles.isEmpty { parts.append("\(s.scrobbles.count) \(Dates.plural(s.scrobbles.count, "track"))") }
        if !s.trackerRecords.isEmpty {
            parts.append("\(s.trackerRecords.count) \(Dates.plural(s.trackerRecords.count, "tracker record"))")
        }
        if !s.events.isEmpty { parts.append("\(s.events.count) \(Dates.plural(s.events.count, "event"))") }
        if parts.isEmpty { return "No records for this day." }
        return "You recorded \(join(parts))."
    }

    private func join(_ parts: [String]) -> String {
        if parts.count == 1 { return parts[0] }
        if parts.count == 2 { return "\(parts[0]) and \(parts[1])" }
        return parts.dropLast().joined(separator: ", ") + " and \(parts.last!)"
    }
}

func onThisDay(_ archive: Archive, _ today: Date) -> [OnThisDayMemory] {
    let currentYear = Dates.component(.year, of: today)
    let month = Dates.component(.month, of: today)
    let day = Dates.component(.day, of: today)
    var memories: [OnThisDayMemory] = []
    // A decade is enough to keep the view calm; add more years only if they contain records.
    for year in stride(from: currentYear - 1, through: currentYear - 25, by: -1) {
        let probe = Dates.date(year: year, month: month, day: day)
        let summary = DaySummary.of(archive, probe)
        if !summary.isEmpty { memories.append(OnThisDayMemory(day: probe, summary: summary)) }
    }
    return memories
}

func activityDays(_ archive: Archive, _ month: Date) -> Set<Int> {
    archive.activityDaysIn(month)
}

func activeDaysInPreviousYears(_ archive: Archive, _ month: Date, years: Int = 10) -> [DaySummary] {
    var results: [DaySummary] = []
    let monthNumber = Dates.component(.month, of: month)
    for year in stride(from: Dates.component(.year, of: month) - 1,
                       through: Dates.component(.year, of: month) - years, by: -1) {
        let daysInMonth = Dates.calendar.range(of: .day, in: .month, for:
            Dates.date(year: year, month: monthNumber, day: 1))?.count ?? 30
        for day in 1...daysInMonth {
            let summary = DaySummary.of(archive, Dates.date(year: year, month: monthNumber, day: day))
            if !summary.isEmpty { results.append(summary) }
        }
    }
    // Dart sorts by day-of-month only, interleaving years. Preserve that.
    return results.sorted { Dates.component(.day, of: $0.day) > Dates.component(.day, of: $1.day) }
}

func dominantMood(_ archive: Archive, _ day: Date) -> Int? {
    let entries = archive.entriesOn(day, includeDrafts: true).filter { $0.mood != nil }
    guard !entries.isEmpty else { return nil }
    let total = entries.reduce(0) { $0 + $1.mood! }
    return min(10, max(1, Int((Double(total) / Double(entries.count)).rounded())))
}

/// Consecutive days with personally logged data. Imported Last.fm plays never count.
func currentStreak(_ archive: Archive, _ today: Date) -> Int {
    var days = Set<String>()
    for entry in archive.entries where !entry.draft && !entry.archived {
        days.insert(Dates.dayKey(entry.createdAt))
    }
    for item in archive.media { days.insert(Dates.dayKey(item.createdAt)) }
    for visit in archive.visits { days.insert(Dates.dayKey(visit.startAt)) }
    for scrobble in archive.scrobbles where scrobble.source == "manual" {
        days.insert(Dates.dayKey(scrobble.playedAt))
    }
    for record in archive.trackerRecords { days.insert(Dates.dayKey(record.recordedAt)) }

    var cursor = Dates.dayStart(today)
    if !days.contains(Dates.dayKey(cursor)) { cursor = Dates.addingDays(-1, to: cursor) }
    var streak = 0
    while days.contains(Dates.dayKey(cursor)) {
        streak += 1
        cursor = Dates.addingDays(-1, to: cursor)
    }
    return streak
}
