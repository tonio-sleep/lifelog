import SwiftUI

// MARK: - Snapshot

struct TrackerTile: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var color: UInt32
    var type: TrackerType
    var label: String?
    var done: Bool
    var lastRecordId: String?
}

struct VisitLine: Identifiable {
    var id: String
    var label: String
    var timeRange: String
    var suggested: Bool
}

struct TodaySnapshot {
    var loaded = false
    var rows: [DayRow] = []
    var totalRecords = 0
    var entryCount = 0
    var mood: Int?
    var steps: Int?
    var sleepHours: Double?
    var trackers: [TrackerTile] = []
    var visits: [VisitLine] = []
    var trackCount = 0
    var artistCount = 0
    var topArtist: String?
    var topTracks: [TopTrack] = []
    var artworkURL: String?
    var trackerRecordCount = 0
    var placeCount = 0
    var eventCount = 0

    static func make(_ archive: Archive, now: Date) -> TodaySnapshot {
        var snap = TodaySnapshot()
        snap.loaded = true
        let summary = DaySummary.of(archive, now)
        snap.totalRecords = summary.totalRecords
        snap.entryCount = summary.entries.filter { !$0.isMetricsOnly }.count
        snap.trackerRecordCount = summary.trackerRecords.count
        snap.eventCount = summary.events.count
        snap.placeCount = Set(summary.visits.map(\.label)).count
        snap.mood = dominantMood(archive, now)

        if let metrics = archive.dayMetricsEntryFor(now) {
            snap.steps = metrics.steps
            snap.sleepHours = metrics.sleepHours
        }

        snap.rows = Array(DayRow.rows(archive, now).reversed())

        let records = archive.trackerRecords
        snap.trackers = archive.activeTrackers.prefix(8).map { tracker in
            let history = HabitHistory(tracker, records)
            let today = TrackerMath.recordsOn(records, trackerId: tracker.id, day: now)
            return TrackerTile(
                id: tracker.id,
                name: tracker.name,
                symbol: tracker.icon.isEmpty ? "circle" : tracker.icon,
                color: tracker.colorValue,
                type: tracker.type,
                label: TrackerMath.dailyLabel(tracker, records, now),
                done: history.doneOn(now),
                lastRecordId: today.last?.id
            )
        }

        snap.visits = summary.visits.map { visit in
            VisitLine(
                id: visit.id,
                label: visit.label,
                timeRange: Dates.formatTimeRange(visit.startAt, visit.endAt),
                suggested: visit.confidence == .suggested
            )
        }

        let music = summary.music
        snap.trackCount = summary.scrobbles.count
        snap.artistCount = music.uniqueArtists
        snap.topArtist = music.topArtistName
        snap.topTracks = Array(music.topTracks.prefix(3))
        snap.artworkURL = summary.scrobbles.compactMap(\.artworkUrl).first { !$0.isEmpty }
        return snap
    }
}

// MARK: - View

