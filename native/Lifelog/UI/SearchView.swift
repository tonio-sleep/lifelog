import SwiftUI

/// Local-only search. Nothing typed here leaves the device.
struct SearchSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var kinds: Set<SearchKind> = []
    @State private var searching = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visible: [SearchHit] {
        kinds.isEmpty ? hits : hits.filter { kinds.contains($0.kind) }
    }

    private var presentKinds: [SearchKind] {
        SearchKind.allCases.filter { kind in hits.contains { $0.kind == kind } }
    }

    var body: some View {
        NavigationStack {
            List {
                if !presentKinds.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.sm) {
                                Button("All") { kinds = [] }
                                    .buttonStyle(ChipStyle(selected: kinds.isEmpty))
                                ForEach(presentKinds, id: \.self) { kind in
                                    Button(kind.label) { toggle(kind) }
                                        .buttonStyle(ChipStyle(selected: kinds.contains(kind)))
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if trimmed.isEmpty {
                    EmptyNote(
                        title: "Search your archive",
                        message: "Entries, photos, practices, places, visits, tracks, and moments. Everything is searched on this device."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if visible.isEmpty && !searching {
                    EmptyNote(title: "No matches", message: "Nothing in your archive matches “\(trimmed)”.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visible) { hit in
                        Button { navigator.open(hit) } label: { SearchRow(hit: hit) }
                            .buttonStyle(RowButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Palette.line)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your archive")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: query) { await run() }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ kind: SearchKind) {
        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
    }

    /// Waits for a pause in typing, then searches off the main thread.
    private func run() async {
        let text = trimmed
        guard !text.isEmpty else {
            hits = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        let archive = env.archive
        let result = await offMain { searchArchive(archive, rawQuery: text) }
        guard !Task.isCancelled else { return }
        hits = result
        searching = false
    }
}

private struct SearchRow: View {
    let hit: SearchHit

    private var symbol: String {
        switch hit.kind {
        case .journal: return "book.closed"
        case .photo: return "photo"
        case .tracker: return "checkmark.circle"
        case .place: return "star"
        case .visit: return "mappin"
        case .music: return "music.note"
        case .event: return "sparkle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(.footnote).weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.accentSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.kind.label + " · " + Dates.formatShortDate(hit.date))
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.inkTertiary)
                Text(hit.title).font(Typeface.bodyStrong).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                if !hit.subtitle.isEmpty {
                    Text(hit.subtitle)
                        .font(Typeface.label)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm)
        .accessibilityElement(children: .combine)
    }
}
