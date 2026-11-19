import Foundation

/// A single chronological row derived from stored records. Views, never duplicated storage.
struct TimelineItem: Identifiable {
    var id: String
    var at: Date
    var title: String
    var subtitle: String
    var source: TimelineSource
    var confidence: TimelineConfidence
    var derived: Bool
    var sourceId: String?
    var metadata: [String: String]
}

func buildTimelineForDay(_ archive: Archive, _ day: Date, includeHidden: Bool = false) -> [TimelineItem] {
    var items: [TimelineItem] = []

    for entry in archive.entriesOn(day) {
        items.append(TimelineItem(
            id: "journal:\(entry.id)", at: entry.createdAt,
            title: entry.displayTitle, subtitle: entry.excerpt,
            source: .journal, confidence: .confirmed, derived: true, sourceId: entry.id,
            metadata: [:]
        ))
    }

    for record in archive.trackerRecordsOn(day) {
        guard let tracker = archive.trackerById(record.trackerId) else { continue }
        let value = TrackerMath.recordLabel(tracker, record)
        let note = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(TimelineItem(
            id: "tracker:\(record.id)", at: record.startedAt ?? record.recordedAt,
            title: tracker.name, subtitle: note.isEmpty ? value : "\(value) · \(note)",
            source: .tracker, confidence: .confirmed, derived: true, sourceId: record.id,
            metadata: ["trackerId": tracker.id]
        ))
    }

    for visit in archive.visitsOn(day) {
        var subtitleParts: [String] = []
        if let end = visit.endAt {
            subtitleParts.append(Dates.formatTimeRange(visit.startAt, end))
        } else {
            subtitleParts.append("Since \(Dates.formatTime(visit.startAt))")
        }
        if let duration = visit.duration { subtitleParts.append(Dates.formatDurationMinutes(duration / 60)) }
        let notes = visit.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { subtitleParts.append(notes) }
        let label = visit.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTravel = label == "Traveling" || label == "On the road" || label.hasPrefix("Traveling")
        items.append(TimelineItem(
            id: "visit:\(visit.id)", at: visit.startAt,
            title: isTravel ? label : "At \(label)",
            subtitle: subtitleParts.joined(separator: " · "),
            source: .location, confidence: visit.confidence, derived: true,
            sourceId: visit.id, metadata: ["visitId": visit.id]
        ))
    }

    for event in archive.eventsOn(day, includeHidden: includeHidden) {
        items.append(TimelineItem(
            id: "event:\(event.id)", at: event.occurredAt,
            title: event.title.isEmpty ? "Event" : event.title,
            subtitle: event.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual, confidence: .confirmed, derived: false, sourceId: event.id,
            metadata: [:]
        ))
    }

    for item in archive.mediaOn(day) {
        let subtitle: String
        if item.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subtitle = "\(item.kindLabel) added"
        } else if item.tags.isEmpty {
            subtitle = item.kindLabel
        } else {
            subtitle = item.tags.map { "#\($0)" }.joined(separator: " ")
        }
        items.append(TimelineItem(
            id: "photo:\(item.id)", at: item.createdAt,
            title: item.displayCaption, subtitle: subtitle,
            source: .photo, confidence: .confirmed, derived: true, sourceId: item.id,
            metadata: [:]
        ))
    }

    items.append(contentsOf: musicSessions(archive.scrobblesOn(day)))

    return items.sorted {
        if $0.at != $1.at { return $0.at < $1.at }
        let all = TimelineSource.allCases
        let left = all.firstIndex(of: $0.source) ?? all.count
        let right = all.firstIndex(of: $1.source) ?? all.count
        if left != right { return left < right }
        return $0.id < $1.id
    }
}

/// One calm daily listening row instead of many separate track rows.
private func musicSessions(_ input: [MusicScrobble]) -> [TimelineItem] {
    guard !input.isEmpty else { return [] }
    let plays = input.sorted { $0.playedAt < $1.playedAt }
    let summary = MusicDaySummary.fromScrobbles(plays)
    let artistNames = summary.topArtists.prefix(3).map(\.name).joined(separator: " · ")
    let artwork = plays.compactMap { $0.artworkUrl }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    return [TimelineItem(
        id: "music:\(Dates.dayKey(plays.first!.playedAt))",
        at: plays.first!.playedAt,
        title: "Listened to \(plays.count) \(plays.count == 1 ? "track" : "tracks")",
        subtitle: artistNames,
        source: .music, confidence: .confirmed, derived: true, sourceId: nil,
        metadata: ["artwork": artwork, "artist": artistNames, "track": "Listening session"]
    )]
}
