import Foundation

/// The entire local archive. Persisted as one authenticated, encrypted document.
/// Timeline rows are views derived from these records, never duplicated storage.
struct Archive: Codable {
    var entries: [JournalEntry]
    var media: [MediaItem]
    var trackers: [TrackerDefinition]
    var trackerRecords: [TrackerRecord]
    var events: [TimelineEvent]
    var places: [Place]
    var visits: [Visit]
    var scrobbles: [MusicScrobble]
    var locationSamples: [LocationSample]

    enum CodingKeys: String, CodingKey {
        case format, version, savedAt
        case entries, media, trackers, trackerRecords, events, places, visits, scrobbles, locationSamples
    }

    init(
        entries: [JournalEntry] = [],
        media: [MediaItem] = [],
        trackers: [TrackerDefinition] = [],
        trackerRecords: [TrackerRecord] = [],
        events: [TimelineEvent] = [],
        places: [Place] = [],
        visits: [Visit] = [],
        scrobbles: [MusicScrobble] = [],
        locationSamples: [LocationSample] = []
    ) {
        self.entries = entries
        self.media = media
        self.trackers = trackers
        self.trackerRecords = trackerRecords
        self.events = events
        self.places = places
        self.visits = visits
        self.scrobbles = scrobbles
        self.locationSamples = locationSamples
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        entries = l.objects(.entries)
        media = l.objects(.media)
        trackers = l.objects(.trackers)
        trackerRecords = l.objects(.trackerRecords)
        events = l.objects(.events)
        places = l.objects(.places)
        visits = l.objects(.visits)
        scrobbles = l.objects(.scrobbles)
        locationSamples = l.objects(.locationSamples)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("lifelog-archive", forKey: .format)
        try c.encode(1, forKey: .version)
        try c.encode(DateCodec.utcString(Date()), forKey: .savedAt)
        try c.encode(entries, forKey: .entries)
        try c.encode(media, forKey: .media)
        try c.encode(trackers, forKey: .trackers)
        try c.encode(trackerRecords, forKey: .trackerRecords)
        try c.encode(events, forKey: .events)
        try c.encode(places, forKey: .places)
        try c.encode(visits, forKey: .visits)
        try c.encode(scrobbles, forKey: .scrobbles)
        try c.encode(locationSamples, forKey: .locationSamples)
    }

    static var empty: Archive { Archive() }

    var isEmpty: Bool {
        entries.isEmpty && media.isEmpty && trackers.isEmpty && trackerRecords.isEmpty &&
        events.isEmpty && places.isEmpty && visits.isEmpty && scrobbles.isEmpty &&
        locationSamples.isEmpty
    }

    /// Structural cache key: nine counts in the Flutter order.
    var signature: String {
        "\(entries.count):\(media.count):\(trackerRecords.count):\(visits.count):" +
        "\(scrobbles.count):\(events.count):\(places.count):\(trackers.count):\(locationSamples.count)"
    }

    // MARK: Lookups

    func entryById(_ id: String) -> JournalEntry? { entries.first { $0.id == id } }
    func mediaById(_ id: String) -> MediaItem? { media.first { $0.id == id } }
    func trackerById(_ id: String) -> TrackerDefinition? { trackers.first { $0.id == id } }
    func placeById(_ id: String?) -> Place? {
        guard let id else { return nil }
        return places.first { $0.id == id }
    }
    func visitById(_ id: String) -> Visit? { visits.first { $0.id == id } }

    // MARK: Day-scoped queries

    func mediaForEntry(_ entryId: String) -> [MediaItem] {
        media.filter { $0.journalEntryId == entryId }.sorted { $0.createdAt < $1.createdAt }
    }

    func mediaOn(_ day: Date) -> [MediaItem] {
        media.filter { Dates.sameDay($0.createdAt, day) }.sorted { $0.createdAt < $1.createdAt }
    }

