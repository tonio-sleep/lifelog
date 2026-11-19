import SwiftUI
import PhotosUI

private enum QuickAddMode: String, Identifiable {
    case entry, event, tracker, photo, music, place

    var id: String { rawValue }
}

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: QuickAddMode?

    private let options: [(QuickAddMode, String, String)] = [
        (.entry, "book.closed", "Journal entry"),
        (.event, "calendar.badge.plus", "Timeline event"),
        (.tracker, "checkmark.circle", "Tracker update"),
        (.photo, "photo", "Photo or video"),
        (.music, "music.note", "Track you heard"),
        (.place, "mappin", "Saved place"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Capture something now. It stays on this device unless you choose to back it up.")
                        .font(LifelogTheme.sans(13))
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(options, id: \.0) { option in
                        Button {
                            mode = option.0
                        } label: {
                            Label(option.2, systemImage: option.1)
                                .font(LifelogTheme.sans(15, weight: .medium))
                                .padding(.vertical, 5)
                        }
                    }
                }
            }
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $mode) { selected in
                switch selected {
                case .entry: EntryEditorView(entry: JournalEntry()).environmentObject(env)
                case .event: EventEditorView(event: .blank(Date())).environmentObject(env)
                case .tracker: TrackerLogView().environmentObject(env)
                case .photo: PhotoImportView().environmentObject(env)
                case .music: ManualTrackView().environmentObject(env)
                case .place: PlaceEditorView(place: Place()).environmentObject(env)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Journal entry

struct EntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var draft: JournalEntry
    @State private var tagText: String
    @State private var moodEnabled: Bool
    @State private var energyEnabled: Bool
    @State private var sleepText: String
    @State private var stepsText: String
    @State private var photoItem: PhotosPickerItem?

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
        _tagText = State(initialValue: entry.tags.joined(separator: ", "))
        _moodEnabled = State(initialValue: entry.mood != nil)
        _energyEnabled = State(initialValue: entry.energy != nil)
        _sleepText = State(initialValue: entry.sleepHours.map { String($0) } ?? "")
        _stepsText = State(initialValue: entry.steps.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The day") {
                    TextField("Title (optional)", text: $draft.title)
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(JournalEntryKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Write freely…", text: $draft.body, axis: .vertical)
                        .lineLimit(6...14)
                    TextField("Highlight", text: $draft.highlight, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("How it felt") {
                    Toggle("Record mood", isOn: $moodEnabled)
                    if moodEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(MoodScore.label(draft.mood ?? 5))
                                Spacer()
                                Text(MoodScore.shortLabel(draft.mood ?? 5))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(draft.mood ?? 5) },
                                set: { draft.mood = Int($0.rounded()) }
                            ), in: 1...10, step: 1)
                        }
                    }
                    Toggle("Record energy", isOn: $energyEnabled)
                    if energyEnabled {
                        Slider(value: Binding(
                            get: { Double(draft.energy ?? 5) },
                            set: { draft.energy = Int($0.rounded()) }
                        ), in: 1...10, step: 1)
                    }
                }

                Section("Details") {
                    TextField("Sleep hours", text: $sleepText)
                        .keyboardType(.decimalPad)
                    TextField("Steps", text: $stepsText)
                        .keyboardType(.numberPad)
                    TextField("Meals", text: $draft.meals, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Tags, separated by commas", text: $tagText)
                }

                if draft.kind == .vocab {
                    Section("Words") {
                        ForEach(draft.vocabItems.indices, id: \.self) { index in
                            HStack {
                                TextField("Term", text: $draft.vocabItems[index].term)
                                TextField("Meaning", text: $draft.vocabItems[index].meaning)
                                Button(role: .destructive) { draft.vocabItems.remove(at: index) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            draft.vocabItems.append(VocabItem())
                        } label: {
                            Label("Add word", systemImage: "plus")
                        }
                    }
                }

                Section("Attachments") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Add a photo", systemImage: "photo.badge.plus")
                    }
                    let attached = env.archive.media.filter { $0.journalEntryId == draft.id }
                    if !attached.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(attached) { item in
                                    EncryptedMediaImage(item: item)
                                        .frame(width: 78, height: 78)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                }

                if env.archive.entryById(draft.id) != nil {
                    Section {
                        Button(role: .destructive) {
                            env.deleteEntry(draft)
                            dismiss()
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(env.archive.entryById(draft.id) == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        _ = env.importMedia(data, fileName: "photo", caption: "", journalEntryId: draft.id)
                    }
                    photoItem = nil
                }
            }
        }
    }

    private func save() {
        draft.tags = normaliseTags([tagText])
        draft.mood = moodEnabled ? MoodScore.clamp(draft.mood ?? 5) : nil
        draft.energy = energyEnabled ? MoodScore.clamp(draft.energy ?? 5) : nil
        draft.sleepHours = Double(sleepText.trimmingCharacters(in: .whitespacesAndNewlines))
        draft.steps = Int(stepsText.trimmingCharacters(in: .whitespacesAndNewlines))
        draft.vocabItems.removeAll { $0.isEmpty }
        if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            draft.isEmpty {
            dismiss()
            return
        }
        env.saveEntry(draft)
        dismiss()
    }
}

