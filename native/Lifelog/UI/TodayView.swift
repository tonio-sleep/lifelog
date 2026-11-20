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
    var scrobbles: [MusicScrobble] = []
    var photos: [MediaItem] = []
    var trackerRecordCount = 0
    var placeCount = 0
    var eventCount = 0

    static func make(_ archive: Archive, day: Date, now: Date) -> TodaySnapshot {
        var snap = TodaySnapshot()
        snap.loaded = true
        let summary = DaySummary.of(archive, day)
        snap.totalRecords = summary.totalRecords
        snap.entryCount = summary.entries.filter { !$0.isMetricsOnly }.count
        snap.trackerRecordCount = summary.trackerRecords.count
        snap.eventCount = summary.events.count
        snap.placeCount = Set(summary.visits.map(\.label)).count
        snap.mood = dominantMood(archive, day)

        if let metrics = archive.dayMetricsEntryFor(day) {
            snap.steps = metrics.steps
            snap.sleepHours = metrics.sleepHours
        }

        snap.rows = Array(DayRow.rows(archive, day).reversed())
        snap.scrobbles = summary.scrobbles
        snap.photos = summary.photos

        let records = archive.trackerRecords
        snap.trackers = archive.activeTrackers.prefix(10).map { tracker in
            let history = HabitHistory(tracker, records)
            let today = TrackerMath.recordsOn(records, trackerId: tracker.id, day: day)
            return TrackerTile(
                id: tracker.id,
                name: tracker.name,
                symbol: tracker.icon.isEmpty ? "circle" : tracker.icon,
                color: tracker.colorValue,
                type: tracker.type,
                label: TrackerMath.dailyLabel(tracker, records, day),
                done: history.doneOn(day),
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
        return snap
    }

    /// Counts real records by local day. Built once per archive revision, never
    /// while scrolling. The calendar turns these into quiet dots.
    static func activity(_ archive: Archive) -> [String: Int] {
        var counts: [String: Int] = [:]
        func add(_ date: Date) {
            counts[Dates.dayKey(date), default: 0] += 1
        }
        for entry in archive.entries where !entry.isMetricsOnly { add(entry.createdAt) }
        for item in archive.media { add(item.createdAt) }
        for record in archive.trackerRecords { add(record.recordedAt) }
        for event in archive.events where !event.hidden { add(event.occurredAt) }
        for visit in archive.visits { add(visit.startAt) }
        for track in archive.scrobbles { add(track.playedAt) }
        return counts
    }
}

// MARK: - View

struct TodayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay = Dates.dayStart(Date())
    @State private var snapshot = TodaySnapshot()
    @State private var activity: [String: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                if enabled("status") { facts }
                if enabled("quickAdd") || enabled("highlight") { TodayComposer(day: selectedDay) }
                calendarCard
                if enabled("music") {
                    LastPlayedCard(scrobbles: snapshot.scrobbles, day: selectedDay)
                }
                if enabled("timeline") { threadSection }
                if enabled("trackers") { practicesSection }
                momentsSection
                if enabled("places") { placesLine }
                footer
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(snapshot.loaded ? 1 : 0)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.2), value: snapshot.loaded)
        .refreshable { await refreshSources() }
        .task(id: env.revision) {
            let archive = env.archive
            let result = await offMain { TodaySnapshot.activity(archive) }
            guard !Task.isCancelled else { return }
            activity = result
        }
        .task(id: "\(env.revision)-\(Dates.dayKey(selectedDay))") {
            let archive = env.archive
            let day = selectedDay
            let now = Date()
            let result = await offMain { TodaySnapshot.make(archive, day: day, now: now) }
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
        if env.healthConnected { await env.syncHealth() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow)
                        .font(Typeface.micro)
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(Palette.inkTertiary)
                    Text(title)
                        .font(Typeface.display)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                LifelogMark(size: 38)
            }

            HStack(spacing: Space.sm) {
                Text(subtitle)
                    .font(Typeface.label)
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !Dates.sameDay(selectedDay, Date()) {
                    Button("Today") {
                        withAnimation(reduceMotion ? nil : Animation.snappy(duration: 0.22)) {
                            selectedDay = Dates.dayStart(Date())
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var eyebrow: String {
        Dates.sameDay(selectedDay, Date()) ? Dates.formatDayLong(Date()) : "Looking back"
    }

    private var title: String {
        Dates.sameDay(selectedDay, Date()) ? greeting : Dates.formatDayHeader(selectedDay)
    }

    private var subtitle: String {
        if snapshot.totalRecords == 0 { return "Nothing recorded for this day yet." }
        return "\(snapshot.totalRecords) \(Dates.plural(snapshot.totalRecords, "record")) in your archive."
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
        if hasAny {
            HStack(alignment: .top, spacing: Space.lg) {
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
            .padding(.vertical, Space.xs)
        }
    }

    // MARK: Calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(
                title: "Calendar",
                detail: activity.isEmpty ? nil : "\(activity.count) \(Dates.plural(activity.count, "day")) recorded"
            )
            DayCalendar(selected: selectedDay, activity: activity) { day in
                Taptic.tap()
                withAnimation(reduceMotion ? nil : Animation.snappy(duration: 0.22)) {
                    selectedDay = day
                }
            }
        }
        .surface(padding: Space.md, radius: 20)
    }

    // MARK: Activity

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(
                title: "Recent activity",
                actionTitle: snapshot.rows.isEmpty ? nil : "All"
            ) { navigator.push(.timeline(selectedDay)) }

            if snapshot.rows.isEmpty {
                EmptyNote(
                    title: "A quiet day so far",
                    message: "Write a note, log a practice, or add a moment. Only what you record appears here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.rows.prefix(6))) { row in
                        Button { navigator.open(row) } label: {
                            DayRowView(row: row)
                        }
                        .buttonStyle(RowButtonStyle())
                        if row.id != snapshot.rows.prefix(6).last?.id { Hairline() }
                    }
                }
            }
        }
    }

    // MARK: Practices

    private var practicesSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(title: "Practices", actionTitle: "All") { navigator.push(.trackers) }
            if snapshot.trackers.isEmpty {
                EmptyNote(
                    title: "No practices yet",
                    message: "A practice is anything you want to note now and then: water, a walk, a mood, a reading.",
                    actionTitle: "Create one"
                ) { navigator.present(.newTracker) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(snapshot.trackers) { tile in
                            PracticeTile(tile: tile, day: selectedDay)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Moments

    @ViewBuilder
    private var momentsSection: some View {
        if !snapshot.photos.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(title: "Moments", detail: "\(snapshot.photos.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(snapshot.photos.prefix(8)) { item in
                            Button { navigator.push(.mediaItem(item.id)) } label: {
                                EncryptedMediaImage(item: item, maxPixel: 240)
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Palette.line, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.displayCaption)
                        }
                    }
                }
            }
        }
    }

    // MARK: Places

    @ViewBuilder
    private var placesLine: some View {
        if !snapshot.visits.isEmpty {
            Button { navigator.push(.map(selectedDay)) } label: {
                HStack(spacing: Space.md) {
                    SourceGlyph(source: .location)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where you were")
                            .font(Typeface.bodyStrong)
                            .foregroundStyle(Palette.ink)
                        Text("\(snapshot.placeCount) \(Dates.plural(snapshot.placeCount, "place")) on this day")
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.vertical, Space.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    private var footer: some View {
        Text("Everything here is derived from records you chose to keep.")
            .font(Typeface.micro)
            .foregroundStyle(Palette.inkTertiary)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Practice tile

private struct PracticeTile: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    let tile: TrackerTile
    let day: Date

    var body: some View {
        Button(action: primary) {
            VStack(spacing: Space.sm) {
                ZStack {
                    Circle().fill(Color(hex: tile.color).opacity(0.16))
                    Image(systemName: tile.symbol)
                        .font(.system(.body).weight(.semibold))
                        .foregroundStyle(Color(hex: tile.color))
                }
                .frame(width: 42, height: 42)

                Text(tile.name)
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(status)
                    .font(Typeface.micro)
                    .foregroundStyle(tile.done ? Palette.moss : Palette.inkTertiary)
                    .lineLimit(1)
            }
            .frame(width: 88, height: 116)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primaryLabel)
        .contextMenu {
            Button { navigator.present(.logTracker(tile.id)) } label: {
                Label("Log with details", systemImage: "square.and.pencil")
            }
            if let last = tile.lastRecordId {
                Button(role: .destructive) { env.deleteTrackerRecord(last) } label: {
                    Label("Undo last entry", systemImage: "arrow.uturn.backward")
                }
            }
            Button { navigator.push(.tracker(tile.id)) } label: {
                Label("Open", systemImage: "chevron.right")
            }
        }
    }

    private var status: String {
        if tile.done { return "Done" }
        return tile.label ?? "Not logged"
    }

    private var quickLoggable: Bool { tile.type == .boolean || tile.type == .count || tile.type == .event }

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
        Taptic.tap()
        env.saveTrackerRecord(TrackerRecord(trackerId: tile.id, recordedAt: Dates.momentForDay(day), value: 1))
    }
}

// MARK: - Composer

private struct TodayComposer: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    let day: Date
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
                    navigator.present(.newEntry(day, startWithVoice: true))
                }
                iconButton("photo", label: "Add photo or video") {
                    navigator.present(.addMedia(day))
                }
                iconButton("square.and.pencil", label: "Open full editor") {
                    navigator.present(.newEntry(day, startWithVoice: false))
                }
                Spacer()
                Button("Save", action: save)
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
        env.saveEntry(JournalEntry(createdAt: Dates.momentForDay(day), body: trimmed))
        text = ""
        focused = false
        env.present("Saved to this day.")
    }
}
