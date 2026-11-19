import Foundation

// MARK: - Mood

/// Mirrors `MoodScore` from the Flutter domain layer, including legacy value parsing.
enum MoodScore {
    static let labels: [Int: String] = [
        1: "Very low", 2: "Low", 3: "Rough", 4: "Below okay", 5: "Okay",
        6: "Fine", 7: "Good", 8: "Very good", 9: "Great", 10: "Excellent",
    ]

    static func clamp(_ value: Int) -> Int { min(10, max(1, value)) }

    static func parse(_ value: AnyJSON?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .int(let v): return clamp(v)
        case .double(let v):
            guard let rounded = SafeNumber.int(v) else { return nil }
            return clamp(rounded)
        case .bool: return nil
        case .null, .array, .object: return nil
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let number = Int(trimmed) { return clamp(number) }
            switch trimmed.lowercased() {
            case "awful", "terrible", "very_low", "1": return 2
            case "low", "bad", "2": return 4
            case "okay", "ok", "neutral", "meh", "3": return 5
            case "good", "4": return 8
            case "great", "excellent", "amazing", "very_good", "5": return 10
            default: return nil
            }
        }
    }

    static func label(_ score: Int) -> String { labels[clamp(score)] ?? "\(score)" }
    /// Deliberately does not clamp, matching Dart's `shortLabel`.
    static func shortLabel(_ score: Int) -> String { "\(score)/10" }
    static func normalize(_ score: Int) -> Double { Double(clamp(score) - 1) / 9.0 }
}

// MARK: - Journal

enum JournalEntryKind: String, Codable {
    case journal, note, vocab

    var label: String {
        switch self {
        case .journal: return "Journal"
        case .note: return "Note"
        case .vocab: return "Vocab list"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try? c.decode(String.self)
        self = JournalEntryKind(rawValue: raw ?? "") ?? .journal
    }
}

struct VocabItem: Codable {
    var term: String
    var meaning: String

    init(term: String = "", meaning: String = "") {
        self.term = term
        self.meaning = meaning
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        term = l.string(.term)
        meaning = l.string(.meaning)
    }

    var isEmpty: Bool {
        term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct JournalEntry: Identifiable, Codable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var body: String
    var kind: JournalEntryKind
    var vocabItems: [VocabItem]
    var mood: Int?
    var energy: Int?
    var sleepHours: Double?
    var steps: Int?
    var meals: String
    var highlight: String
    var tags: [String]
    var placeId: String?
    var placeLabel: String?
    var draft: Bool
    var archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, title, body, kind
        case vocabItems = "vocab"
        case mood, energy, sleepHours, steps, meals, highlight, tags
        case placeId, placeLabel, draft, archived
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "",
        body: String = "",
        kind: JournalEntryKind = .journal,
        vocabItems: [VocabItem] = [],
        mood: Int? = nil,
        energy: Int? = nil,
        sleepHours: Double? = nil,
        steps: Int? = nil,
        meals: String = "",
        highlight: String = "",
        tags: [String] = [],
        placeId: String? = nil,
        placeLabel: String? = nil,
        draft: Bool = false,
        archived: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.body = body
        self.kind = kind
        self.vocabItems = vocabItems
        self.mood = mood
        self.energy = energy
        self.sleepHours = sleepHours
        self.steps = steps
        self.meals = meals
        self.highlight = highlight
        self.tags = tags
        self.placeId = placeId
        self.placeLabel = placeLabel
        self.draft = draft
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        let now = Date()
        createdAt = try l.c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try l.c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now
        title = l.string(.title)
        body = l.string(.body)
        kind = (try? l.c.decodeIfPresent(JournalEntryKind.self, forKey: .kind)) ?? .journal
        vocabItems = l.objects(.vocabItems)
        mood = MoodScore.parse(l.any(.mood))
        energy = l.int(.energy)
        sleepHours = l.double(.sleepHours)
        steps = l.int(.steps)
        meals = l.string(.meals)
        highlight = l.string(.highlight)
        tags = l.strings(.tags)
        placeId = l.optionalString(.placeId)
        placeLabel = l.optionalString(.placeLabel)
        draft = l.bool(.draft)
        archived = l.bool(.archived)
    }