struct TodayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var snapshot = TodaySnapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if enabled("status") { facts }
                if enabled("quickAdd") || enabled("highlight") { TodayComposer() }
                if enabled("timeline") { threadSection }
                if enabled("trackers") { practicesSection }
                if enabled("places") { placesSection }
                if enabled("music") { listeningSection }
                if enabled("recap") { recapSection }
                footer
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(snapshot.loaded ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: snapshot.loaded)
        .refreshable { await refreshSources() }
        .task(id: env.revision) {
            let archive = env.archive
            let now = Date()
            let result = await offMain { TodaySnapshot.make(archive, now: now) }
            guard !Task.isCancelled else { return }
            snapshot = result
        }
    }

    private func enabled(_ key: String) -> Bool { env.settings.todaySections.contains(key) }

    private func refreshSources() async {
        if env.settings.lastfmConnected {
            if let added = await env.syncLastfm() {
                env.present(added == 0 ? "Listening is up to date." : "Added \(added) \(Dates.plural(added, "track")).")
            }
        }
        if env.healthConnected {
            await env.syncHealth()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            PageHeader(
                eyebrow: Dates.formatDayLong(Date()),
                title: greeting,
                subtitle: snapshot.totalRecords == 0
                    ? "A blank page is still a good place to begin."
                    : "\(snapshot.totalRecords) \(Dates.plural(snapshot.totalRecords, "record")) so far today."
            )
            Button {
                navigator.push(.journal(Date()))
            } label: {
                Label("Open today's page", systemImage: "book")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "A quiet night."
        }
    }

    // MARK: Facts

    @ViewBuilder
    private var facts: some View {
        let hasAny = snapshot.mood != nil || snapshot.sleepHours != nil || snapshot.steps != nil
        if hasAny || snapshot.entryCount > 0 {
            VStack(alignment: .leading, spacing: Space.md) {
                Hairline()
                HStack(alignment: .top, spacing: Space.lg) {
                    Figure(value: "\(snapshot.entryCount)", label: Dates.plural(snapshot.entryCount, "Entry", "Entries"))
                    if let mood = snapshot.mood {
                        Figure(value: "\(mood)/10", label: "Mood")
                    }
                    if let sleep = snapshot.sleepHours {
                        Figure(value: Dates.formatCompactNumber(sleep) + " h", label: "Sleep")
                    }
                    if let steps = snapshot.steps {
                        Figure(value: steps.formatted(), label: "Steps")
                    }
                }
                Hairline()
            }
        }
    }

    // MARK: Thread

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(
                title: "Today's thread",
                actionTitle: "Add event"
            ) { navigator.present(.newEvent(Date())) }

            if snapshot.rows.isEmpty {
                EmptyNote(
                    title: "Nothing recorded yet",
                    message: "Write a note, log a practice, or add a moment. Only what you record appears here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.rows.prefix(5))) { row in
                        Button { navigator.open(row) } label: {
                            DayRowView(row: row)
                        }
                        .buttonStyle(RowButtonStyle())
                        if row.id != snapshot.rows.prefix(5).last?.id { Hairline() }
                    }
                }
                if snapshot.rows.count > 5 {
                    Button("See all \(snapshot.rows.count)") { navigator.push(.timeline(Date())) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    // MARK: Practices

    private var practicesSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(title: "Practices", actionTitle: "All") { navigator.push(.trackers) }
            if snapshot.trackers.isEmpty {
                EmptyNote(
                    title: "No practices yet",
                    message: "A practice is anything you want to note now and then: water, a walk, a mood, a reading.",
                    actionTitle: "Create one"
                ) { navigator.present(.newTracker) }
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.trackers) { tile in
                        PracticeRow(tile: tile)
                        if tile.id != snapshot.trackers.last?.id { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Places

    @ViewBuilder
    private var placesSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(title: "Where you were", actionTitle: "Map") { navigator.push(.map(Date())) }
            if snapshot.visits.isEmpty {
                EmptyNote(
                    title: "No places today",
                    message: env.settings.locationTrackingEnabled
                        ? "Stops appear after you spend time somewhere."
                        : "Location visits are off. You can turn them on in Settings whenever you like."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.visits.prefix(4)) { visit in
                        HStack(spacing: Space.md) {
                            SourceGlyph(source: .location, suggested: visit.suggested)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.label).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                                Text(visit.timeRange).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.sm)
                        .accessibilityElement(children: .combine)
                        if visit.id != snapshot.visits.prefix(4).last?.id { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Listening

    @ViewBuilder
    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(title: "Listening")
            if snapshot.trackCount == 0 {
                EmptyNote(
                    title: "No tracks today",
                    message: env.settings.lastfmConnected
                        ? "Pull down to sync Last.fm, or add a track you heard."
                        : "Connect Last.fm in Settings, or add a track you heard.",
                    actionTitle: "Add a track"
                ) { navigator.present(.addTrack) }
            } else {
                HStack(alignment: .top, spacing: Space.md) {
                    if env.settings.showArtwork {
                        RemoteArtwork(urlString: snapshot.artworkURL)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(snapshot.trackCount) \(Dates.plural(snapshot.trackCount, "track")) · \(snapshot.artistCount) \(Dates.plural(snapshot.artistCount, "artist"))")
                            .font(Typeface.bodyStrong)
                            .foregroundStyle(Palette.ink)
                        if let artist = snapshot.topArtist {
                            Text("Most played: \(artist)")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        ForEach(snapshot.topTracks, id: \.name) { track in
                            Text("\(track.name) · \(track.plays)")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Recap

    @ViewBuilder
    private var recapSection: some View {
        if snapshot.totalRecords > 0 {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(title: "Day so far")
                Text(recapText)
                    .font(Typeface.reading)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recapText: String {
        var parts: [String] = []
        if snapshot.entryCount > 0 { parts.append("\(snapshot.entryCount) \(Dates.plural(snapshot.entryCount, "journal entry", "journal entries"))") }
        if snapshot.trackerRecordCount > 0 { parts.append("\(snapshot.trackerRecordCount) practice \(Dates.plural(snapshot.trackerRecordCount, "update"))") }
        if snapshot.placeCount > 0 { parts.append("\(snapshot.placeCount) \(Dates.plural(snapshot.placeCount, "place")) visited") }
        if snapshot.eventCount > 0 { parts.append("\(snapshot.eventCount) \(Dates.plural(snapshot.eventCount, "moment")) noted") }
        if snapshot.trackCount > 0 { parts.append("\(snapshot.trackCount) \(Dates.plural(snapshot.trackCount, "track")) heard") }
        if parts.isEmpty { return "Records are stored for today." }
        return "You recorded " + parts.joined(separator: ", ") + "."
    }

    private var footer: some View {
        Text("Everything here is derived from records you chose to keep.")
            .font(Typeface.micro)
            .foregroundStyle(Palette.inkTertiary)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Practice row

private struct PracticeRow: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    let tile: TrackerTile

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: tile.symbol)
                .font(.system(.body))
                .foregroundStyle(Color(hex: tile.color))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                Text(tile.label ?? "Not logged yet")
                    .font(Typeface.caption)
                    .foregroundStyle(tile.done ? Palette.moss : Palette.inkSecondary)
            }
            Spacer(minLength: Space.sm)
            Button(action: primary) {
                Image(systemName: primarySymbol)
                    .font(.system(.title3))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryLabel)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { navigator.present(.logTracker(tile.id)) } label: {
                Label("Log with details", systemImage: "square.and.pencil")
            }
            if let last = tile.lastRecordId {
                Button(role: .destructive) { env.deleteTrackerRecord(last) } label: {
                    Label("Undo last entry today", systemImage: "arrow.uturn.backward")
                }
            }
            Button { navigator.push(.tracker(tile.id)) } label: {
                Label("Open", systemImage: "chevron.right")
            }
        }
    }

    private var quickLoggable: Bool { tile.type == .boolean || tile.type == .count || tile.type == .event }

    private var primarySymbol: String {
        if tile.type == .boolean && tile.done { return "checkmark.circle.fill" }
        return quickLoggable ? "plus.circle" : "square.and.pencil"
    }

    private var primaryLabel: String {
        switch tile.type {
        case .boolean: return "Log yes for \(tile.name)"
        case .count, .event: return "Add one to \(tile.name)"
        default: return "Log \(tile.name)"
        }
    }

    private func primary() {
        guard quickLoggable else {
            navigator.present(.logTracker(tile.id))
            return
        }
        if tile.type == .boolean && tile.done { return }
        env.saveTrackerRecord(TrackerRecord(trackerId: tile.id, recordedAt: Date(), value: 1))
    }
}

// MARK: - Composer

private struct TodayComposer: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            TextField("One sentence is enough…", text: $text, axis: .vertical)
                .font(Typeface.reading)
                .foregroundStyle(Palette.ink)
                .lineLimit(2...6)
                .focused($focused)
                .accessibilityLabel("Quick note")
            HStack(spacing: Space.xs) {
                iconButton("mic", label: "Voice note") {
                    navigator.present(.newEntry(Date(), startWithVoice: true))
                }
                iconButton("photo", label: "Add photo or video") {
                    navigator.present(.addMedia(Date()))
                }
                iconButton("square.and.pencil", label: "Open full editor") {
                    navigator.present(.newEntry(Date(), startWithVoice: false))
                }
                Spacer()
                Button("Save note", action: save)
                    .buttonStyle(QuietButtonStyle())
                    .disabled(trimmed.isEmpty)
            }
        }
        .surface()
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.body))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        env.saveEntry(JournalEntry(createdAt: Date(), body: trimmed))
        text = ""
        focused = false
        env.present("Saved to today.")
    }
}
