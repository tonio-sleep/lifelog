import Foundation

enum SearchKind: String, CaseIterable {
    case journal, photo, tracker, place, visit, music, event

    var label: String {
        switch self {
        case .journal: return "Journal"
        case .photo: return "Photos"
        case .tracker: return "Trackers"
        case .place: return "Places"
        case .visit: return "Visits"
        case .music: return "Music"
        case .event: return "Events"
        }
    }
}

struct SearchHit: Identifiable {
    var id: String { "\(kind.rawValue):\(sourceId):\(date.timeIntervalSince1970)" }
    var kind: SearchKind
    var title: String
    var subtitle: String
    var date: Date
    var sourceId: String
}

/// Local-only search: no query ever leaves the device.
func searchArchive(_ archive: Archive, rawQuery: String) -> [SearchHit] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return [] }

    func matches(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.lowercased().contains(query)
    }

    func snippet(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "" }
        guard let range = clean.range(of: query, options: [.caseInsensitive]) else {
            return clean.count > 120 ? String(clean.prefix(120)) + "…" : clean
        }
        let index = clean.distance(from: clean.startIndex, to: range.lowerBound)
        let matchLength = clean.distance(from: range.lowerBound, to: range.upperBound)
        let start = max(0, index - 40)
        let end = min(clean.count, index + matchLength + 80)
        let startIndex = clean.index(clean.startIndex, offsetBy: start)
        let endIndex = clean.index(clean.startIndex, offsetBy: end)
        let prefix = start > 0 ? "…" : ""
        let suffix = end < clean.count ? "…" : ""
        return prefix + clean[startIndex..<endIndex] + suffix
    }

    var hits: [SearchHit] = []

    for entry in archive.entries where !entry.archived {
        let tagText = entry.tags.joined(separator: " ")
        let numericMatches = [
            entry.mood.map { MoodScore.label($0) },
            entry.mood.map { "\($0)/10" },
            entry.steps.map { "\($0)" },
            entry.sleepHours.map { "\($0)" },
        ].compactMap { $0 }
        let matched = [entry.title, entry.body, tagText, entry.placeLabel, entry.meals, entry.highlight] +
            numericMatches
        guard matched.contains(where: matches) else { continue }
        let subtitle: String
        if matches(entry.body) { subtitle = snippet(entry.body) }
        else if matches(entry.meals) { subtitle = snippet(entry.meals) }
        else if matches(entry.highlight) { subtitle = snippet(entry.highlight) }
        else { subtitle = tagText }
        hits.append(SearchHit(kind: .journal, title: entry.displayTitle, subtitle: subtitle,
                              date: entry.createdAt, sourceId: entry.id))
    }

    for item in archive.media {
        guard matches(item.caption) || matches(item.tags.joined(separator: " ")) else { continue }
        hits.append(SearchHit(kind: .photo, title: item.displayCaption,
                              subtitle: item.tags.map { "#\($0)" }.joined(separator: " "),
                              date: item.createdAt, sourceId: item.id))
    }

    for tracker in archive.trackers {
        guard matches(tracker.name) || matches(tracker.category) || matches(tracker.unit) else { continue }
        hits.append(SearchHit(kind: .tracker, title: tracker.name,
                              subtitle: "\(tracker.type.label) · \(tracker.category)",
                              date: tracker.createdAt, sourceId: tracker.id))
    }

    for record in archive.trackerRecords {
        guard let tracker = archive.trackerById(record.trackerId) else { continue }
        guard matches(record.text) || matches(record.note) else { continue }
        let title = "\(tracker.name): \(record.text.isEmpty ? record.note : record.text)"
        hits.append(SearchHit(kind: .tracker, title: title,
                              subtitle: snippet([record.text, record.note].joined(separator: " ")),
                              date: record.recordedAt, sourceId: tracker.id))
    }

    for place in archive.places {
        guard matches(place.name) || matches(place.notes) else { continue }
        hits.append(SearchHit(kind: .place, title: place.name,
                              subtitle: place.hasCoordinates ? "Saved place with coordinates" : "Saved place",
                              date: place.createdAt, sourceId: place.id))
    }

    for visit in archive.visits {
        guard matches(visit.label) || matches(visit.notes) else { continue }
        let subtitle = visit.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(Dates.formatTime(visit.startAt)) · \(visit.confidence.label)"
            : snippet(visit.notes)
        hits.append(SearchHit(kind: .visit, title: visit.label, subtitle: subtitle,
                              date: visit.startAt, sourceId: visit.id))
    }

    for scrobble in archive.scrobbles {
        guard matches(scrobble.title) || matches(scrobble.artist) || matches(scrobble.album) else { continue }
        hits.append(SearchHit(kind: .music,
                              title: "\(scrobble.displayTitle) · \(scrobble.displayArtist)",
                              subtitle: scrobble.album.isEmpty ? "Last.fm scrobble" : scrobble.album,
                              date: scrobble.playedAt, sourceId: scrobble.id))
    }

    for event in archive.events where !event.hidden {
        guard matches(event.title) || matches(event.notes) else { continue }
        hits.append(SearchHit(kind: .event, title: event.title,
                              subtitle: event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? "Timeline event" : snippet(event.notes),
                              date: event.occurredAt, sourceId: event.id))
    }

    return hits.sorted { $0.date > $1.date }.prefix(250).map { $0 }
}