    static func blank(_ date: Date, kind: JournalEntryKind = .journal) -> JournalEntry {
        let now = Date()
        let comps = Dates.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let created = Dates.calendar.date(from: comps) ?? date
        return JournalEntry(id: UUID().uuidString.lowercased(), createdAt: created,
                            updatedAt: now, kind: kind, draft: true)
    }

    var isVocab: Bool { kind == .vocab }

    var hasCheckinData: Bool {
        mood != nil || energy != nil || sleepHours != nil || steps != nil ||
        !meals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCheckinEntry: Bool {
        if isVocab { return false }
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        let hasSnapshot = mood != nil || energy != nil ||
            !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasSnapshot { return false }
        if sleepHours != nil || steps != nil ||
            !meals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var hasVocabContent: Bool { vocabItems.contains { !$0.isEmpty } }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        meals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        tags.isEmpty && mood == nil && energy == nil && sleepHours == nil &&
        steps == nil && !hasVocabContent
    }

    private func truncated(_ value: String, _ limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) + "..." : value
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        if isVocab {
            if let term = vocabItems.compactMap({ $0.term.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }).first {
                return term
            }
            return "Vocab list"
        }
        let firstLine = body.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstLine.isEmpty { return truncated(firstLine, 72) }
        return "Untitled entry"
    }

    var excerpt: String {
        if isVocab {
            let parts = vocabItems.filter { !$0.isEmpty }.map { item -> String in
                let t = item.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let m = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { return m }
                if m.isEmpty { return t }
                return "\(t) - \(m)"
            }
            let joined = parts.isEmpty ? "No words yet" : parts.joined(separator: ", ")
            return truncated(joined, 160)
        }
        let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let result = clean.isEmpty ? "No text" : clean
        return truncated(result, 160)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Splits on commas, lowercases, de-duplicates, caps at eight tags.
func normaliseTags(_ input: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for raw in input {
        for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if tag.isEmpty || !seen.insert(tag).inserted { continue }
            output.append(tag)
            if output.count == 8 { return output }
        }
    }
    return output
}

// MARK: - Media

struct MediaItem: Identifiable, Codable {
    var id: String
    var createdAt: Date
    var mimeType: String
    var bytes: Int
    var caption: String
    var tags: [String]
    var journalEntryId: String?
    var favorite: Bool
    var hasThumbnail: Bool
    var width: Int?
    var height: Int?
    var originalName: String?

    enum CodingKeys: String, CodingKey {
        case id, createdAt, mimeType, bytes, caption, tags, journalEntryId
        case favorite, hasThumbnail, width, height, originalName
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: Date = Date(),
        mimeType: String,
        bytes: Int,
        caption: String = "",
        tags: [String] = [],
        journalEntryId: String? = nil,
        favorite: Bool = false,
        hasThumbnail: Bool = false,
        width: Int? = nil,
        height: Int? = nil,
        originalName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mimeType = mimeType
        self.bytes = bytes
        self.caption = caption
        self.tags = tags
        self.journalEntryId = journalEntryId
        self.favorite = favorite
        self.hasThumbnail = hasThumbnail
        self.width = width
        self.height = height
        self.originalName = originalName
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        createdAt = l.date(.createdAt)
        mimeType = l.string(.mimeType).nilIfEmpty ?? "application/octet-stream"
        bytes = l.int(.bytes) ?? 0
        caption = l.string(.caption)
        tags = l.strings(.tags)
        journalEntryId = l.optionalString(.journalEntryId)
        favorite = l.bool(.favorite)
        hasThumbnail = l.bool(.hasThumbnail)
        width = l.int(.width)
        height = l.int(.height)
        originalName = l.optionalString(.originalName)
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
    var kindLabel: String {
        if isImage { return "Photo" }
        if isVideo { return "Video" }
        if isAudio { return "Audio" }
        return "File"
    }
    var displayCaption: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kindLabel
    }
}

// MARK: - Music

struct MusicScrobble: Identifiable, Codable {
    var id: String
    var artist: String
    var title: String
    var playedAt: Date
    var album: String
    var artworkUrl: String?
    var durationSeconds: Int?
    var source: String