    func entriesOn(_ day: Date, includeDrafts: Bool = false, includeArchived: Bool = false) -> [JournalEntry] {
        entries.filter {
            Dates.sameDay($0.createdAt, day) &&
            (includeDrafts || !$0.draft) &&
            (includeArchived || !$0.archived)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func checkinsOn(_ day: Date) -> [JournalEntry] {
        entriesOn(day, includeDrafts: true).filter { $0.isCheckinEntry }
    }

    func latestCheckinOn(_ day: Date) -> JournalEntry? { checkinsOn(day).last }

    func trackerRecordsOn(_ day: Date) -> [TrackerRecord] {
        trackerRecords.filter { Dates.sameDay($0.recordedAt, day) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func recordsForTracker(_ trackerId: String) -> [TrackerRecord] {
        trackerRecords.filter { $0.trackerId == trackerId }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func visitsOn(_ day: Date) -> [Visit] {
        visits.filter { Dates.sameDay($0.startAt, day) }.sorted { $0.startAt < $1.startAt }
    }

    func locationSamplesOn(_ day: Date) -> [LocationSample] {
        locationSamples.filter { Dates.sameDay($0.recordedAt, day) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func eventsOn(_ day: Date, includeHidden: Bool = false) -> [TimelineEvent] {
        events.filter {
            Dates.sameDay($0.occurredAt, day) && (includeHidden || !$0.hidden)
        }.sorted { $0.occurredAt < $1.occurredAt }
    }

    func scrobblesOn(_ day: Date) -> [MusicScrobble] {
        scrobbles.filter { Dates.sameDay($0.playedAt, day) }
            .sorted { $0.playedAt < $1.playedAt }
    }

    func musicOn(_ day: Date) -> MusicDaySummary { MusicDaySummary.fromScrobbles(scrobblesOn(day)) }

    // MARK: Entry selection heuristics

    func dayMetricsEntryFor(_ day: Date) -> JournalEntry? {
        let stableId = "day-\(Dates.dayKey(day))"
        if let byId = entryById(stableId) { return byId }
        let candidates = entries.filter {
            Dates.sameDay($0.createdAt, day) && ($0.sleepHours != nil || $0.steps != nil)
        }.sorted { $0.updatedAt > $1.updatedAt }
        return candidates.first
    }

    func primaryWritingEntryFor(_ day: Date) -> JournalEntry? {
        let candidates = entriesOn(day, includeDrafts: true).filter { entry in
            if entry.isVocab { return true }
            if !entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if entry.draft && !entry.isCheckinEntry { return true }
            return false
        }
        func rank(_ entry: JournalEntry) -> Int {
            if !entry.archived && !entry.draft { return 0 }
            if !entry.archived && entry.draft { return 1 }
            return 2
        }
        return candidates.sorted {
            let left = rank($0)
            let right = rank($1)
            if left != right { return left < right }
            return $0.updatedAt > $1.updatedAt
        }.first
    }

    func dailyEntryFor(_ day: Date) -> JournalEntry? {
        if let writing = primaryWritingEntryFor(day) { return writing }
        if let checkin = latestCheckinOn(day) { return checkin }
        if let metrics = dayMetricsEntryFor(day) { return metrics }
        let all = entriesOn(day, includeDrafts: true)
        return all.isEmpty ? nil : all.last
    }

    // MARK: Global lists

    var drafts: [JournalEntry] {
        entries.filter { $0.draft && !$0.archived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeTrackers: [TrackerDefinition] {
        trackers.filter { $0.active && !$0.archived }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    // MARK: Calendar activity

    func activityDaysIn(_ month: Date) -> Set<Int> {
        var days = Set<Int>()
        func addIfInMonth(_ at: Date) {
            let atParts = Dates.calendar.dateComponents([.year, .month, .day], from: at)
            let monthParts = Dates.calendar.dateComponents([.year, .month], from: month)
            if atParts.year == monthParts.year && atParts.month == monthParts.month,
               let day = atParts.day { days.insert(day) }
        }
        for entry in entries where !entry.draft && !entry.archived { addIfInMonth(entry.createdAt) }
        for item in media { addIfInMonth(item.createdAt) }
        for visit in visits { addIfInMonth(visit.startAt) }
        for scrobble in scrobbles { addIfInMonth(scrobble.playedAt) }
        for record in trackerRecords { addIfInMonth(record.recordedAt) }
        return days
    }

    // MARK: Mutation helpers (value semantics; caller persists the returned archive)

    func puttingEntry(_ entry: JournalEntry) -> Archive {
        var copy = self
        if let index = copy.entries.firstIndex(where: { $0.id == entry.id }) {
            copy.entries[index] = entry
        } else {
            copy.entries.append(entry)
        }
        return copy
    }

    func removingEntry(_ id: String, detachMedia: Bool) -> Archive {
        var copy = self
        copy.entries.removeAll { $0.id == id }
        if detachMedia {
            copy.media = copy.media.map { item in
                var item = item
                if item.journalEntryId == id { item.journalEntryId = nil }
                return item
            }
        }
        return copy
    }

    func puttingTracker(_ tracker: TrackerDefinition) -> Archive {
        var copy = self
        if let index = copy.trackers.firstIndex(where: { $0.id == tracker.id }) {
            copy.trackers[index] = tracker
        } else {
            var tracker = tracker
            tracker.sortOrder = (copy.trackers.map(\.sortOrder).max() ?? -1) + 1
            copy.trackers.append(tracker)
        }
        return copy
    }

    func puttingRecord(_ record: TrackerRecord) -> Archive {
        var copy = self
        if let index = copy.trackerRecords.firstIndex(where: { $0.id == record.id }) {
            copy.trackerRecords[index] = record
        } else {
            copy.trackerRecords.append(record)
        }
        return copy
    }

    func puttingEvent(_ event: TimelineEvent) -> Archive {
        var copy = self
        if let index = copy.events.firstIndex(where: { $0.id == event.id }) {
            copy.events[index] = event
        } else {
            copy.events.append(event)
        }
        return copy
    }

    func puttingPlace(_ place: Place) -> Archive {
        var copy = self
        if let index = copy.places.firstIndex(where: { $0.id == place.id }) {
            copy.places[index] = place
        } else {
            copy.places.append(place)
        }
        return copy
    }

    func puttingVisit(_ visit: Visit) -> Archive {
        var copy = self
        if let index = copy.visits.firstIndex(where: { $0.id == visit.id }) {
            copy.visits[index] = visit
        } else {
            copy.visits.append(visit)
        }
        return copy
    }

    func puttingMedia(_ item: MediaItem) -> Archive {
        var copy = self
        if let index = copy.media.firstIndex(where: { $0.id == item.id }) {
            copy.media[index] = item
        } else {
            copy.media.append(item)
        }
        return copy
    }
}