// MARK: - Event

struct EventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var draft: TimelineEvent

    init(event: TimelineEvent) { _draft = State(initialValue: event) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $draft.title)
                    DatePicker("When", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                    Toggle("Hide from timeline", isOn: $draft.hidden)
                }
                if env.archive.events.contains(where: { $0.id == draft.id }) {
                    Section {
                        Button(role: .destructive) {
                            env.deleteEvent(draft.id)
                            dismiss()
                        } label: { Label("Delete event", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Timeline event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.title = "Event" }
                        env.saveEvent(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Tracker update

struct TrackerLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var trackerId: String
    @State private var valueText = ""
    @State private var note = ""

    init() {
        _trackerId = State(initialValue: envPlaceholderFirstTrackerID)
    }

    private static var envPlaceholderFirstTrackerID: String { "" }

    private var tracker: TrackerDefinition? { env.archive.trackerById(trackerId) }

    var body: some View {
        NavigationStack {
            Form {
                if env.archive.activeTrackers.isEmpty {
                    EmptyState(
                        title: "No trackers yet",
                        message: "Create a tracker in the Trackers screen first.",
                        systemImage: "checkmark.circle",
                        action: nil
                    )
                } else {
                    Section("Tracker") {
                        Picker("Tracker", selection: $trackerId) {
                            ForEach(env.archive.activeTrackers) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onAppear {
                            if trackerId.isEmpty { trackerId = env.archive.activeTrackers.first?.id ?? "" }
                        }
                    }
                    if let tracker {
                        Section("Value") {
                            switch tracker.type {
                            case .boolean:
                                HStack {
                                    Button("Yes") { save(value: 1) }
                                    Button("No") { save(value: 0) }
                                }
                            case .text, .event:
                                TextField("What did you notice?", text: $valueText, axis: .vertical)
                            default:
                                TextField(tracker.unit.isEmpty ? "Value" : tracker.unit, text: $valueText)
                                    .keyboardType(tracker.type == .rating || tracker.type == .duration ? .numberPad : .decimalPad)
                            }
                            TextField("Note (optional)", text: $note, axis: .vertical)
                        }
                    }
                }
            }
            .navigationTitle("Log update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if (tracker?.type ?? .count) != .boolean {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(value: Double(valueText)) }.fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func save(value: Double?) {
        guard let tracker else { return }
        let record = TrackerRecord(
            trackerId: tracker.id,
            recordedAt: Date(),
            value: value,
            text: [.text, .event].contains(tracker.type) ? valueText : "",
            note: note
        )
        env.saveTrackerRecord(record)
        dismiss()
    }
}

// MARK: - Photo

struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var item: PhotosPickerItem?
    @State private var caption = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                PhotosPicker(selection: $item, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 38, weight: .light))
                        Text("Choose from Photos")
                            .font(LifelogTheme.sans(15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.quaternary))
                }
                TextField("Caption (optional)", text: $caption)
                    .textFieldStyle(.roundedBorder)
                if isSaving { ProgressView() }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Add media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                isSaving = true
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        _ = env.importMedia(data, fileName: "photo", caption: caption)
                    }
                    isSaving = false
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Music

struct ManualTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var artist = ""
    @State private var title = ""
    @State private var album = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Artist", text: $artist)
                TextField("Track", text: $title)
                TextField("Album (optional)", text: $album)
            }
            .navigationTitle("Add track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.addManualTrack(artist: artist, title: title, album: album)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Place

struct PlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @State private var draft: Place
    @State private var useCurrentLocation = false

    init(place: Place) { _draft = State(initialValue: place) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...6)
                Toggle("Attach current location", isOn: $useCurrentLocation)
                if draft.latitude != nil {
                    Label("Coordinates saved", systemImage: "location.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Saved place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if useCurrentLocation {
                            Task {
                                if let sample = await env.location.captureCurrent() {
                                    draft.latitude = sample.latitude
                                    draft.longitude = sample.longitude
                                }
                                finish()
                            }
                        } else {
                            finish()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @MainActor
    private func finish() {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        env.savePlace(draft)
        dismiss()
    }
}