    enum CodingKeys: String, CodingKey {
        case id, artist, title, playedAt, album, artworkUrl, durationSeconds, source
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        artist: String,
        title: String,
        playedAt: Date = Date(),
        album: String = "",
        artworkUrl: String? = nil,
        durationSeconds: Int? = nil,
        source: String = "lastfm"
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.playedAt = playedAt
        self.album = album
        self.artworkUrl = artworkUrl
        self.durationSeconds = durationSeconds
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        artist = l.string(.artist)
        title = l.string(.title)
        playedAt = l.date(.playedAt)
        album = l.string(.album)
        artworkUrl = l.optionalString(.artworkUrl)
        durationSeconds = l.int(.durationSeconds)
        source = l.string(.source).nilIfEmpty ?? "lastfm"
    }

    static func manual(artist: String, title: String, album: String = "", playedAt: Date? = nil) -> MusicScrobble {
        MusicScrobble(artist: artist, title: title, album: album,
                      playedAt: playedAt ?? Date(), source: "manual")
    }

    var dedupeKey: String {
        let millis = SafeNumber.truncatingInt(playedAt.timeIntervalSince1970 * 1000) ?? 0
        return "\(source)|\(millis)|" +
            artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" +
            title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unknown track" }
    var displayArtist: String { artist.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unknown artist" }
}

struct TopArtist { var name: String; var plays: Int }
struct TopTrack { var name: String; var artist: String; var plays: Int }

struct MusicDaySummary {
    var scrobbles: [MusicScrobble]
    var topArtists: [TopArtist]
    var topTracks: [TopTrack]

    var total: Int { scrobbles.count }
    var uniqueTracks: Int {
        Set(scrobbles.map { "\($0.artist)|\($0.title)".lowercased() }).count
    }
    var uniqueArtists: Int { Set(scrobbles.map { $0.artist.lowercased() }).count }
    var topArtistName: String? { topArtists.first?.name }

    static func fromScrobbles(_ input: [MusicScrobble]) -> MusicDaySummary {
        let plays = input.sorted { $0.playedAt < $1.playedAt }
        var artists: [String: Int] = [:]
        struct TrackKey: Hashable { let name: String; let artist: String }
        var tracks: [TrackKey: (name: String, artist: String, plays: Int)] = [:]
        for play in plays {
            artists[play.displayArtist, default: 0] += 1
            let key = TrackKey(name: play.displayTitle, artist: play.displayArtist)
            if let existing = tracks[key] {
                tracks[key] = (existing.name, existing.artist, existing.plays + 1)
            } else {
                tracks[key] = (play.displayTitle, play.displayArtist, 1)
            }
        }
        let sortedArtists = artists.map { TopArtist(name: $0.key, plays: $0.value) }
            .sorted { $0.plays > $1.plays }
        let sortedTracks = tracks.values.map { TopTrack(name: $0.name, artist: $0.artist, plays: $0.plays) }
            .sorted { $0.plays > $1.plays }
        return MusicDaySummary(scrobbles: plays, topArtists: sortedArtists, topTracks: sortedTracks)
    }
}

// MARK: - Places

struct Place: Identifiable, Codable {
    var id: String
    var name: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double
    var notes: String
    var colorValue: UInt32

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, latitude, longitude, radiusMeters, notes, colorValue
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String = "Place",
        createdAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double = 120,
        notes: String = "",
        colorValue: UInt32 = 0xFF52796F
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notes = notes
        self.colorValue = colorValue
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        name = l.string(.name).nilIfEmpty ?? "Place"
        createdAt = l.date(.createdAt)
        latitude = l.double(.latitude)
        longitude = l.double(.longitude)
        radiusMeters = l.double(.radiusMeters) ?? 120
        notes = l.string(.notes)
        colorValue = (try? l.c.decodeIfPresent(UInt32.self, forKey: .colorValue)) ?? 0xFF52796F
    }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }
}

struct LocationSample: Identifiable, Codable {
    var id: String
    var recordedAt: Date
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double?
    var speedMps: Double?

