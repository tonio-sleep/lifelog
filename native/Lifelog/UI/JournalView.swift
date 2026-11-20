import SwiftUI

private struct EntryCard: Identifiable {
    var id: String
    var time: String
    var title: String
    var excerpt: String
    var mood: Int?
    var kind: JournalEntryKind
    var tags: [String]
    var isDraft: Bool
}

private struct JournalDaySnapshot {
    var loaded = false
    var entries: [EntryCard] = []
    var drafts: [EntryCard] = []
    var rows: [DayRow] = []
    var media: [MediaItem] = []
    var steps: Int?
    var sleepHours: Double?

    static func make(_ archive: Archive, day: Date) -> JournalDaySnapshot {
        var snap = JournalDaySnapshot()
        snap.loaded = true

        func card(_ entry: JournalEntry, draft: Bool) -> EntryCard {
            EntryCard(
                id: entry.id,
                time: Dates.formatTime(entry.createdAt),
                title: entry.title.isEmpty ? "" : entry.title,
                excerpt: entry.excerpt,
                mood: entry.mood,
                kind: entry.kind,
                tags: entry.tags,
                isDraft: draft
            )
        }

        let all = archive.entriesOn(day, includeDrafts: true)
        snap.entries = all.filter { !$0.draft && !$0.isMetricsOnly }.map { card($0, draft: false) }
        snap.drafts = all.filter { $0.draft }.map { card($0, draft: true) }

        if let metrics = archive.dayMetricsEntryFor(day) {
            snap.steps = metrics.steps
            snap.sleepHours = metrics.sleepHours
        }
        snap.rows = DayRow.rows(archive, day).filter { $0.source != .journal && $0.source != .photo }
        snap.media = archive.mediaOn(day).filter { !$0.isAudio }
        return snap
    }
}

/// One day as a page: what you wrote first, then everything else that happened.
struct JournalDayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var day: Date
    @State private var snapshot = JournalDaySnapshot()

    init(day: Date) {
        _day = State(initialValue: day)
    }

    private struct Key: Equatable {
        var revision: Int
        var day: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                dateBar
                PageHeader(
                    eyebrow: Dates.relativeDayLabel(day),
                    title: Dates.formatDayHeader(day),
                    subtitle: Dates.component(.year, of: day) == Dates.component(.year, of: Date())
                        ? nil : String(Dates.component(.year, of: day))
                )
                facts
                entries
                drafts
                otherRecords
                photos
                links
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { navigator.present(.newEntry(day, startWithVoice: false)) } label: {
                        Label("Journal entry", systemImage: "square.and.pencil")
                    }
                    Button { navigator.present(.newEntry(day, startWithVoice: true)) } label: {
                        Label("Voice note", systemImage: "mic")
                    }
                    Button { navigator.present(.addMedia(day)) } label: {
                        Label("Photo or video", systemImage: "photo.on.rectangle")
                    }
                    Button { navigator.present(.newEvent(day)) } label: {
                        Label("Moment", systemImage: "sparkle")
                    }
                    Button { navigator.present(.logTracker(nil)) } label: {
                        Label("Practice", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to this day")
            }
        }
        .paperScreen()
        .opacity(snapshot.loaded ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: snapshot.loaded)
        .task(id: Key(revision: env.revision, day: Dates.dayKey(day))) {
            let archive = env.archive
            let target = day
            let result = await offMain { JournalDaySnapshot.make(archive, day: target) }
            guard !Task.isCancelled else { return }
            snapshot = result
        }
    }

    // MARK: Sections

    private var dateBar: some View {
        HStack(spacing: Space.sm) {
            Button { day = Dates.addingDays(-1, to: day) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")
            DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            Button { day = Dates.addingDays(1, to: day) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(Dates.sameDay(day, Date()))
            .accessibilityLabel("Next day")
            Spacer()
        }
        .padding(.leading, -Space.sm)
    }

    @ViewBuilder
    private var facts: some View {
        if snapshot.sleepHours != nil || snapshot.steps != nil {
            HStack(alignment: .top, spacing: Space.lg) {
                if let sleep = snapshot.sleepHours {
                    Figure(value: Dates.formatCompactNumber(sleep) + " h", label: "Sleep")
                }
                if let steps = snapshot.steps {
                    Figure(value: steps.formatted(), label: "Steps")
                }
            }
        }
    }

    @ViewBuilder
    private var entries: some View {
        if snapshot.entries.isEmpty && snapshot.drafts.isEmpty && snapshot.rows.isEmpty && snapshot.media.isEmpty && snapshot.loaded {
            EmptyNote(
                title: "A blank page",
                message: "Nothing was recorded on this day. You can still add something now.",
                actionTitle: "Write an entry"
            ) { navigator.present(.newEntry(day, startWithVoice: false)) }
        }
        ForEach(snapshot.entries) { card in
            Button { navigator.push(.entry(card.id)) } label: {
                VStack(alignment: .leading, spacing: Space.sm) {
                    HStack(spacing: 6) {
                        Text(card.time).monospacedDigit()
                        if card.kind != .journal { Text("· \(card.kind.label)") }
                        if let mood = card.mood { Text("· Mood \(mood)/10") }
                    }
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.inkTertiary)
                    if !card.title.isEmpty {
                        Text(card.title)
                            .font(Typeface.title)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                    }
                    if !card.excerpt.isEmpty {
                        Text(card.excerpt)
                            .font(Typeface.reading)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(6)
                            .multilineTextAlignment(.leading)
                    }
                    if !card.tags.isEmpty { TagLine(tags: card.tags) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    @ViewBuilder
    private var drafts: some View {
        if !snapshot.drafts.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(title: "Unfinished")
                ForEach(snapshot.drafts) { card in
                    Button { navigator.present(.editEntry(card.id)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title.isEmpty ? "Untitled draft" : card.title)
                                .font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                            Text(card.excerpt.isEmpty ? "No text yet" : card.excerpt)
                                .font(Typeface.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
                        }
                        .padding(.vertical, Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(RowButtonStyle())
                    Hairline()
                }
            }
        }
    }

    @ViewBuilder
    private var otherRecords: some View {
        if !snapshot.rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(title: "Also this day")
                ForEach(snapshot.rows) { row in
                    Button { navigator.open(row) } label: { DayRowView(row: row) }
                        .buttonStyle(RowButtonStyle())
                    Hairline()
                }
            }
        }
    }

    @ViewBuilder
    private var photos: some View {
        if !snapshot.media.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel(title: "Photos and video", detail: "\(snapshot.media.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.sm)], spacing: Space.sm) {
                    ForEach(snapshot.media) { item in
                        Button { navigator.push(.mediaItem(item.id)) } label: { MediaTile(item: item) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var links: some View {
        HStack(spacing: Space.xl) {
            Button { navigator.push(.timeline(day)) } label: {
                Label("Timeline", systemImage: "calendar.day.timeline.left")
            }
            Button { navigator.push(.map(day)) } label: {
                Label("Map", systemImage: "map")
            }
        }
        .buttonStyle(QuietButtonStyle())
        .padding(.top, Space.sm)
    }
}
