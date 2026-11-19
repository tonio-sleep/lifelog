import SwiftUI

/// A chronological read across several days. Timeline rows are always derived
/// from the archive; nothing here becomes a second source of truth.
struct TimelineView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette

    @State private var anchor: Date
    @State private var activeSources: Set<TimelineSource> = Set(TimelineSource.allCases)

    init(day: Date? = nil) {
        _anchor = State(initialValue: day ?? Date())
    }

    private struct DayGroup: Identifiable {
        let date: Date
        let items: [TimelineItem]
        var id: Date { date }
    }

    private var groups: [DayGroup] {
        (0..<14).reversed().compactMap { offset in
            let day = Dates.addingDays(-offset, to: anchor)
            let items = buildTimelineForDay(env.archive, day)
                .filter { activeSources.contains($0.source) }
            return items.isEmpty ? nil : DayGroup(date: day, items: items)
        }
    }

    private var totalShown: Int { groups.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            filterBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if groups.isEmpty {
                        EmptyState(
                            title: "No records in this window",
                            message: "The timeline only shows what you actually recorded. Try another date or widen the filters.",
                            systemImage: "calendar.day.timeline.left"
                        ) { router.push(.newEvent) }
                        .lifelogCard()
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    router.push(.journal(group.date))
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(Dates.relativeDayLabel(group.date))
                                            .font(LifelogTheme.serif(20, relativeTo: .title2))
                                            .foregroundStyle(palette.text)
                                        Text(Dates.formatDayHeader(group.date))
                                            .font(LifelogTheme.sans(12))
                                            .foregroundStyle(palette.secondary)
                                        Spacer()
                                        Image(systemName: "book.closed")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(palette.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)

                                VStack(spacing: 8) {
                                    ForEach(group.items) { item in
                                        TimelineRow(item: item)
                                            .contentShape(Rectangle())
                                            .onTapGesture { open(item) }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                hideAction(for: item)
                                            }
                                    }
                                }
                            }
                        }
                    }

                    Text("\(totalShown) \(Dates.plural(totalShown, "record")) across the last 14 days · ordered by original timestamp")
                        .font(LifelogTheme.sans(11))
                        .foregroundStyle(palette.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.newEvent)
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .accessibilityLabel("Add timeline event")
            }
        }
    }

    private var dateBar: some View {
        HStack(spacing: 10) {
            Button {
                anchor = Dates.addingDays(-1, to: anchor)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")

            DatePicker("", selection: $anchor, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .colorMultiply(palette.text)

            Button {
                anchor = Dates.addingDays(1, to: anchor)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")

            Button {
                anchor = Date()
            } label: {
                Text("Today")
                    .font(LifelogTheme.sans(12, weight: .semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(palette.background.opacity(0.92))
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.6) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimelineSource.allCases, id: \.self) { source in
                    Button {
                        toggle(source)
                    } label: {
                        HStack(spacing: 5) {
                            if activeSources.contains(source) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            Text(source.label)
                                .font(LifelogTheme.sans(11, weight: .medium))
                        }
                        .foregroundStyle(activeSources.contains(source) ? palette.background : palette.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(activeSources.contains(source) ? palette.accent : palette.surfaceRaised))
                        .overlay(Capsule().stroke(palette.border, lineWidth: activeSources.contains(source) ? 0 : 0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.label) filter")
                    .accessibilityValue(activeSources.contains(source) ? "On" : "Off")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(palette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.6) }
    }

    private func toggle(_ source: TimelineSource) {
        if activeSources.contains(source) {
            if activeSources.count > 1 { activeSources.remove(source) }
        } else {
            activeSources.insert(source)
        }
    }

    @ViewBuilder
    private func hideAction(for item: TimelineItem) -> some View {
        if item.source == .manual,
           let id = item.sourceId,
           var event = env.archive.events.first(where: { $0.id == id }) {
            Button {
                event.hidden.toggle()
                env.saveEvent(event)
            } label: {
                Label(event.hidden ? "Show" : "Hide", systemImage: event.hidden ? "eye" : "eye.slash")
            }
            .tint(palette.warning)
        }
    }

    private func open(_ item: TimelineItem) {
        guard let id = item.sourceId else {
            if item.source == .location { router.push(.map(item.at)) }
            return
        }
        switch item.source {
        case .journal: router.push(.entry(id))
        case .manual: router.push(.event(id))
        case .photo: router.push(.media)
        case .tracker: router.push(.trackers)
        case .location: router.push(.map(item.at))
        case .music: break
        }
    }
}
