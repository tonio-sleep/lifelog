import SwiftUI

/// The single "add something" sheet. Each row opens the right editor in place.
struct QuickAddSheet: View {
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss

    private struct Option: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let sheet: AppSheet
    }

    private var options: [Option] {
        let now = Date()
        return [
            Option(id: "entry", symbol: "square.and.pencil", title: "Journal entry",
                   detail: "Write about your day, with mood and tags.", sheet: .newEntry(now, startWithVoice: false)),
            Option(id: "voice", symbol: "mic", title: "Voice note",
                   detail: "Record, and turn it into text on this device.", sheet: .newEntry(now, startWithVoice: true)),
            Option(id: "media", symbol: "photo.on.rectangle", title: "Photo or video",
                   detail: "From your library, the camera, or Files.", sheet: .addMedia(now)),
            Option(id: "moment", symbol: "sparkle", title: "Moment",
                   detail: "Something that happened at a particular time.", sheet: .newEvent(now)),
            Option(id: "practice", symbol: "checkmark.circle", title: "Practice",
                   detail: "Log water, a walk, a reading, anything you track.", sheet: .logTracker(nil)),
            Option(id: "track", symbol: "music.note", title: "Track you heard",
                   detail: "Add a song that Last.fm missed.", sheet: .addTrack),
            Option(id: "place", symbol: "mappin.and.ellipse", title: "Place",
                   detail: "Save somewhere that matters to you.", sheet: .newPlace),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        Button { navigator.present(option.sheet) } label: {
                            HStack(spacing: Space.md) {
                                Image(systemName: option.symbol)
                                    .font(.system(.title3))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 36)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                                    Text(option.detail)
                                        .font(Typeface.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, Space.md)
                        }
                        .buttonStyle(RowButtonStyle())
                        if option.id != options.last?.id { Hairline() }
                    }
                }
                .padding(.horizontal, Space.page)
            }
            .paperScreen()
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Adds a song by hand, optionally at a particular time.
struct ManualTrackSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var artist = ""
    @State private var title = ""
    @State private var album = ""
    @State private var playedAt = Date()

    private var canSave: Bool {
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist", text: $artist)
                    TextField("Track", text: $title)
                    TextField("Album (optional)", text: $album)
                    DatePicker("Heard", selection: $playedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
            }
            .paperList()
            .navigationTitle("Add a track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let track = MusicScrobble.manual(
                            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
                            playedAt: playedAt
                        )
                        _ = env.importScrobbles([track])
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