    enum CodingKeys: String, CodingKey {
        case id, recordedAt, latitude, longitude, accuracyMeters, speedMps
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        recordedAt: Date = Date(),
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double? = nil,
        speedMps: Double? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.speedMps = speedMps
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        recordedAt = l.date(.recordedAt)
        latitude = l.double(.latitude) ?? 0
        longitude = l.double(.longitude) ?? 0
        accuracyMeters = l.double(.accuracyMeters)
        speedMps = l.double(.speedMps)
    }
}

enum TimelineConfidence: String, Codable {
    case confirmed, suggested
    var label: String { self == .confirmed ? "Confirmed" : "Suggested" }

    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = TimelineConfidence(rawValue: raw ?? "") ?? .confirmed
    }
}

struct Visit: Identifiable, Codable {
    var id: String
    var label: String
    var startAt: Date
    var placeId: String?
    var endAt: Date?
    var confidence: TimelineConfidence
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id, label, startAt, placeId, endAt, confidence, notes
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        label: String = "Visit",
        startAt: Date = Date(),
        placeId: String? = nil,
        endAt: Date? = nil,
        confidence: TimelineConfidence = .confirmed,
        notes: String = ""
    ) {
        self.id = id
        self.label = label
        self.startAt = startAt
        self.placeId = placeId
        self.endAt = endAt
        self.confidence = confidence
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        label = l.string(.label).nilIfEmpty ?? "Visit"
        startAt = l.date(.startAt)
        placeId = l.optionalString(.placeId)
        endAt = l.optionalDate(.endAt)
        confidence = (try? l.c.decodeIfPresent(TimelineConfidence.self, forKey: .confidence)) ?? .confirmed
        notes = l.string(.notes)
    }

    var duration: TimeInterval? { endAt?.timeIntervalSince(startAt) }
}

// MARK: - Timeline

enum TimelineSource: String, Codable, CaseIterable {
    case manual, journal, tracker, location, music, photo

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .journal: return "Journal"
        case .tracker: return "Tracker"
        case .location: return "Location"
        case .music: return "Music"
        case .photo: return "Photo"
        }
    }
}

struct TimelineEvent: Identifiable, Codable {
    var id: String
    var title: String
    var occurredAt: Date
    var notes: String
    var hidden: Bool

    enum CodingKeys: String, CodingKey { case id, title, occurredAt, notes, hidden }

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String = "Event",
        occurredAt: Date = Date(),
        notes: String = "",
        hidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.occurredAt = occurredAt
        self.notes = notes
        self.hidden = hidden
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        title = l.string(.title).nilIfEmpty ?? "Event"
        occurredAt = l.date(.occurredAt)
        notes = l.string(.notes)
        hidden = l.bool(.hidden)
    }

    static func blank(_ date: Date) -> TimelineEvent {
        let comps = Dates.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return TimelineEvent(id: UUID().uuidString.lowercased(),
                             title: "",
                             occurredAt: Dates.calendar.date(from: comps) ?? date)
    }
}

// MARK: - Trackers

enum TrackerType: String, Codable, CaseIterable {
    case boolean, count, number, duration, rating, text, event

    var label: String {
        switch self {
        case .boolean: return "Yes / no"
        case .count: return "Count"
        case .number: return "Number"
        case .duration: return "Duration"
        case .rating: return "Rating"
        case .text: return "Note"
        case .event: return "Event"
        }
    }

