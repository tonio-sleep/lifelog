import SwiftUI

private struct CalendarCell: Identifiable {
    let id: String
    let date: Date?
    let day: Int
}

/// A month grid with a compact week option. Dots show how much was recorded;
/// they are a count of real records, never a streak or a score.
struct DayCalendar: View {
    let selected: Date
    let activity: [String: Int]
    var onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month = Dates.dayStart(Date())
    @State private var compact = false

    private let initials = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: Space.md) {
            HStack(spacing: Space.xs) {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(.footnote).weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Text(Dates.formatMonthYear(month))
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 108)

                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote).weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")

                Spacer(minLength: 4)

                Picker("Calendar view", selection: $compact) {
                    Text("Week").tag(true)
                    Text("Month").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 104)
            }

            if compact { weekStrip } else { monthGrid }
        }
        .onChange(of: selected) { _, new in
            let year = Dates.component(.year, of: new)
            let monthNumber = Dates.component(.month, of: new)
            if year != Dates.component(.year, of: month) ||
                monthNumber != Dates.component(.month, of: month) {
                month = Dates.dayStart(new)
            }
        }
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.22), value: compact)
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.22), value: month)
    }

    // MARK: Month

    private var monthGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(initials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(Typeface.micro)
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                spacing: 2
            ) {
                ForEach(monthCells) { cell in
                    if let date = cell.date {
                        dayCell(date: date, day: cell.day)
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
        }
    }

    private var monthCells: [CalendarCell] {
        let year = Dates.component(.year, of: month)
        let monthNumber = Dates.component(.month, of: month)
        let first = Dates.date(year: year, month: monthNumber, day: 1)
        let lead = Dates.calendar.component(.weekday, from: first) - 1
        let count = Dates.calendar.range(of: .day, in: .month, for: first)?.count ?? 30

        var cells: [CalendarCell] = []
        for index in 0..<max(0, lead) {
            cells.append(CalendarCell(id: "lead-\(index)", date: nil, day: 0))
        }
        for day in 1...count {
            let date = Dates.date(year: year, month: monthNumber, day: day)
            cells.append(CalendarCell(id: Dates.dayKey(date), date: date, day: day))
        }
        while cells.count % 7 != 0 {
            cells.append(CalendarCell(id: "pad-\(cells.count)", date: nil, day: 0))
        }
        return cells
    }

    // MARK: Week

    private var weekStrip: some View {
        let weekday = Dates.calendar.component(.weekday, from: Dates.dayStart(selected)) - 1
        let start = Dates.addingDays(-weekday, to: Dates.dayStart(selected))
        return HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { offset in
                let date = Dates.addingDays(offset, to: start)
                dayCell(date: date, day: Dates.component(.day, of: date))
            }
        }
    }

    // MARK: Day

    @ViewBuilder
    private func dayCell(date: Date, day: Int) -> some View {
        let key = Dates.dayKey(date)
        let count = activity[key] ?? 0
        let isSelected = Dates.sameDay(date, selected)
        let isToday = Dates.sameDay(date, Date())
        let level = min(3, count)
        let future = date > Date()

        Button { onSelect(date) } label: {
            VStack(spacing: 3) {
                Text(initials[Dates.calendar.component(.weekday, from: date) - 1])
                    .font(Typeface.micro)
                    .foregroundStyle(isSelected ? Palette.onAccent.opacity(0.8) : Palette.inkTertiary)

                ZStack {
                    if isSelected {
                        Circle().fill(Palette.accent)
                    } else if isToday {
                        Circle().strokeBorder(Palette.accent, lineWidth: 1.2)
                    }
                    Text("\(day)")
                        .font(Typeface.label)
                        .foregroundStyle(
                            isSelected ? Palette.onAccent : (isToday ? Palette.accent : Palette.ink)
                        )
                }
                .frame(width: 30, height: 30)

                HStack(spacing: 2) {
                    if level == 0 {
                        Circle().fill(Palette.line).frame(width: 3, height: 3)
                    } else {
                        ForEach(0..<level, id: \.self) { _ in
                            Circle().fill(Palette.moss).frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
            .opacity(future ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Dates.formatDayLong(date)), \(count) \(Dates.plural(count, "record"))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shift(_ delta: Int) {
        guard let next = Dates.calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
    }
}
