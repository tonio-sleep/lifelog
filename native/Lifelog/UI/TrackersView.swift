import SwiftUI

struct TrackersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var editing: TrackerDefinition?
    @State private var showEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Personal measures")
                    Text("Trackers")
                        .font(LifelogTheme.serif(29, relativeTo: .largeTitle))
                    Text("Keep what matters. Ignore the scoreboard.")
                        .font(LifelogTheme.sans(13)).foregroundStyle(palette.secondary)
                }

                if env.archive.trackers.isEmpty {
                    EmptyState(title: "No trackers yet", message: "Track a habit, a measurement, a duration, or a simple note.", systemImage: "checkmark.circle") {
                        editing = .blank()
                        showEditor = true
                    }
                    .lifelogCard()
                } else {
                    ForEach(env.archive.activeTrackers) { tracker in
                        TrackerCard(tracker: tracker)
                    }

                    if env.archive.trackers.contains(where: { $0.archived || !$0.active }) {
                        SectionHeader(title: "Archived", subtitle: "No longer shown in daily views")
                        ForEach(env.archive.trackers.filter { $0.archived || !$0.active }) { tracker in
                            HStack {
                                Image(systemName: tracker.icon).foregroundStyle(palette.tertiary)
                                Text(tracker.name).font(LifelogTheme.sans(14))
                                Spacer()
                                Button("Restore") {
                                    var item = tracker
                                    item.archived = false
                                    item.active = true
                                    env.saveTracker(item)
                                }
                                .font(LifelogTheme.sans(12, weight: .semibold))
                            }
                            .lifelogCard(padding: 13, radius: 14)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 30)
        }
        .navigationTitle("Trackers")
        .toolbar {
            Button {
                editing = .blank()
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showEditor) {
            if let editing {
                TrackerEditorView(tracker: editing).environmentObject(env)
            }
        }
    }
}

private struct TrackerCard: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    let tracker: TrackerDefinition
    @State private var showHistory = false

    private var series: [Double] { TrackerMath.dailySeries(tracker, env.archive.trackerRecords, endDay: Date(), days: 14).map(\.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Color(hex: tracker.colorValue).opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: tracker.icon)
                        .foregroundStyle(Color(hex: tracker.colorValue))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name).font(LifelogTheme.sans(15, weight: .semibold))
                    Text(tracker.type.label + (tracker.unit.isEmpty ? "" : " · \(tracker.unit)"))
                        .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Button { showHistory.toggle() } label: {
                    Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }

            BarChart(values: series, height: 54)

            HStack(spacing: 16) {
                Label(TrackerMath.dailyLabel(tracker, env.archive.trackerRecords, Date()) ?? "Not logged today", systemImage: "checkmark.circle")
                if !tracker.targetLabel.isEmpty { Text(tracker.targetLabel) }
            }
            .font(LifelogTheme.sans(10))
            .foregroundStyle(palette.secondary)

            if showHistory {
                Divider()
                let records = env.archive.trackerRecords
                    .filter { $0.trackerId == tracker.id }
                    .sorted { $0.recordedAt > $1.recordedAt }
                    .prefix(8)
                if records.isEmpty {
                    Text("No updates yet.").font(LifelogTheme.sans(12)).foregroundStyle(palette.tertiary)
                } else {
                    ForEach(Array(records)) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(TrackerMath.recordLabel(tracker, record))
                                    .font(LifelogTheme.sans(12, weight: .medium))
                                if !record.note.isEmpty {
                                    Text(record.note).font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                                }
                            }
                            Spacer()
                            Text(Dates.formatTime(record.recordedAt))
                                .font(LifelogTheme.sans(10)).foregroundStyle(palette.tertiary)
                            Button {
                                env.deleteTrackerRecord(record.id)
                            } label: {
                                Image(systemName: "trash").foregroundStyle(palette.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .lifelogCard()
        .contextMenu {
            Button {
                var item = tracker
                item.archived = true
                item.active = false
                env.saveTracker(item)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }
}

struct TrackerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var draft: TrackerDefinition
    @State private var targetText: String

    init(tracker: TrackerDefinition) {
        _draft = State(initialValue: tracker)
        _targetText = State(initialValue: tracker.target.map { String($0) } ?? "")
    }

    private let icons = ["circle", "checkmark.circle", "drop", "bed.double", "figure.walk", "book", "heart", "moon", "scope"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Type", selection: $draft.type) {
                        ForEach(TrackerType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    Text(draft.type.typeDescription)
                        .font(LifelogTheme.sans(11)).foregroundStyle(.secondary)
                    TextField("Category", text: $draft.category)
                    TextField("Unit", text: $draft.unit)
                    TextField("Target (optional)", text: $targetText).keyboardType(.decimalPad)
                    Toggle("Allow multiple per day", isOn: $draft.multiplePerDay)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                draft.icon = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(width: 40, height: 40)
                                    .background(draft.icon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if env.archive.trackers.contains(where: { $0.id == draft.id }) {
                    Section {
                        Button(role: .destructive) {
                            env.deleteTracker(draft.id)
                            dismiss()
                        } label: { Label("Delete tracker and records", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        draft.target = Double(targetText.trimmingCharacters(in: .whitespacesAndNewlines))
                        env.saveTracker(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
