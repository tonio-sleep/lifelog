import SwiftUI
import Charts

// MARK: - Snapshot

struct DayValue: Identifiable {
    var day: Date
    var value: Double
    var id: Date { day }
}

struct PracticeInsight: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var color: UInt32
    var daysLogged: Int
    var series: [DayValue]
}

struct InsightsSnapshot {
    var loaded = false
    var entryCount = 0
    var wordCount = 0
    var mediaCount = 0
    var practiceUpdates = 0
    var averageMood: Double?
    var moodSeries: [DayValue] = []
    var writingSeries: [DayValue] = []
    var writingTotal = 0
    var sleepSeries: [DayValue] = []
    var averageSleep: Double?
    var averageSteps: Int?
    var practices: [PracticeInsight] = []
    var topArtists: [TopArtist] = []
    var trackTotal = 0

    static func make(_ archive: Archive, now: Date) -> InsightsSnapshot {
        var snap = InsightsSnapshot()
        snap.loaded = true

        let written = archive.entries.filter { !$0.draft && !$0.archived && !$0.isMetricsOnly }
        snap.entryCount = written.count
        snap.wordCount = written.reduce(0) { $0 + $1.body.split(whereSeparator: { $0.isWhitespace }).count }
        snap.mediaCount = archive.media.filter { !$0.isAudio }.count
        snap.practiceUpdates = archive.trackerRecords.count

        // Bucket by day once.
        var perDayEntries: [String: Int] = [:]
        var perDayMood: [String: [Int]] = [:]
        var perDaySleep: [String: Double] = [:]
        var perDaySteps: [String: Int] = [:]
        for entry in archive.entries where !entry.draft && !entry.archived {
            let key = Dates.dayKey(entry.createdAt)
            if !entry.isMetricsOnly { perDayEntries[key, default: 0] += 1 }
            if let mood = entry.mood { perDayMood[key, default: []].append(mood) }
            if let sleep = entry.sleepHours { perDaySleep[key] = max(perDaySleep[key] ?? 0, sleep) }
            if let steps = entry.steps { perDaySteps[key] = max(perDaySteps[key] ?? 0, steps) }
        }

        let today = Dates.dayStart(now)
        func days(_ count: Int) -> [Date] {
            (0..<count).reversed().map { Dates.addingDays(-$0, to: today) }
        }

        let fortnight = days(14)
        snap.writingSeries = fortnight.map { DayValue(day: $0, value: Double(perDayEntries[Dates.dayKey($0)] ?? 0)) }
        snap.writingTotal = Int(snap.writingSeries.reduce(0) { $0 + $1.value })

        let month = days(30)
        snap.moodSeries = month.compactMap { day in
            guard let moods = perDayMood[Dates.dayKey(day)], !moods.isEmpty else { return nil }
            return DayValue(day: day, value: Double(moods.reduce(0, +)) / Double(moods.count))
        }
        if !snap.moodSeries.isEmpty {
            snap.averageMood = snap.moodSeries.reduce(0) { $0 + $1.value } / Double(snap.moodSeries.count)
        }

        snap.sleepSeries = fortnight.compactMap { day in
            guard let sleep = perDaySleep[Dates.dayKey(day)] else { return nil }
            return DayValue(day: day, value: sleep)
        }
        if !snap.sleepSeries.isEmpty {
            snap.averageSleep = snap.sleepSeries.reduce(0) { $0 + $1.value } / Double(snap.sleepSeries.count)
        }
        let stepDays = fortnight.compactMap { perDaySteps[Dates.dayKey($0)] }
        if !stepDays.isEmpty { snap.averageSteps = stepDays.reduce(0, +) / stepDays.count }

        // Practices over the last two weeks.
        var recordsByTracker: [String: [String: Int]] = [:]
        for record in archive.trackerRecords {
            recordsByTracker[record.trackerId, default: [:]][Dates.dayKey(record.recordedAt), default: 0] += 1
        }
        snap.practices = archive.activeTrackers.prefix(6).map { tracker in
            let counts = recordsByTracker[tracker.id] ?? [:]
            let series = fortnight.map { DayValue(day: $0, value: Double(counts[Dates.dayKey($0)] ?? 0)) }
            return PracticeInsight(
                id: tracker.id,
                name: tracker.name,
                symbol: tracker.icon.isEmpty ? "circle" : tracker.icon,
                color: tracker.colorValue,
                daysLogged: series.filter { $0.value > 0 }.count,
                series: series
            )
        }

        let cutoff = Dates.addingDays(-30, to: today)
        let recentPlays = archive.scrobbles.filter { $0.playedAt >= cutoff }
        let music = MusicDaySummary.fromScrobbles(recentPlays)
        snap.topArtists = Array(music.topArtists.prefix(5))
        snap.trackTotal = recentPlays.count
        return snap
    }
}

// MARK: - View