    var typeDescription: String {
        switch self {
        case .boolean: return "A daily yes or no."
        case .count: return "Tap once per occurrence."
        case .number: return "A measured value with an optional unit."
        case .duration: return "Minutes spent."
        case .rating: return "A 1–5 personal rating."
        case .text: return "A short written observation."
        case .event: return "A timestamped occurrence."
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = TrackerType(rawValue: raw ?? "") ?? .count
    }
}

struct TrackerDefinition: Identifiable, Codable {
    var id: String
    var name: String
    var type: TrackerType
    var createdAt: Date
    var icon: String
    var colorValue: UInt32
    var category: String
    var unit: String
    var target: Double?
    var active: Bool
    var archived: Bool
    var multiplePerDay: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, type, createdAt, icon, colorValue, category, unit, target
        case active, archived, multiplePerDay, sortOrder
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String = "Tracker",
        type: TrackerType,
        createdAt: Date = Date(),
        icon: String = "circle",
        colorValue: UInt32 = 0xFF6B8F71,
        category: String = "Personal",
        unit: String = "",
        target: Double? = nil,
        active: Bool = true,
        archived: Bool = false,
        multiplePerDay: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.icon = icon
        self.colorValue = colorValue
        self.category = category
        self.unit = unit
        self.target = target
        self.active = active
        self.archived = archived
        self.multiplePerDay = multiplePerDay
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        name = l.string(.name).nilIfEmpty ?? "Tracker"
        type = (try? l.c.decodeIfPresent(TrackerType.self, forKey: .type)) ?? .count
        createdAt = l.date(.createdAt)
        icon = l.string(.icon).nilIfEmpty ?? "circle"
        colorValue = (try? l.c.decodeIfPresent(UInt32.self, forKey: .colorValue)) ?? 0xFF6B8F71
        category = l.string(.category).nilIfEmpty ?? "Personal"
        unit = l.string(.unit)
        target = l.double(.target)
        active = l.bool(.active, default: true)
        archived = l.bool(.archived)
        multiplePerDay = l.bool(.multiplePerDay, default: true)
        sortOrder = l.int(.sortOrder) ?? 0
    }

    static func blank() -> TrackerDefinition {
        TrackerDefinition(name: "", type: .count)
    }

    /// Includes rating, excludes event — matching Dart's `isNumeric`.
    var isNumeric: Bool {
        [.count, .number, .duration, .rating].contains(type)
    }

    var targetLabel: String {
        guard let target else { return "" }
        let unitText = unit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return "Target \(Dates.formatCompactNumber(target))" + (unitText.map { " \($0)" } ?? "")
    }
}

struct TrackerRecord: Identifiable, Codable {
    var id: String
    var trackerId: String
    var recordedAt: Date
    var value: Double?
    var text: String
    var note: String
    var startedAt: Date?
    var endedAt: Date?
    var durationMinutes: Double?
    var count: Double?

    enum CodingKeys: String, CodingKey {
        case id, trackerId, recordedAt, value, text, note, startedAt, endedAt, durationMinutes, count
    }

    init(
        id: String = UUID().uuidString.lowercased(),
        trackerId: String = "",
        recordedAt: Date = Date(),
        value: Double? = nil,
        text: String = "",
        note: String = "",
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationMinutes: Double? = nil,
        count: Double? = nil
    ) {
        self.id = id
        self.trackerId = trackerId
        self.recordedAt = recordedAt
        self.value = value
        self.text = text
        self.note = note
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id) ?? UUID().uuidString.lowercased()
        trackerId = l.string(.trackerId)
        recordedAt = l.date(.recordedAt)
        value = l.double(.value)
        text = l.string(.text)
        note = l.string(.note)
        startedAt = l.optionalDate(.startedAt)
        endedAt = l.optionalDate(.endedAt)
        durationMinutes = l.double(.durationMinutes)
        count = l.double(.count)
    }

    var effectiveDurationMinutes: Double? {
        if let durationMinutes { return durationMinutes }
        guard let startedAt, let endedAt else { return nil }
        let minutes = endedAt.timeIntervalSince(startedAt) / 60
        guard let wholeMinutes = SafeNumber.truncatingInt(minutes) else { return nil }
        let whole = Double(wholeMinutes)
        return whole < 0 ? nil : whole
    }
}

// MARK: - Settings

enum AppThemeMode: String, Codable {
    case system, light, dark

    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = AppThemeMode(rawValue: raw ?? "") ?? .system
    }
}

enum ReminderRepeat: String, Codable {
    case once, daily

    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = ReminderRepeat(rawValue: raw ?? "") ?? .daily
    }
}

