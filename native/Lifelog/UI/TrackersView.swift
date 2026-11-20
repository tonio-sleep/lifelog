import SwiftUI
import Charts

private let trackerIcons: [String] = [
    "drop", "figure.walk", "book", "bed.double", "pills", "fork.knife",
    "dumbbell", "brain.head.profile", "leaf", "heart", "cup.and.saucer", "moon",
    "sun.max", "figure.run", "bicycle", "music.note", "pencil", "camera",
    "phone", "cart", "house", "star", "flame", "face.smiling",
]

private let trackerColors: [UInt32] = [
    0xFF6B8F71, 0xFF9A4733, 0xFF3D6A8F, 0xFF92692A, 0xFF7A4E8F, 0xFF8F4A5C, 0xFF52796F, 0xFF5B6B7A,
]

// MARK: - List

private struct TrackerRowData: Identifiable {
    var id: String
    var tracker: TrackerDefinition
    var label: String?
    var done: Bool
    var recent: [Bool]
}

struct TrackersView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var rows: [TrackerRowData] = []
    @State private var archived: [TrackerDefinition] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader(
                    eyebrow: "Practices",
                    title: "What you track",
                    subtitle: "Nothing is scored. Log when it is useful to you."
                )

                if loaded && rows.isEmpty {
                    EmptyNote(
                        title: "No practices yet",
                        message: "A practice can be a yes/no, a count, a number, a duration, a rating, or a short note.",
                        actionTitle: "Create a practice"
                    ) { navigator.present(.newTracker) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button { navigator.push(.tracker(row.id)) } label: {
                                TrackerRowView(row: row)
                            }
                            .buttonStyle(RowButtonStyle())
                            if row.id != rows.last?.id { Hairline() }
                        }
                    }
                }

                if !archived.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel(title: "Archived")
                        ForEach(archived) { tracker in
                            Button { navigator.present(.editTracker(tracker.id)) } label: {
                                HStack {
                                    Text(tracker.name).font(Typeface.label).foregroundStyle(Palette.inkSecondary)
                                    Spacer()
                                    Text("Restore or edit").font(Typeface.caption).foregroundStyle(Palette.inkTertiary)
                                }
                                .padding(.vertical, Space.sm)
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigator.present(.newTracker) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New practice")
            }
        }
        .paperScreen()
        .task(id: env.revision) {
            let archive = env.archive
            let now = Date()
            let result: ([TrackerRowData], [TrackerDefinition]) = await offMain {
                let records = archive.trackerRecords
                let rows = archive.activeTrackers.map { tracker -> TrackerRowData in
                    let history = HabitHistory(tracker, records)
                    return TrackerRowData(
                        id: tracker.id,
                        tracker: tracker,
                        label: TrackerMath.dailyLabel(tracker, records, now),
                        done: history.doneOn(now),
                        recent: history.lastDays(now, count: 14)
                    )
                }
                return (rows, archive.trackers.filter { $0.archived })
            }
            guard !Task.isCancelled else { return }
            rows = result.0
            archived = result.1
            loaded = true
        }
    }
}

