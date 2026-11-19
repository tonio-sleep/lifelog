import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette

    private var summary: DaySummary { DaySummary.of(env.archive, Date()) }
    private var timeline: [TimelineItem] { Array(buildTimelineForDay(env.archive, Date()).suffix(6).reversed()) }
    private var mood: Int? { dominantMood(env.archive, Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                stats

                if enabled("highlight") { quickNote }
                if enabled("timeline") { timelineSection }
                if enabled("trackers") { trackersSection }
                if enabled("places") { placesSection }
                if enabled("music") { musicSection }
                if enabled("recap") { recapSection }

                Text("Everything here is derived from records you chose to keep.")
                    .font(LifelogTheme.sans(11))
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .refreshable {
            await env.syncLastfm()
        }
    }

    private func enabled(_ key: String) -> Bool { env.settings.todaySections.contains(key) }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: Dates.formatDayLong(Date()))
            Text(greeting)
                .font(LifelogTheme.serif(34, relativeTo: .largeTitle))
                .foregroundStyle(palette.text)
            Text(summary.isEmpty
                 ? "A blank page is still a good place to begin."
                 : "\(summary.totalRecords) \(Dates.plural(summary.totalRecords, "record")) so far today.")
                .font(LifelogTheme.sans(14))
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "A quiet night."
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "\(summary.entries.count)", label: "Entries", systemImage: "book.closed", accent: true)
            StatTile(value: mood.map { MoodScore.shortLabel($0) } ?? "—", label: "Mood", systemImage: "heart")
            StatTile(value: "\(summary.photos.count)", label: "Photos", systemImage: "photo")
            StatTile(value: "\(summary.scrobbles.count)", label: "Tracks", systemImage: "music.note")
        }
    }

    private var quickNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "A thought to keep", subtitle: "No title. No pressure.")
            QuickNoteCard()
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Today's thread",
                subtitle: "A calm view of what was recorded",
                action: { router.push(.newEvent) },
                actionLabel: "Add event"
            )
            if timeline.isEmpty {
                EmptyState(
                    title: "Nothing recorded yet",
                    message: "Add an entry, log a tracker, or simply note a moment.",
                    systemImage: "sparkles"
                ) { router.push(.newEntry) }
                .lifelogCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(timeline) { item in
                        TimelineRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                switch item.source {
                                case .journal:
                                    if let id = item.sourceId { router.push(.entry(id)) }
                                case .manual:
                                    if let id = item.sourceId { router.push(.event(id)) }
                                default: break
                                }
                            }
                    }
                }
            }
        }
    }

    private var trackersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Daily practices", subtitle: "Your own measures, not a scoreboard") {
                router.push(.trackers)
            }
            let trackers = Array(env.archive.activeTrackers.prefix(4))
            if trackers.isEmpty {
                EmptyState(title: "No practices yet", message: "Create one in Trackers.", systemImage: "checkmark.circle", action: nil)
                    .lifelogCard()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(trackers) { tracker in
                        let history = HabitHistory(tracker, env.archive.trackerRecords)
                        Button {
                            env.saveTrackerRecord(TrackerRecord(
                                trackerId: tracker.id,
                                recordedAt: Date(),
                                value: tracker.type == .boolean ? 1 : (tracker.target ?? 1)
                            ))
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: tracker.icon.isEmpty ? "circle" : tracker.icon)
                                        .foregroundStyle(palette.accent)
                                    Spacer()
                                    if history.doneOn(Date()) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.success)
                                    }
                                }
                                Text(tracker.name)
                                    .font(LifelogTheme.sans(14, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                    .lineLimit(1)
                                Text(TrackerMath.dailyLabel(tracker, env.archive.trackerRecords, Date()) ?? "Not logged yet")
                                    .font(LifelogTheme.sans(11))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lifelogCard(padding: 14, radius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Where you were",
                subtitle: "Only what you chose to track",
                action: { router.push(.map(Date())) },
                actionLabel: "Map"
            )
            if summary.visits.isEmpty {
                EmptyState(title: "No place signals", message: "Enable location tracking in Settings if you want automatic visits.", systemImage: "map", action: nil)
                    .lifelogCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(summary.visits.prefix(3))) { visit in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(visit.label).font(LifelogTheme.sans(14, weight: .semibold))
                                Text(Dates.formatTimeRange(visit.startAt, visit.endAt))
                                    .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            if visit.confidence == .suggested {
                                Text("Suggested").font(LifelogTheme.sans(9)).foregroundStyle(palette.tertiary)
                            }
                        }
                        .lifelogCard(padding: 14, radius: 15)
                    }
                }
            }
        }
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Listening", subtitle: summary.music.topArtistName.map { "Most played: \($0)" } ?? "Connect Last.fm in Settings")
            if summary.scrobbles.isEmpty {
                EmptyState(title: "No tracks today", message: "Last.fm scrobbles or manually added tracks appear here.", systemImage: "music.note", action: nil)
                    .lifelogCard()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        RemoteArtwork(urlString: summary.scrobbles.compactMap(\.artworkUrl).first)
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading) {
                            Text("\(summary.total) \(Dates.plural(summary.total, "track"))")
                                .font(LifelogTheme.serif(21, relativeTo: .title3))
                            Text("\(summary.uniqueArtists) artists · \(summary.uniqueTracks) tracks")
                                .font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
                        }
                    }
                    ForEach(Array(summary.music.topTracks.prefix(3)), id: \.name) { track in
                        HStack {
                            Text(track.name).font(LifelogTheme.sans(13))
                            Spacer()
                            Text("\(track.plays)").font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
                        }
                    }
                }
                .lifelogCard()
            }
        }
    }

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Day recap", subtitle: "Built only from stored records")
            VStack(spacing: 10) {
                RecapRow(label: "Journal entries", value: "\(summary.entries.count)", systemImage: "book.closed")
                RecapRow(label: "Tracker records", value: "\(summary.trackerRecords.count)", systemImage: "checkmark.circle")
                RecapRow(label: "Places visited", value: "\(Set(summary.visits.map(\.label)).count)", systemImage: "mappin")
                RecapRow(label: "Events", value: "\(summary.events.count)", systemImage: "calendar")
            }
            .lifelogCard()
        }
    }
}

private struct RecapRow: View {
    @Environment(\.lifelogPalette) private var palette
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(palette.accent)
            Text(label).font(LifelogTheme.sans(13))
            Spacer()
            Text(value).font(LifelogTheme.sans(14, weight: .semibold)).foregroundStyle(palette.text)
        }
    }
}

private struct QuickNoteCard: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("One sentence is enough…", text: $text, axis: .vertical)
                .font(LifelogTheme.sans(15))
                .lineLimit(2...5)
                .textFieldStyle(.plain)
            HStack {
                Spacer()
                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    env.saveEntry(JournalEntry(createdAt: Date(), body: trimmed))
                    text = ""
                } label: {
                    Text("Save note").font(LifelogTheme.sans(12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .lifelogCard()
    }
}