struct ReminderItem: Identifiable, Codable {
    var id: String
    var title: String
    var note: String
    var hour: Int
    var minute: Int
    var enabled: Bool
    var repeatMode: ReminderRepeat

    enum CodingKeys: String, CodingKey {
        case id, title, note, hour, minute, enabled
        case repeatMode = "repeat"
    }

    init(
        id: String? = nil,
        title: String = "",
        note: String = "",
        hour: Int = 9,
        minute: Int = 0,
        enabled: Bool = true,
        repeatMode: ReminderRepeat = .daily
    ) {
        self.id = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? UUID().uuidString.lowercased()
        self.title = title
        self.note = note
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.enabled = enabled
        self.repeatMode = repeatMode
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        id = l.optionalString(.id)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? UUID().uuidString.lowercased()
        title = l.string(.title)
        note = l.string(.note)
        hour = min(23, max(0, l.int(.hour) ?? 9))
        minute = min(59, max(0, l.int(.minute) ?? 0))
        enabled = l.bool(.enabled, default: true)
        repeatMode = (try? l.c.decodeIfPresent(ReminderRepeat.self, forKey: .repeatMode)) ?? .daily
    }

    var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return f.string(from: Dates.calendar.date(from: comps) ?? Date())
    }
}

enum TodaySection: String, Codable, CaseIterable {
    case status, quickAdd, highlight, timeline, trackers, places, music, recap

    static let defaults: [String] = [
        "status", "quickAdd", "highlight", "timeline", "trackers", "places", "music", "recap",
    ]
}

struct AppSettings: Codable {
    static let defaultCloudflareWorkerUrl = "https://lifelog-cloudflare-sync.logginglife.workers.dev"

