import SwiftUI

private struct TimelineGroup: Identifiable {
    let date: Date
    let rows: [DayRow]
    var id: Date { date }
}

private struct TimelineKey: Equatable {
    var revision: Int
    var anchor: String
    var days: Int
    var filter: Set<TimelineSource>
    var showHidden: Bool
}

/// A chronological read across several days. A native List keeps long histories
/// recycled and makes swipe actions work. Rows are always derived from the archive.
struct TimelineView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator

    @State private var anchor: Date
    @State private var days = 14
    @State private var filter: Set<TimelineSource> = []
    @State private var showHidden = false
    @State private var groups: [TimelineGroup] = []
    @State private var loaded = false

    init(day: Date? = nil) {
        _anchor = State(initialValue: day ?? Date())
    }

    private var key: TimelineKey {
        TimelineKey(
            revision: env.revision,
            anchor: Dates.dayKey(anchor),
            days: days,
            filter: filter,
            showHidden: showHidden
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            content
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Show hidden moments", isOn: $showHidden)
            }
        }
        .task(id: key) { await rebuild() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                DatePicker("Jump to date", selection: $anchor, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                Spacer()
                Button("Today") { anchor = Date(); days = 14 }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, Space.page)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    Button("All") { filter = [] }
                        .buttonStyle(ChipStyle(selected: filter.isEmpty))
                    ForEach(TimelineSource.allCases, id: \.self) { source in
                        Button(source.label) { toggle(source) }
                            .buttonStyle(ChipStyle(selected: filter.contains(source)))
                            .accessibilityAddTraits(filter.contains(source) ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Space.page)
            }
            Hairline()
        }
    }

    private func toggle(_ source: TimelineSource) {
        if filter.contains(source) { filter.remove(source) } else { filter.insert(source) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loaded && groups.isEmpty {
            ScrollView {
                EmptyNote(
                    title: "No records in this window",
                    message: "The timeline shows only what you recorded. Try another date, widen the filters, or add a moment.",
                    actionTitle: "Add a moment"
                ) { navigator.present(.newEvent(anchor)) }
                .padding(Space.page)
            }
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            Button { navigator.open(row) } label: { DayRowView(row: row) }
                                .buttonStyle(RowButtonStyle())
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Palette.line)
                                .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeActions(for: row) }
                        }
                    } header: {
                        dayHeader(group.date)
                    }
                }
                if loaded && !groups.isEmpty {
                    footer
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .opacity(loaded ? 1 : 0)
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        Button { navigator.push(.journal(date)) } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(Dates.relativeDayLabel(date))
                    .font(Typeface.heading)
                    .foregroundStyle(Palette.ink)
                Text(Dates.formatDayHeader(date))
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Image(systemName: "book")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("Open journal page for \(Dates.formatDayLong(date))")
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        VStack(spacing: Space.sm) {
            Button("Load earlier days") { days = min(days + 14, 365) }
                .buttonStyle(QuietButtonStyle())
                .disabled(days >= 365)
            let total = groups.reduce(0) { $0 + $1.rows.count }
            Text("\(total) \(Dates.plural(total, "record")) across \(days) days")
                .font(Typeface.micro)
                .foregroundStyle(Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func swipeActions(for row: DayRow) -> some View {
        if row.source == .manual, let id = row.sourceId {
            Button {
                toggleHidden(id)
            } label: {
                Label(row.hidden ? "Show" : "Hide", systemImage: row.hidden ? "eye" : "eye.slash")
            }
            .tint(Palette.amber)
        } else if row.source == .tracker, let id = row.sourceId {
            Button(role: .destructive) {
                env.deleteTrackerRecord(id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func toggleHidden(_ id: String) {
        guard var event = env.archive.events.first(where: { $0.id == id }) else { return }
        event.hidden.toggle()
        env.saveEvent(event)
    }

    // MARK: Data

    private func rebuild() async {
        let archive = env.archive
        let anchorDay = anchor
        let span = days
        let active = filter
        let hidden = showHidden
        let result: [TimelineGroup] = await offMain {
            var built: [TimelineGroup] = []
            for offset in 0..<span {
                let day = Dates.addingDays(-offset, to: anchorDay)
                var rows = DayRow.rows(archive, day, includeHidden: hidden)
                if !active.isEmpty { rows = rows.filter { active.contains($0.source) } }
                if !rows.isEmpty { built.append(TimelineGroup(date: day, rows: rows)) }
            }
            return built
        }
        guard !Task.isCancelled else { return }
        groups = result
        loaded = true
    }
}