struct InsightsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var snapshot = InsightsSnapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                PageHeader(
                    eyebrow: "Patterns",
                    title: "Insights",
                    subtitle: "Plain summaries of what you recorded. No scores, no streaks."
                )
                if snapshot.loaded && snapshot.entryCount == 0 && snapshot.practiceUpdates == 0 && snapshot.mediaCount == 0 {
                    EmptyNote(
                        title: "Not enough to show yet",
                        message: "Write a few entries or log a practice, and gentle patterns will appear here."
                    )
                } else {
                    totals
                    writing
                    mood
                    body_
                    practices
                    listening
                }
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .opacity(snapshot.loaded ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: snapshot.loaded)
        .task(id: env.revision) {
            let archive = env.archive
            let now = Date()
            let result = await offMain { InsightsSnapshot.make(archive, now: now) }
            guard !Task.isCancelled else { return }
            snapshot = result
        }
    }

    // MARK: Sections

    private var totals: some View {
        VStack(spacing: Space.md) {
            Hairline()
            HStack(alignment: .top, spacing: Space.lg) {
                Figure(value: snapshot.entryCount.formatted(), label: "Entries")
                Figure(value: snapshot.wordCount.formatted(), label: "Words")
                Figure(value: snapshot.mediaCount.formatted(), label: "Photos & video")
                Figure(value: snapshot.practiceUpdates.formatted(), label: "Practice updates")
            }
            Hairline()
        }
    }

    private var writing: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(title: "Writing", detail: "Last 14 days")
            Chart(snapshot.writingSeries) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Entries", item.value)
                )
                .foregroundStyle(Palette.accent)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
            }
            .frame(height: 130)
            .accessibilityLabel("Entries per day for the last 14 days")
            .accessibilityValue("\(snapshot.writingTotal) entries in total")
            Text("\(snapshot.writingTotal) \(Dates.plural(snapshot.writingTotal, "entry", "entries")) in the last two weeks.")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    @ViewBuilder
    private var mood: some View {
        if snapshot.moodSeries.count >= 2, let average = snapshot.averageMood {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Mood", detail: "Last 30 days")
                Chart(snapshot.moodSeries) { item in
                    LineMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Mood", item.value)
                    )
                    .foregroundStyle(Palette.accent)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Day", item.day, unit: .day),
                        y: .value("Mood", item.value)
                    )
                    .foregroundStyle(Palette.accent)
                    .symbolSize(24)
                }
                .chartYScale(domain: 1...10)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [1.0, 5.0, 10.0])
                }
                .frame(height: 140)
                .accessibilityLabel("Mood on days you recorded it, last 30 days")
                Text("Average \(Dates.formatCompactNumber((average * 10).rounded() / 10)) out of 10, across \(snapshot.moodSeries.count) recorded days.")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var body_: some View {
        if snapshot.averageSleep != nil || snapshot.averageSteps != nil {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Sleep and movement", detail: "Last 14 days")
                if !snapshot.sleepSeries.isEmpty {
                    Chart(snapshot.sleepSeries) { item in
                        BarMark(
                            x: .value("Day", item.day, unit: .day),
                            y: .value("Hours", item.value)
                        )
                        .foregroundStyle(Palette.moss)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.day(), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                    }
                    .frame(height: 120)
                    .accessibilityLabel("Hours of sleep per day")
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    if let sleep = snapshot.averageSleep {
                        Figure(value: Dates.formatCompactNumber((sleep * 10).rounded() / 10) + " h", label: "Average sleep")
                    }
                    if let steps = snapshot.averageSteps {
                        Figure(value: steps.formatted(), label: "Average steps")
                    }
                }
                if !env.healthConnected {
                    InfoLine(text: "These come from entries that carry sleep or steps. Connect Apple Health in Settings to fill them in automatically.", symbol: "heart")
                }
            }
        }
    }

    @ViewBuilder
    private var practices: some View {
        if !snapshot.practices.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Practices", detail: "Last 14 days")
                ForEach(snapshot.practices) { practice in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Image(systemName: practice.symbol)
                                .foregroundStyle(Color(hex: practice.color))
                                .accessibilityHidden(true)
                            Text(practice.name).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(practice.daysLogged) of 14 days")
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Chart(practice.series) { item in
                            BarMark(
                                x: .value("Day", item.day, unit: .day),
                                y: .value("Updates", item.value)
                            )
                            .foregroundStyle(Color(hex: practice.color))
                            .cornerRadius(2)
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 36)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.vertical, Space.xs)
                }
            }
        }
    }

    @ViewBuilder
    private var listening: some View {
        if !snapshot.topArtists.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Listening", detail: "\(snapshot.trackTotal) \(Dates.plural(snapshot.trackTotal, "track")) in 30 days")
                VStack(spacing: 0) {
                    ForEach(snapshot.topArtists, id: \.name) { artist in
                        HStack {
                            Text(artist.name).font(Typeface.label).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(artist.plays)").font(Typeface.caption.monospacedDigit()).foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.vertical, Space.sm)
                        .accessibilityElement(children: .combine)
                        Hairline()
                    }
                }
            }
        }
    }
}
