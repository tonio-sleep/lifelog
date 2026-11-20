import SwiftUI
import UIKit

// MARK: - Reading

/// A journal entry as something to read, not a form.
struct EntryDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss
    let entryId: String
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let entry = env.archive.entryById(entryId) {
                content(entry)
            } else {
                ContentUnavailableView("Entry not found", systemImage: "book.closed")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
    }

    private func content(_ entry: JournalEntry) -> some View {
        let attachments = env.archive.media
            .filter { $0.journalEntryId == entry.id }
            .sorted { $0.createdAt < $1.createdAt }
        let place = env.archive.placeById(entry.placeId)?.name ?? entry.placeLabel

        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(entry, place: place)

                if !entry.highlight.isEmpty {
                    Text(entry.highlight)
                        .font(Typeface.readingLarge.italic())
                        .foregroundStyle(Palette.ink)
                        .padding(.leading, Space.md)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Palette.accent).frame(width: 2)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(Typeface.reading)
                        .lineSpacing(6)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !entry.meals.isEmpty { labelled("Meals", entry.meals) }
                numbers(entry)
                if entry.hasVocabContent { vocab(entry) }
                if !attachments.isEmpty { media(attachments) }
                if !entry.tags.isEmpty { TagLine(tags: entry.tags) }

                Text("Last edited \(Dates.formatShortDate(entry.updatedAt)) at \(Dates.formatTime(entry.updatedAt))")
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { navigator.present(.editEntry(entry.id)) }
                Menu {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) {
                env.deleteEntry(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Attached photos and recordings stay in your media library.")
        }
    }

    private func header(_ entry: JournalEntry, place: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(Dates.formatDayLong(entry.createdAt)) · \(Dates.formatTime(entry.createdAt))")
                .font(Typeface.micro)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            Text(entry.title.isEmpty ? entry.displayTitle : entry.title)
                .font(Typeface.display)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.md) {
                if let mood = entry.mood {
                    Label("\(mood)/10 · \(MoodScore.labels[mood] ?? "")", systemImage: "face.smiling")
                }
                if let energy = entry.energy {
                    Label("Energy \(energy)/5", systemImage: "bolt")
                }
            }
            .font(Typeface.caption)
            .foregroundStyle(Palette.inkSecondary)
            if let place, !place.isEmpty {
                Label(place, systemImage: "mappin")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if entry.kind != .journal {
                Text(entry.kind.label)
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private func labelled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Typeface.micro).textCase(.uppercase).tracking(1).foregroundStyle(Palette.inkTertiary)
            Text(text).font(Typeface.body).foregroundStyle(Palette.ink)
        }
    }

    @ViewBuilder
    private func numbers(_ entry: JournalEntry) -> some View {
        if entry.sleepHours != nil || entry.steps != nil {
            HStack(alignment: .top, spacing: Space.lg) {
                if let sleep = entry.sleepHours {
                    Figure(value: Dates.formatCompactNumber(sleep) + " h", label: "Sleep")
                }
                if let steps = entry.steps {
                    Figure(value: steps.formatted(), label: "Steps")
                }
            }
        }
    }

    private func vocab(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Vocabulary").font(Typeface.micro).textCase(.uppercase).tracking(1).foregroundStyle(Palette.inkTertiary)
            ForEach(Array(entry.vocabItems.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.term).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                    if !item.meaning.isEmpty {
                        Text(item.meaning).font(Typeface.label).foregroundStyle(Palette.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Hairline()
            }
        }
    }

    private func media(_ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Attachments").font(Typeface.micro).textCase(.uppercase).tracking(1).foregroundStyle(Palette.inkTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(items) { item in
                    Button { navigator.push(.mediaItem(item.id)) } label: {
                        MediaTile(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A square media thumbnail with a small badge for video and audio.
struct MediaTile: View {
    let item: MediaItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                EncryptedMediaImage(item: item, maxPixel: 300)
            )
            .overlay(alignment: .bottomLeading) {
                if item.isVideo || item.isAudio {
                    Image(systemName: item.isVideo ? "play.fill" : "waveform")
                        .font(.system(.caption2).weight(.bold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(6)
                        .background(Circle().fill(Palette.accent))
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            .accessibilityLabel(item.displayCaption)
    }
}

// MARK: - Editing

struct ScalePicker: View {
    let title: String
    let range: ClosedRange<Int>
    let columns: Int
    var labels: [Int: String] = [:]
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text(title).font(Typeface.labelStrong).foregroundStyle(Palette.ink)
                Spacer()
                if let value {
                    Text(labels[value].map { "\(value) · \($0)" } ?? "\(value)")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.inkSecondary)
                    Button("Clear") { self.value = nil }
                        .font(Typeface.caption)
                        .buttonStyle(QuietButtonStyle())
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(Array(range), id: \.self) { number in
                    Button {
                        value = (value == number) ? nil : number
                    } label: {
                        Text("\(number)")
                            .font(Typeface.labelStrong.monospacedDigit())
                            .foregroundStyle(value == number ? Palette.onAccent : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(value == number ? Palette.accent : Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(value == number ? Color.clear : Palette.line, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(number)")
                    .accessibilityAddTraits(value == number ? .isSelected : [])
                }
            }
        }
    }
}

private struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(Typeface.micro)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Palette.inkTertiary)
            content
        }
    }
}

struct EntryEditorSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var draft: JournalEntry
    @State private var sleepText: String
    @State private var stepsText: String
    @State private var tagText: String
    @State private var sessionMedia: [MediaItem] = []
    @State private var removedMedia: Set<String> = []
    @State private var initialSignature: String
    @State private var showVoice = false
    @State private var voiceAutoStart = false
    @State private var confirmDiscard = false
    @State private var healthMessage: String?
    @State private var healthBusy = false
    @State private var saveError: String?
    private let startWithVoice: Bool
    @FocusState private var bodyFocused: Bool

    init(entry: JournalEntry, startWithVoice: Bool) {
        _draft = State(initialValue: entry)
        let sleep = NumberInput.display(entry.sleepHours)
        let steps = entry.steps.map(String.init) ?? ""
        let tags = entry.tags.joined(separator: ", ")
        _sleepText = State(initialValue: sleep)
        _stepsText = State(initialValue: steps)
        _tagText = State(initialValue: tags)
        _initialSignature = State(initialValue: Self.signature(entry, sleep, steps, tags, 0, 0))
        self.startWithVoice = startWithVoice
    }

    private static func signature(_ entry: JournalEntry, _ sleep: String, _ steps: String, _ tags: String, _ added: Int, _ removed: Int) -> String {
        let vocab = entry.vocabItems.map { "\($0.term)=\($0.meaning)" }.joined(separator: ";")
        let parts: [String] = [
            entry.title, entry.body, entry.kind.rawValue,
            "\(entry.mood ?? -1)", "\(entry.energy ?? -1)",
            sleep, steps, entry.meals, entry.highlight, tags,
            entry.placeLabel ?? "", entry.placeId ?? "",
            "\(entry.createdAt.timeIntervalSince1970)", vocab,
            "\(added)", "\(removed)",
        ]
        return parts.joined(separator: "\u{1F}")
    }

    private var isDirty: Bool {
        Self.signature(draft, sleepText, stepsText, tagText, sessionMedia.count, removedMedia.count) != initialSignature
    }

    private var isExisting: Bool { env.archive.entryById(draft.id) != nil }

    private var attachments: [MediaItem] {
        env.archive.media
            .filter { $0.journalEntryId == draft.id && !removedMedia.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    writingArea
                    attachmentsArea
                    feelingArea
                    if draft.kind != .note { detailsArea }
                    bodyArea
                    placeArea
                    if draft.kind == .vocab || draft.hasVocabContent { vocabArea }
                    tagsArea
                    if isExisting { deleteArea }
                }
                .padding(Space.page)
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .paperScreen()
            .navigationTitle(isExisting ? "Edit entry" : "New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { bodyFocused = false }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { discard() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Can't save yet", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $showVoice) {
                VoiceNoteSheet(onFinish: handleVoice, autoStart: voiceAutoStart)
                    .environmentObject(env)
                    .presentationDetents([.large])
            }
            .task {
                if startWithVoice {
                    voiceAutoStart = true
                    showVoice = true
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    // MARK: Areas

    private var writingArea: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Picker("Type", selection: $draft.kind) {
                ForEach(JournalEntryKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            DatePicker("When", selection: $draft.createdAt, displayedComponents: [.date, .hourAndMinute])
                .font(Typeface.label)
                .foregroundStyle(Palette.inkSecondary)

            TextField("Title", text: $draft.title, axis: .vertical)
                .font(Typeface.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...3)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft.body)
                    .font(Typeface.reading)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .focused($bodyFocused)
                    .padding(.horizontal, -5)
                if draft.body.isEmpty {
                    Text(draft.kind == .vocab ? "Notes about this list…" : "Write freely. Nothing here is graded.")
                        .font(Typeface.reading)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var attachmentsArea: some View {
        EditorSection(title: "Voice and media") {
            HStack(spacing: 0) {
                Button {
                    voiceAutoStart = false
                    showVoice = true
                } label: {
                    Image(systemName: "mic")
                        .font(.system(.body))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Record a voice note")

                MediaSourceButtons(day: draft.createdAt, entryId: draft.id, style: .icons) { items in
                    sessionMedia.append(contentsOf: items)
                }
                Spacer()
            }
            if !attachments.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Space.sm)], spacing: Space.sm) {
                    ForEach(attachments) { item in
                        MediaTile(item: item)
                            .overlay(alignment: .topTrailing) {
                                Button { remove(item) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(.title3))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Palette.ink, Palette.paper)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove attachment")
                            }
                    }
                }
            }
        }
    }

    private var feelingArea: some View {
        EditorSection(title: "How it felt") {
            ScalePicker(title: "Mood", range: 1...10, columns: 5, labels: MoodScore.labels, value: $draft.mood)
            ScalePicker(title: "Energy", range: 1...5, columns: 5, value: $draft.energy)
        }
    }

    private var detailsArea: some View {
        EditorSection(title: "Highlight and meals") {
            TextField("Highlight of the day", text: $draft.highlight, axis: .vertical)
                .font(Typeface.body)
                .lineLimit(1...4)
                .padding(Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Meals", text: $draft.meals, axis: .vertical)
                .font(Typeface.body)
                .lineLimit(1...4)
                .padding(Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var bodyArea: some View {
        EditorSection(title: "Sleep and steps") {
            HStack(spacing: Space.md) {
                labelledField("Sleep (hours)", text: $sleepText, keyboard: .decimalPad)
                labelledField("Steps", text: $stepsText, keyboard: .numberPad)
            }
            if HealthService.isAvailable {
                Button {
                    Task { await fillFromHealth() }
                } label: {
                    Label(healthBusy ? "Reading Health…" : "Fill from Apple Health", systemImage: "heart.text.square")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(healthBusy)
            }
            if let healthMessage {
                Text(healthMessage).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func labelledField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typeface.micro).foregroundStyle(Palette.inkSecondary)
            TextField("—", text: text)
                .keyboardType(keyboard)
                .font(Typeface.body.monospacedDigit())
                .padding(Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeArea: some View {
        EditorSection(title: "Place") {
            HStack {
                TextField("Where were you?", text: Binding(
                    get: { draft.placeLabel ?? "" },
                    set: { draft.placeLabel = $0.isEmpty ? nil : $0; draft.placeId = nil }
                ))
                .font(Typeface.body)
                if !env.archive.places.isEmpty {
                    Menu {
                        ForEach(env.archive.places) { place in
                            Button(place.name) {
                                draft.placeId = place.id
                                draft.placeLabel = place.name
                            }
                        }
                        if draft.placeId != nil || draft.placeLabel != nil {
                            Divider()
                            Button("Clear place", role: .destructive) {
                                draft.placeId = nil
                                draft.placeLabel = nil
                            }
                        }
                    } label: {
                        Image(systemName: "star")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Choose a saved place")
                }
            }
            .padding(.horizontal, Space.md)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var vocabArea: some View {
        EditorSection(title: "Vocabulary") {
            ForEach(draft.vocabItems.indices, id: \.self) { index in
                VStack(spacing: Space.xs) {
                    TextField("Word or phrase", text: $draft.vocabItems[index].term)
                        .font(Typeface.bodyStrong)
                    TextField("Meaning", text: $draft.vocabItems[index].meaning)
                        .font(Typeface.label)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        draft.vocabItems.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove word")
                }
            }
            Button {
                draft.vocabItems.append(VocabItem())
            } label: {
                Label("Add a word", systemImage: "plus")
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    private var tagsArea: some View {
        EditorSection(title: "Tags") {
            TextField("travel, family, idea", text: $tagText)
                .font(Typeface.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            let tags = normaliseTags(tagText.split(separator: ",").map(String.init))
            if !tags.isEmpty { TagLine(tags: tags) }
        }
    }

    private var deleteArea: some View {
        Button(role: .destructive) {
            if let existing = env.archive.entryById(draft.id) {
                env.deleteEntry(existing)
            }
            dismiss()
        } label: {
            Label("Delete entry", systemImage: "trash")
        }
        .buttonStyle(QuietButtonStyle())
    }

    // MARK: Actions

    private func remove(_ item: MediaItem) {
        if sessionMedia.contains(where: { $0.id == item.id }) {
            // Added during this edit: nothing to preserve.
            env.deleteMedia(item)
            sessionMedia.removeAll { $0.id == item.id }
        } else {
            removedMedia.insert(item.id)
        }
    }

    private func handleVoice(_ result: VoiceNoteResult) {
        Task {
            guard let data = try? Data(contentsOf: result.url) else {
                env.present("The recording could not be read.")
                return
            }
            let transcript = result.transcript
            let item = await env.importMediaAsync(
                data,
                fileName: "voice-note.m4a",
                mimeType: "audio/mp4",
                caption: "Voice note",
                tags: transcript.isEmpty ? ["voice-note"] : ["voice-note", "transcript"],
                journalEntryId: draft.id,
                createdAt: Date()
            )
            try? FileManager.default.removeItem(at: result.url)
            guard let item else { return }
            sessionMedia.append(item)
            if !transcript.isEmpty {
                draft.body = draft.body.isEmpty ? transcript : draft.body + "\n\n" + transcript
            }
        }
    }

    private func fillFromHealth() async {
        healthBusy = true
        healthMessage = nil
        defer { healthBusy = false }
        guard await env.health.requestPermission() else {
            healthMessage = "Health access could not be requested."
            return
        }
        do {
            let summary = try await env.health.dailySummary(for: draft.createdAt)
            guard summary.hasData else {
                healthMessage = "No steps or sleep found for that day. Check Settings › Health › Data Access & Devices › Lifelog."
                return
            }
            if let sleep = summary.sleepHours { sleepText = NumberInput.display(sleep) }
            if let steps = summary.steps { stepsText = String(steps) }
            healthMessage = "Filled from Apple Health."
        } catch {
            healthMessage = "Could not read Health data."
        }
    }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { discard() }
    }

    private func discard() {
        // Anything imported during this edit belongs to an entry that will not exist.
        for item in sessionMedia { env.deleteMedia(item) }
        dismiss()
    }

    private func save() {
        var entry = draft
        entry.tags = normaliseTags(tagText.split(separator: ",").map(String.init))
        if let sleep = NumberInput.double(sleepText) {
            entry.sleepHours = min(24, max(0, sleep))
        } else {
            entry.sleepHours = nil
        }
        entry.steps = NumberInput.int(stepsText)
        entry.vocabItems = entry.vocabItems.filter { !$0.isEmpty }
        entry.draft = false

        let hasMedia = !attachments.isEmpty
        if entry.isEmpty && !hasMedia {
            saveError = "Write something, add a mood, or attach media first."
            return
        }
        for id in removedMedia {
            if let item = env.archive.media.first(where: { $0.id == id }) { env.deleteMedia(item) }
        }
        env.saveEntry(entry)
        dismiss()
    }
}

// MARK: - Moments

struct EventEditorSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TimelineEvent

    init(event: TimelineEvent) {
        _draft = State(initialValue: event)
    }

    private var isExisting: Bool { env.archive.events.contains { $0.id == draft.id } }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $draft.title)
                    DatePicker("When", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(2...6)
                }
                if isExisting {
                    Section {
                        Toggle("Hide from timeline", isOn: $draft.hidden)
                        Button("Delete moment", role: .destructive) {
                            env.deleteEvent(draft.id)
                            dismiss()
                        }
                    } footer: {
                        Text("Hidden moments stay in your archive. Use “Show hidden moments” in the timeline to see them.")
                    }
                }
            }
            .paperList()
            .navigationTitle(isExisting ? "Edit moment" : "New moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        env.saveEvent(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
