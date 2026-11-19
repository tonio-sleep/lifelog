import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette
    @State private var day: Date
    @State private var showDrafts = false

    init(day: Date = Date()) {
        _day = State(initialValue: day)
    }

    private var timeline: [TimelineItem] { buildTimelineForDay(env.archive, day, includeHidden: true) }
    private var summary: DaySummary { DaySummary.of(env.archive, day) }

    var body: some View {
        VStack(spacing: 0) {
            dateBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if timeline.isEmpty {
                        EmptyState(
                            title: "No records for this day",
                            message: "Write a note, add an event, or log a tracker to begin this page.",
                            systemImage: "book.closed"
                        ) { router.push(.newEntry) }
                        .lifelogCard()
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(timeline) { item in
                                TimelineRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(item) }
                            }
                        }
                    }

                    if !summary.photos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Photos from this day") { router.push(.media) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(summary.photos) { item in
                                        EncryptedMediaImage(item: item)
                                            .frame(width: 112, height: 112)
                                            .clipShape(RoundedRectangle(cornerRadius: 15))
                                    }
                                }
                            }
                        }
                    }

                    if !env.archive.drafts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: "Unfinished",
                                action: { showDrafts.toggle() },
                                actionLabel: showDrafts ? "Hide" : "Show"
                            )
                            if showDrafts {
                                ForEach(env.archive.drafts) { entry in
                                    Button { router.push(.entry(entry.id)) } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(entry.displayTitle).font(LifelogTheme.sans(14, weight: .semibold))
                                                Text(entry.excerpt).font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").foregroundStyle(palette.tertiary)
                                        }
                                        .lifelogCard(padding: 14, radius: 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }

    private var dateBar: some View {
        HStack(spacing: 10) {
            Button {
                day = Dates.addingDays(-1, to: day)
            } label: {
                Image(systemName: "chevron.left")
            }
            DatePicker("", selection: $day, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .colorMultiply(palette.text)
            Button {
                day = Dates.addingDays(1, to: day)
            } label: {
                Image(systemName: "chevron.right")
            }
            Button { day = Date() } label: {
                Text("Today").font(LifelogTheme.sans(12, weight: .semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(palette.background.opacity(0.9))
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.6) }
    }

    private func open(_ item: TimelineItem) {
        guard let id = item.sourceId else { return }
        switch item.source {
        case .journal: router.push(.entry(id))
        case .manual: router.push(.event(id))
        case .photo: router.push(.media)
        case .tracker: router.push(.trackers)
        default: break
        }
    }
}