    var onboardingComplete: Bool
    var themeMode: AppThemeMode
    var lastfmUsername: String?
    var lastfmApiKeyCipher: String?
    var lastfmConnectedAt: Date?
    var lastfmLastSync: Date?
    var lastfmLastSyncFrom: Date?
    var weekStartsMonday: Bool
    var lockEnabled: Bool
    var pinSalt: String?
    var pinHash: String?
    var autoLockMinutes: Int
    var lastBackupAt: Date?
    var hiddenInsightCategories: [String]
    var todaySections: [String]
    var showArtwork: Bool
    var backupFolderPath: String?
    var cloudflareWorkerUrl: String?
    var cloudflareUsername: String?
    var cloudflareSessionCipher: String?
    var cloudflareConnectedAt: Date?
    var cloudflareLastSyncAt: Date?
    var cloudflareSetupDone: Bool
    var reminders: [ReminderItem]
    var locationTrackingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case onboardingComplete, themeMode, lastfmUsername, lastfmApiKeyCipher
        case lastfmConnectedAt, lastfmLastSync, lastfmLastSyncFrom, weekStartsMonday
        case lockEnabled, pinSalt, pinHash, autoLockMinutes, lastBackupAt
        case hiddenInsightCategories, todaySections, showArtwork, backupFolderPath
        case cloudflareWorkerUrl, cloudflareUsername, cloudflareSessionCipher
        case cloudflareConnectedAt, cloudflareLastSyncAt, cloudflareSetupDone
        case reminders, locationTrackingEnabled
    }

    init(
        onboardingComplete: Bool = false,
        themeMode: AppThemeMode = .system,
        lastfmUsername: String? = nil,
        lastfmApiKeyCipher: String? = nil,
        lastfmConnectedAt: Date? = nil,
        lastfmLastSync: Date? = nil,
        lastfmLastSyncFrom: Date? = nil,
        weekStartsMonday: Bool = false,
        lockEnabled: Bool = false,
        pinSalt: String? = nil,
        pinHash: String? = nil,
        autoLockMinutes: Int = 5,
        lastBackupAt: Date? = nil,
        hiddenInsightCategories: [String] = [],
        todaySections: [String] = TodaySection.defaults,
        showArtwork: Bool = true,
        backupFolderPath: String? = nil,
        cloudflareWorkerUrl: String? = AppSettings.defaultCloudflareWorkerUrl,
        cloudflareUsername: String? = nil,
        cloudflareSessionCipher: String? = nil,
        cloudflareConnectedAt: Date? = nil,
        cloudflareLastSyncAt: Date? = nil,
        cloudflareSetupDone: Bool = false,
        reminders: [ReminderItem] = [],
        locationTrackingEnabled: Bool = false
    ) {
        self.onboardingComplete = onboardingComplete
        self.themeMode = themeMode
        self.lastfmUsername = lastfmUsername
        self.lastfmApiKeyCipher = lastfmApiKeyCipher
        self.lastfmConnectedAt = lastfmConnectedAt
        self.lastfmLastSync = lastfmLastSync
        self.lastfmLastSyncFrom = lastfmLastSyncFrom
        self.weekStartsMonday = weekStartsMonday
        self.lockEnabled = lockEnabled
        self.pinSalt = pinSalt
        self.pinHash = pinHash
        self.autoLockMinutes = autoLockMinutes
        self.lastBackupAt = lastBackupAt
        self.hiddenInsightCategories = hiddenInsightCategories
        self.todaySections = todaySections
        self.showArtwork = showArtwork
        self.backupFolderPath = backupFolderPath
        self.cloudflareWorkerUrl = cloudflareWorkerUrl
        self.cloudflareUsername = cloudflareUsername
        self.cloudflareSessionCipher = cloudflareSessionCipher
        self.cloudflareConnectedAt = cloudflareConnectedAt
        self.cloudflareLastSyncAt = cloudflareLastSyncAt
        self.cloudflareSetupDone = cloudflareSetupDone
        self.reminders = reminders
        self.locationTrackingEnabled = locationTrackingEnabled
    }

    init(from decoder: Decoder) throws {
        let l = LooseDecode(c: try decoder.container(keyedBy: CodingKeys.self))
        onboardingComplete = l.bool(.onboardingComplete)
        themeMode = (try? l.c.decodeIfPresent(AppThemeMode.self, forKey: .themeMode)) ?? .system
        lastfmUsername = l.optionalString(.lastfmUsername)
        lastfmApiKeyCipher = l.optionalString(.lastfmApiKeyCipher)
        lastfmConnectedAt = l.optionalDate(.lastfmConnectedAt)
        lastfmLastSync = l.optionalDate(.lastfmLastSync)
        lastfmLastSyncFrom = l.optionalDate(.lastfmLastSyncFrom)
        weekStartsMonday = l.bool(.weekStartsMonday)
        lockEnabled = l.bool(.lockEnabled)
        pinSalt = l.optionalString(.pinSalt)
        pinHash = l.optionalString(.pinHash)
        autoLockMinutes = l.int(.autoLockMinutes) ?? 5
        lastBackupAt = l.optionalDate(.lastBackupAt)
        hiddenInsightCategories = l.strings(.hiddenInsightCategories)
        todaySections = l.strings(.todaySections).isEmpty ? TodaySection.defaults : l.strings(.todaySections)
        showArtwork = l.bool(.showArtwork, default: true)
        backupFolderPath = l.optionalString(.backupFolderPath)
        let storedWorker = l.optionalString(.cloudflareWorkerUrl)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cloudflareWorkerUrl = storedWorker.isEmpty
            ? AppSettings.defaultCloudflareWorkerUrl : storedWorker
        cloudflareUsername = l.optionalString(.cloudflareUsername)
        cloudflareSessionCipher = l.optionalString(.cloudflareSessionCipher)
        cloudflareConnectedAt = l.optionalDate(.cloudflareConnectedAt)
        cloudflareLastSyncAt = l.optionalDate(.cloudflareLastSyncAt)
        cloudflareSetupDone = l.bool(.cloudflareSetupDone) ||
            !(l.optionalString(.cloudflareSessionCipher)?.isEmpty ?? true)
        reminders = l.objects(.reminders).filter { !$0.id.isEmpty }
        locationTrackingEnabled = l.bool(.locationTrackingEnabled)
    }

    var lastfmConnected: Bool {
        !(lastfmUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var cloudflareConnected: Bool {
        !(cloudflareWorkerUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        !(cloudflareUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        !(cloudflareSessionCipher?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
