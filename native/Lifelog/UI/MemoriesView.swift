import SwiftUI

// MARK: - Snapshot

struct MemoryCard: Identifiable {
    var id: String
    var day: Date
    var relative: String
    var dateLong: String
    var description: String
    var photos: [MediaItem]
}

struct PastDayLine: Identifiable {
    var id: String
    var day: Date
    var records: Int
}

struct MemoriesSnapshot {
    var loaded = false
    var memories: [MemoryCard] = []
    var activeDays: Set<Int> = []
    var pastDays: [PastDayLine] = []

    /// One pass over every record instead of a full-archive scan per probed day.
    /// Results match the domain helpers: on-this-day looks back 25 years, and the
    /// same-month list looks back 10 years and orders by day of month.
    static func make(_ archive: Archive, month: Date, today: Date) -> MemoriesSnapshot {
        var snap = MemoriesSnapshot()
        snap.loaded = true
        snap.activeDays = archive.activityDaysIn(month)

        let calendar = Dates.calendar
        let selectedYear = calendar.component(.year, from: month)
        let selectedMonth = calendar.component(.month, from: month)
        let todayYear = calendar.component(.year, from: today)
        let todayMonth = calendar.component(.month, from: today)
        let todayDay = calendar.component(.day, from: today)

        var pastCounts: [Int: Int] = [:]
        var thisDayYears = Set<Int>()

        func visit(_ date: Date) {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = parts.year, let m = parts.month, let day = parts.day else { return }
            if m == selectedMonth, year < selectedYear, year >= selectedYear - 10 {
                pastCounts[year * 10_000 + m * 100 + day, default: 0] += 1
            }
            if m == todayMonth, day == todayDay, year < todayYear, year >= todayYear - 25 {
                thisDayYears.insert(year)
            }
        }

        for entry in archive.entries where !entry.draft && !entry.archived { visit(entry.createdAt) }
        for item in archive.media { visit(item.createdAt) }
        for place in archive.visits { visit(place.startAt) }
        for scrobble in archive.scrobbles { visit(scrobble.playedAt) }
        for record in archive.trackerRecords { visit(record.recordedAt) }
        for event in archive.events where !event.hidden { visit(event.occurredAt) }

        for year in thisDayYears.sorted(by: >) {
            let probe = Dates.date(year: year, month: todayMonth, day: todayDay)
            let summary = DaySummary.of(archive, probe)
            guard !summary.isEmpty else { continue }
            let memory = OnThisDayMemory(day: probe, summary: summary)
            snap.memories.append(MemoryCard(
                id: memory.id,
                day: probe,
                relative: memory.relativeLabel,
                dateLong: Dates.formatDayLong(probe),
                description: memory.description,
                photos: Array(summary.photos.prefix(6))
            ))
        }

        let lines = pastCounts.map { key, count -> PastDayLine in
            let year = key / 10_000
            let m = (key / 100) % 100
            let day = key % 100
            let date = Dates.date(year: year, month: m, day: day)
            return PastDayLine(id: Dates.dayKey(date), day: date, records: count)
        }
        snap.pastDays = lines.sorted {
            let left = Dates.component(.day, of: $0.day)
            let right = Dates.component(.day, of: $1.day)
            if left != right { return left > right }
            return $0.day > $1.day
        }
        return snap
    }
}

// MARK: - View

