import SwiftUI
import UIKit

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct InsightsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: Router
    @Environment(\.lifelogPalette) private var palette
    @State private var showBackup = false

    private var entries: [JournalEntry] { env.archive.entries.filter { !$0.archived && !$0.draft } }
    private var moods: [Int] { entries.compactMap(\.mood) }
    private var averageMood: Double? {
        guard !moods.isEmpty else { return nil }
        return Double(moods.reduce(0, +)) / Double(moods.count)
    }
    private var music: MusicDaySummary { MusicDaySummary.fromScrobbles(env.archive.scrobbles) }
    private var recentDays: [(day: Date, value: Double)] {
        let end = Date()
        let all = env.archive.entries.filter { !$0.archived && !$0.draft }
        var result: [(Date, Double)] = []
        for offset in (0..<14).reversed() {
            let day = Dates.dayStart(Dates.addingDays(-offset, to: end))
            let count = all.filter { Dates.sameDay($0.createdAt, day) }.count
            result.append((day, Double(count)))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Your archive")
                    Text("Insights")
                        .font(LifelogTheme.serif(30, relativeTo: .largeTitle))
                    Text("Patterns, not grades. Every number comes from a record you kept.")
                        .font(LifelogTheme.sans(13)).foregroundStyle(palette.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(value: "\(entries.count)", label: "Entries", systemImage: "book.closed")
                    StatTile(value: "\(env.archive.media.count)", label: "Photos", systemImage: "photo")
                    StatTile(value: "\(env.archive.trackerRecords.count)", label: "Updates", systemImage: "checkmark.circle")
                    StatTile(value: averageMood.map { String(format: "%.1f", $0) } ?? "—", label: "Average mood", systemImage: "heart", accent: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Writing rhythm", subtitle: "Entries in the last 14 days")
                    BarChart(
                        values: recentDays.map(\.value),
                        labels: recentDays.map { Dates.component(.day, of: $0.day) % 2 == 0 ? "\(Dates.component(.day, of: $0.day))" : "" },
                        height: 110
                    )
                    .lifelogCard()
                }

                if !env.archive.activeTrackers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Practices", subtitle: "Last 14 days") { router.push(.trackers) }
                        ForEach(Array(env.archive.activeTrackers.prefix(4))) { tracker in
                            let series = TrackerMath.dailySeries(tracker, env.archive.trackerRecords, endDay: Date(), days: 14)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: tracker.icon.isEmpty ? "circle" : tracker.icon)
                                        .foregroundStyle(palette.accent)
                                    Text(tracker.name).font(LifelogTheme.sans(14, weight: .semibold))
                                    Spacer()
                                    Text("\(series.filter { $0.value > 0 }.count)/14 days")
                                        .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                                }
                                BarChart(values: series.map(\.value), height: 60)
                            }
                            .lifelogCard()
                        }
                    }
                }

                if !music.scrobbles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Listening", subtitle: "\(music.total) tracks · \(music.uniqueArtists) artists")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(music.topArtists.prefix(5)), id: \.name) { artist in
                                HStack {
                                    Text(artist.name).font(LifelogTheme.sans(13))
                                    Spacer()
                                    Text("\(artist.plays)")
                                        .font(LifelogTheme.sans(12, weight: .semibold))
                                        .foregroundStyle(palette.secondary)
                                }
                            }
                        }
                        .lifelogCard()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Keep it safe", subtitle: "Exports are encrypted with a passphrase you choose")
                    Button { showBackup = true } label: {
                        Label("Create encrypted backup", systemImage: "externaldrive.badge.plus")
                            .font(LifelogTheme.sans(14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showBackup) { BackupExportView().environmentObject(env) }
    }
}

struct BackupExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var exportedURL: IdentifiableURL?
    @State private var isExporting = false

    private var matches: Bool { passphrase.count >= 8 && passphrase == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup passphrase", text: $passphrase)
                    SecureField("Repeat passphrase", text: $confirm)
                    if !passphrase.isEmpty && passphrase.count < 8 {
                        Text("Use at least 8 characters.").font(.caption).foregroundStyle(.red)
                    }
                    if !confirm.isEmpty && passphrase != confirm {
                        Text("Passphrases do not match.").font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("The backup includes your archive and, when available, decrypted media re-encrypted with this passphrase. Store it somewhere you trust.")
                        .font(LifelogTheme.sans(12)).foregroundStyle(.secondary)
                }
                Section {
                    Button(isExporting ? "Creating…" : "Create backup") {
                        isExporting = true
                        let environment = env
                        Task {
                            let current = passphrase
                            let url = await environment.exportBackup(passphrase: current)
                            await MainActor.run {
                                isExporting = false
                                if let url { exportedURL = IdentifiableURL(url: url) }
                            }
                        }
                    }
                    .disabled(!matches || isExporting)
                }
            }
            .navigationTitle("Encrypted backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $exportedURL) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