private struct TrackerRowView: View {
    let row: TrackerRowData

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: row.tracker.icon.isEmpty ? "circle" : row.tracker.icon)
                .font(.system(.title3))
                .foregroundStyle(Color(hex: row.tracker.colorValue))
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.tracker.name).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                Text(row.label.map { "Today: \($0)" } ?? "Not logged today")
                    .font(Typeface.caption)
                    .foregroundStyle(row.done ? Palette.moss : Palette.inkSecondary)
                HStack(spacing: 3) {
                    ForEach(Array(row.recent.enumerated()), id: \.offset) { _, on in
                        Circle()
                            .fill(on ? Color(hex: row.tracker.colorValue) : Palette.line)
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

struct TrackerDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    let trackerId: String

    var body: some View {
        Group {
            if let tracker = env.archive.trackerById(trackerId) {
                content(tracker)
            } else {
                ContentUnavailableView("Practice not found", systemImage: "checkmark.circle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
    }

    private func content(_ tracker: TrackerDefinition) -> some View {
        let records = env.archive.recordsForTracker(tracker.id).sorted { $0.recordedAt > $1.recordedAt }
        let series = TrackerMath.dailySeries(tracker, env.archive.trackerRecords, endDay: Date(), days: 30)
            .map { DayValue(day: $0.day, value: $0.value) }
        let daysLogged = series.filter { $0.value > 0 }.count

        return List {
            Section {
                VStack(alignment: .leading, spacing: Space.md) {
                    PageHeader(
                        eyebrow: tracker.type.label,
                        title: tracker.name,
                        subtitle: tracker.targetLabel.isEmpty ? tracker.type.typeDescription : tracker.targetLabel
                    )
                    Button { navigator.present(.logTracker(tracker.id)) } label: {
                        Label("Log \(tracker.name)", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Chart(series) { point in
                        BarMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(Color(hex: tracker.colorValue))
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                    }
                    .frame(height: 120)
                    .accessibilityLabel("Last 30 days")
                    .accessibilityValue("Logged on \(daysLogged) of 30 days")

                    Text("Logged on \(daysLogged) of the last 30 days · \(records.count) \(Dates.plural(records.count, "entry", "entries")) in total")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                if records.isEmpty {
                    EmptyNote(title: "Nothing logged", message: "Entries you add appear here, newest first.")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(records.prefix(60)) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TrackerMath.recordLabel(tracker, record))
                                .font(Typeface.bodyStrong)
                                .foregroundStyle(Palette.ink)
                            Text(Dates.formatShortDate(record.recordedAt) + " · " + Dates.formatTime(record.recordedAt))
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.inkSecondary)
                            if !record.note.isEmpty {
                                Text(record.note).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Palette.line)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                env.deleteTrackerRecord(record.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("History").font(Typeface.heading).foregroundStyle(Palette.ink).textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { navigator.present(.editTracker(tracker.id)) }
            }
        }
    }
}

// MARK: - Logging

struct TrackerLogSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: String
    @State private var yes = true
    @State private var amount = 1
    @State private var numberText = ""
    @State private var minutesText = ""
    @State private var rating: Int?
    @State private var text = ""
    @State private var note = ""
    @State private var when = Date()
    @State private var error: String?

    init(trackerId: String?) {
        _selectedId = State(initialValue: trackerId ?? "")
    }

    private var trackers: [TrackerDefinition] { env.archive.activeTrackers }

    private var tracker: TrackerDefinition? {
        env.archive.trackerById(selectedId) ?? (selectedId.isEmpty ? trackers.first : nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if trackers.isEmpty {
                    VStack(spacing: Space.lg) {
                        EmptyNote(
                            title: "No practices yet",
                            message: "Create one first, then you can log it here.",
                            actionTitle: "Create a practice"
                        ) { navigator.present(.newTracker) }
                    }
                    .padding(Space.page)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else if let tracker {
                    form(tracker)
                }
            }
            .paperScreen()
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(tracker == nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func form(_ tracker: TrackerDefinition) -> some View {
        Form {
            if trackers.count > 1 {
                Section {
                    Picker("Practice", selection: Binding(
                        get: { tracker.id },
                        set: { selectedId = $0 }
                    )) {
                        ForEach(trackers) { item in Text(item.name).tag(item.id) }
                    }
                }
            }
            Section {
                input(for: tracker)
            } header: {
                Text(tracker.name)
            } footer: {
                if !tracker.multiplePerDay {
                    Text("This practice keeps one entry per day, so saving replaces today's.")
                }
            }
            Section {
                DatePicker("When", selection: $when, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
            }
            if let error {
                Section { Text(error).foregroundStyle(Palette.danger).font(Typeface.caption) }
            }
        }
        .paperList()
    }

    @ViewBuilder
    private func input(for tracker: TrackerDefinition) -> some View {
        switch tracker.type {
        case .boolean:
            Picker("Did you?", selection: $yes) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .pickerStyle(.segmented)
        case .count, .event:
            Stepper("Amount: \(amount)", value: $amount, in: 1...999)
        case .number:
            HStack {
                TextField("Value", text: $numberText).keyboardType(.decimalPad)
                if !tracker.unit.isEmpty { Text(tracker.unit).foregroundStyle(Palette.inkSecondary) }
            }
        case .duration:
            HStack {
                TextField("Minutes", text: $minutesText).keyboardType(.decimalPad)
                Text("min").foregroundStyle(Palette.inkSecondary)
            }
            HStack(spacing: Space.sm) {
                ForEach([10, 15, 30, 45, 60], id: \.self) { value in
                    Button("\(value)") { minutesText = String(value) }
                        .buttonStyle(ChipStyle(selected: minutesText == String(value)))
                }
            }
        case .rating:
            ScalePicker(title: "Rating", range: 1...5, columns: 5, value: $rating)
        case .text:
            TextField("What did you notice?", text: $text, axis: .vertical).lineLimit(2...6)
        }
    }

    private func save() {
        guard let tracker else { return }
        error = nil
        var record = TrackerRecord(trackerId: tracker.id, recordedAt: when, note: note.trimmingCharacters(in: .whitespacesAndNewlines))

        switch tracker.type {
        case .boolean:
            record.value = yes ? 1 : 0
        case .count, .event:
            record.value = Double(amount)
        case .number:
            guard let value = NumberInput.double(numberText) else {
                error = "Enter a number."
                return
            }
            record.value = value
        case .duration:
            guard let minutes = NumberInput.double(minutesText), minutes > 0 else {
                error = "Enter the minutes spent."
                return
            }
            record.value = minutes
        case .rating:
            guard let rating else {
                error = "Choose a rating from 1 to 5."
                return
            }
            record.value = Double(rating)
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                error = "Write a short note."
                return
            }
            record.text = trimmed
        }

        if !tracker.multiplePerDay,
           let existing = TrackerMath.recordsOn(env.archive.trackerRecords, trackerId: tracker.id, day: when).last {
            record.id = existing.id
        }
        env.saveTrackerRecord(record)
        env.present("Logged \(tracker.name).")
        dismiss()
    }
}

// MARK: - Editing

struct TrackerEditorSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrackerDefinition
    @State private var targetText: String
    @State private var confirmDelete = false

    init(tracker: TrackerDefinition) {
        _draft = State(initialValue: tracker)
        _targetText = State(initialValue: NumberInput.display(tracker.target))
    }

    private var isExisting: Bool { env.archive.trackerById(draft.id) != nil }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var supportsTarget: Bool { [.count, .number, .duration, .rating].contains(draft.type) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Type", selection: $draft.type) {
                        ForEach(TrackerType.allCases, id: \.self) { type in Text(type.label).tag(type) }
                    }
                    TextField("Category", text: $draft.category)
                } footer: {
                    Text(draft.type.typeDescription)
                }

                if draft.type == .number {
                    Section("Unit") { TextField("For example: glasses, km, kg", text: $draft.unit) }
                }
                if supportsTarget {
                    Section {
                        TextField("Daily target (optional)", text: $targetText).keyboardType(.decimalPad)
                    } footer: {
                        Text("A target is only a reference line. Missing it is never recorded as a failure.")
                    }
                }
                if draft.type != .boolean {
                    Section {
                        Toggle("Allow several entries per day", isOn: $draft.multiplePerDay)
                    }
                }

                Section("Icon") { iconGrid }
                Section("Color") { colorRow }

                if isExisting {
                    Section {
                        Button(draft.archived ? "Restore practice" : "Archive practice") {
                            draft.archived.toggle()
                            draft.active = !draft.archived
                            persist()
                        }
                        Button("Delete practice and its history", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .paperList()
            .navigationTitle(isExisting ? "Edit practice" : "New practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { persist() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this practice?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete practice", role: .destructive) {
                    env.deleteTracker(draft.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its history is deleted too. This cannot be undone.")
            }
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(trackerIcons, id: \.self) { icon in
                Button { draft.icon = icon } label: {
                    Image(systemName: icon)
                        .font(.system(.body))
                        .foregroundStyle(draft.icon == icon ? Palette.onAccent : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(draft.icon == icon ? Palette.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(draft.icon == icon ? .isSelected : [])
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: Space.sm) {
            ForEach(trackerColors, id: \.self) { value in
                Button { draft.colorValue = value } label: {
                    Circle()
                        .fill(Color(hex: value))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: draft.colorValue == value ? 2 : 0).padding(-3))
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
                .accessibilityAddTraits(draft.colorValue == value ? .isSelected : [])
            }
        }
    }

    private func persist() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.target = supportsTarget ? NumberInput.double(targetText) : nil
        if draft.type == .boolean { draft.multiplePerDay = false }
        env.saveTracker(draft)
        dismiss()
    }
}