struct MemoriesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var month = Date()
    @State private var snapshot = MemoriesSnapshot()

    private struct Key: Equatable {
        var revision: Int
        var month: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                PageHeader(
                    eyebrow: "Looking back",
                    title: "Memories",
                    subtitle: "Only days you actually recorded appear here."
                )
                onThisDay
                calendar
                pastMonth
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .opacity(snapshot.loaded ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: snapshot.loaded)
        .task(id: Key(revision: env.revision, month: Dates.formatMonthYear(month))) {
            let archive = env.archive
            let shown = month
            let result = await offMain { MemoriesSnapshot.make(archive, month: shown, today: Date()) }
            guard !Task.isCancelled else { return }
            snapshot = result
        }
    }

    // MARK: On this day

    private var onThisDay: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(
                title: "On this day",
                detail: snapshot.memories.isEmpty ? nil : "\(snapshot.memories.count)"
            )
            if snapshot.memories.isEmpty {
                EmptyNote(
                    title: "Nothing from this date yet",
                    message: "As the years pass, entries and photos from today will surface here."
                )
            } else {
                ForEach(snapshot.memories) { memory in
                    Button { navigator.push(.journal(memory.day)) } label: {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(memory.relative)
                                .font(Typeface.micro)
                                .textCase(.uppercase)
                                .tracking(1)
                                .foregroundStyle(Palette.accent)
                            Text(memory.dateLong)
                                .font(Typeface.heading)
                                .foregroundStyle(Palette.ink)
                            Text(memory.description)
                                .font(Typeface.label)
                                .foregroundStyle(Palette.inkSecondary)
                                .multilineTextAlignment(.leading)
                            if !memory.photos.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: Space.sm) {
                                        ForEach(memory.photos) { item in
                                            EncryptedMediaImage(item: item, maxPixel: 260)
                                                .frame(width: 84, height: 84)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                    }
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surface()
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
    }

    // MARK: Calendar

    private var calendar: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(title: "Calendar", detail: Dates.formatMonthYear(month))
            MonthGrid(
                month: $month,
                activeDays: snapshot.activeDays,
                weekStartsMonday: env.settings.weekStartsMonday
            ) { day in
                navigator.push(.journal(day))
            }
            .surface()
        }
    }

    // MARK: Same month, earlier years

    @ViewBuilder
    private var pastMonth: some View {
        if !snapshot.pastDays.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(title: "Same month, earlier years", detail: "\(snapshot.pastDays.count) days")
                VStack(spacing: 0) {
                    ForEach(snapshot.pastDays.prefix(12)) { line in
                        Button { navigator.push(.journal(line.day)) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Dates.formatDayLong(line.day)).font(Typeface.label).foregroundStyle(Palette.ink)
                                    Text("\(line.records) \(Dates.plural(line.records, "record"))")
                                        .font(Typeface.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(Typeface.caption)
                                    .foregroundStyle(Palette.inkTertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, Space.sm)
                        }
                        .buttonStyle(RowButtonStyle())
                        Hairline()
                    }
                }
            }
        }
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    @Binding var month: Date
    let activeDays: Set<Int>
    let weekStartsMonday: Bool
    let onSelect: (Date) -> Void

    private var firstWeekday: Int { weekStartsMonday ? 2 : 1 }

    private var symbols: [String] {
        let all = ["S", "M", "T", "W", "T", "F", "S"]
        let shift = firstWeekday - 1
        return Array(all[shift...] + all[..<shift])
    }

    private var cells: [Int?] {
        let calendar = Dates.calendar
        let parts = calendar.dateComponents([.year, .month], from: month)
        guard let first = calendar.date(from: parts),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - firstWeekday + 7) % 7
        let days: [Int?] = range.map { Optional($0) }
        return [Int?](repeating: nil, count: leading) + days
    }

    private var canGoForward: Bool {
        let calendar = Dates.calendar
        let shown = calendar.dateComponents([.year, .month], from: month)
        let now = calendar.dateComponents([.year, .month], from: Date())
        return (shown.year ?? 0, shown.month ?? 0) < (now.year ?? 0, now.month ?? 0)
    }

    var body: some View {
        VStack(spacing: Space.md) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(Dates.formatMonthYear(month))
                    .font(Typeface.labelStrong)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(!canGoForward)
                .accessibilityLabel("Next month")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Typeface.micro)
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(day: day, active: activeDays.contains(day), isToday: isToday(day)) {
                            select(day)
                        }
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func date(_ day: Int) -> Date? {
        var parts = Dates.calendar.dateComponents([.year, .month], from: month)
        parts.day = day
        return Dates.calendar.date(from: parts)
    }

    private func isToday(_ day: Int) -> Bool {
        guard let date = date(day) else { return false }
        return Dates.sameDay(date, Date())
    }

    private func select(_ day: Int) {
        if let date = date(day), date <= Date() { onSelect(date) }
    }

    private func shift(_ delta: Int) {
        if let next = Dates.calendar.date(byAdding: .month, value: delta, to: month) { month = next }
    }
}

private struct DayCell: View {
    let day: Int
    let active: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(day)")
                .font(Typeface.caption.monospacedDigit())
                .fontWeight(active ? .semibold : .regular)
                .foregroundStyle(active ? Palette.onAccent : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    Circle()
                        .fill(active ? Palette.accent : Color.clear)
                        .padding(2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isToday ? Palette.accent : Color.clear, lineWidth: 1)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day \(day)" + (active ? ", has records" : "") + (isToday ? ", today" : ""))
    }
}
