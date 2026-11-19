import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var query = ""
    @State private var kind: SearchKind?

    private var hits: [SearchHit] {
        let all = searchArchive(env.archive, rawQuery: query)
        guard let kind else { return all }
        return all.filter { $0.kind == kind }
    }

    var body: some View {
        List {
            Section {
                TextField("Search entries, photos, places, music…", text: $query)
                    .font(LifelogTheme.sans(15))
                    .textFieldStyle(.plain)
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            filterPill(nil, title: "All")
                            ForEach(SearchKind.allCases, id: \.self) { item in
                                filterPill(item, title: item.label)
                            }
                        }
                    }
                }
                Section {
                    if hits.isEmpty {
                        EmptyState(title: "No matches", message: "Search is local. Try a different word or tag.", systemImage: "magnifyingglass", action: nil)
                    } else {
                        ForEach(hits) { hit in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(for: hit.kind))
                                    .frame(width: 22)
                                    .foregroundStyle(palette.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.title).font(LifelogTheme.sans(14, weight: .semibold))
                                    if !hit.subtitle.isEmpty {
                                        Text(hit.subtitle).font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary).lineLimit(2)
                                    }
                                    Text(Dates.formatShortDate(hit.date) + " · " + Dates.formatTime(hit.date))
                                        .font(LifelogTheme.sans(10)).foregroundStyle(palette.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("\(hits.count) results")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
    }

    private func filterPill(_ value: SearchKind?, title: String) -> some View {
        Button {
            kind = value
        } label: {
            Text(title)
                .font(LifelogTheme.sans(12, weight: .semibold))
                .foregroundStyle(kind == value ? palette.background : palette.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(kind == value ? palette.accent : palette.surfaceRaised))
                .overlay(Capsule().stroke(palette.border, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func icon(for kind: SearchKind) -> String {
        switch kind {
        case .journal: return "book.closed"
        case .photo: return "photo"
        case .tracker: return "checkmark.circle"
        case .place: return "mappin"
        case .visit: return "clock"
        case .music: return "music.note"
        case .event: return "calendar"
        }
    }
}
