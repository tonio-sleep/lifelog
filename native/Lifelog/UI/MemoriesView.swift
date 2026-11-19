import SwiftUI

struct MemoriesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette
    @State private var month = Date()

    private var memories: [OnThisDayMemory] { onThisDay(env.archive, Date()) }
    private var past: [DaySummary] { activeDaysInPreviousYears(env.archive, month, years: 10) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Looking back")
                    Text("Memories")
                        .font(LifelogTheme.serif(30, relativeTo: .largeTitle))
                    Text("Only days you actually recorded appear here.")
                        .font(LifelogTheme.sans(13)).foregroundStyle(palette.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "On this day", subtitle: memories.isEmpty ? "No earlier records for today" : "\(memories.count) \(Dates.plural(memories.count, "memory"))")
                    if memories.isEmpty {
                        EmptyState(title: "Nothing from this date", message: "As years pass, entries and photos from today will surface here.", systemImage: "clock.arrow.circlepath", action: nil)
                            .lifelogCard()
                    } else {
                        ForEach(memories) { memory in
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: memory.relativeLabel)
                                Text(Dates.formatDayLong(memory.day))
                                    .font(LifelogTheme.serif(20, relativeTo: .title3))
                                Text(memory.description)
                                    .font(LifelogTheme.sans(13)).foregroundStyle(palette.secondary)
                                if !memory.summary.photos.isEmpty {
                                    ScrollView(.horizontal) {
                                        HStack {
                                            ForEach(Array(memory.summary.photos.prefix(6))) { item in
                                                EncryptedMediaImage(item: item)
                                                    .frame(width: 76, height: 76)
                                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                            }
                                        }
                                    }
                                }
                            }
                            .lifelogCard()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Activity calendar", subtitle: Dates.formatMonthYear(month))
                    MonthGrid(month: $month, activeDays: activityDays(env.archive, month)) { day in
                        router.push(.journal(day))
                    }
                    .lifelogCard()
                }

                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Same month, earlier years", subtitle: "\(past.count) recorded days")
                        ForEach(Array(past.prefix(10)), id: \.day) { summary in
                            Button {
                                router.push(.journal(summary.day))
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(Dates.formatShortDate(summary.day)).font(LifelogTheme.sans(14, weight: .semibold))
                                        Text("\(summary.totalRecords) records").font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(palette.tertiary)
                                }
                                .lifelogCard(padding: 13, radius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
    }
}

private struct MonthGrid: View {
    @Environment(\.lifelogPalette) private var palette
    @Binding var month: Date
    let activeDays: Set<Int>
    let onSelect: (Date) -> Void

    private let symbols = ["M", "T", "W", "T", "F", "S", "S"]

    private var days: [Int?] {
        let comps = Dates.calendar.dateComponents([.year, .month], from: month)
        guard let first = Dates.calendar.date(from: comps),
              let range = Dates.calendar.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = Dates.calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading) + Array(range.lowerBound...range.upperBound).map { Optional($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { month = Dates.calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(Dates.formatMonthYear(month)).font(LifelogTheme.sans(14, weight: .semibold))
                Spacer()
                Button { month = Dates.calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                    Image(systemName: "chevron.right")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(LifelogTheme.sans(10, weight: .bold)).foregroundStyle(palette.tertiary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    Button {
                        guard let day else { return }
                        var components = Dates.calendar.dateComponents([.year, .month], from: month)
                        components.day = day
                        if let date = Dates.calendar.date(from: components) { onSelect(date) }
                    } label: {
                        ZStack {
                            if let day {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(activeDays.contains(day) ? palette.accent.opacity(0.82) : palette.surfaceRaised)
                                Text("\(day)")
                                    .font(LifelogTheme.sans(11, weight: activeDays.contains(day) ? .bold : .regular))
                                    .foregroundStyle(activeDays.contains(day) ? palette.background : palette.secondary)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    .disabled(day == nil)
                }
            }
        }
    }
}
