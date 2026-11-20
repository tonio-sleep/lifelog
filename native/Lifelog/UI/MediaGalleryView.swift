import SwiftUI
import AVKit
import AVFoundation
import UIKit

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Gallery

private enum MediaFilter: String, CaseIterable, Identifiable {
    case all, photos, videos, audio, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .audio: return "Voice & audio"
        case .favorites: return "Favorites"
        }
    }
}

struct MediaGalleryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @State private var filter: MediaFilter = .all

    var body: some View {
        let items = filtered()
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(MediaFilter.allCases) { option in
                        Button(option.title) { filter = option }
                            .buttonStyle(ChipStyle(selected: filter == option))
                            .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Space.page)
            }
            Hairline()
            ScrollView {
                if items.isEmpty {
                    EmptyNote(
                        title: "Nothing here",
                        message: filter == .all
                            ? "Photos, videos, and voice notes you add are encrypted and kept here."
                            : "No media matches this filter.",
                        actionTitle: filter == .all ? "Add media" : nil
                    ) { navigator.present(.addMedia(Date())) }
                    .padding(Space.page)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                        ForEach(items) { item in
                            Button { navigator.push(.mediaItem(item.id)) } label: {
                                MediaTile(item: item)
                                    .overlay(alignment: .topTrailing) {
                                        if item.favorite {
                                            Image(systemName: "heart.fill")
                                                .font(.system(.caption))
                                                .foregroundStyle(Palette.onAccent)
                                                .padding(5)
                                                .background(Circle().fill(Palette.accent))
                                                .padding(5)
                                                .accessibilityLabel("Favorite")
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    Text("\(items.count) \(Dates.plural(items.count, "item"))")
                        .font(Typeface.micro)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.vertical, Space.lg)
                }
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigator.present(.addMedia(Date())) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add media")
            }
        }
        .paperScreen()
    }

    private func filtered() -> [MediaItem] {
        let all = env.archive.media.sorted { $0.createdAt > $1.createdAt }
        switch filter {
        case .all: return all
        case .photos: return all.filter { $0.isImage }
        case .videos: return all.filter { $0.isVideo }
        case .audio: return all.filter { $0.isAudio }
        case .favorites: return all.filter { $0.favorite }
        }
    }
}

// MARK: - Detail

struct MediaDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.dismiss) private var dismiss
    let itemId: String

    @State private var caption = ""
    @State private var captionLoaded = false
    @State private var playbackURL: URL?
    @State private var player: AVPlayer?
    @State private var loadFailed = false
    @State private var confirmDelete = false
    @State private var shareItem: IdentifiableURL?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1

    var body: some View {
        Group {
            if let item = env.archive.media.first(where: { $0.id == itemId }) {
                content(item)
            } else {
                ContentUnavailableView("Item not found", systemImage: "photo")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .paperScreen()
        .onDisappear { teardown() }
    }

    private func content(_ item: MediaItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                viewer(item)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Caption").font(Typeface.micro).textCase(.uppercase).tracking(1).foregroundStyle(Palette.inkTertiary)
                    TextField("Add a caption", text: $caption, axis: .vertical)
                        .font(Typeface.reading)
                        .lineLimit(1...5)
                        .onSubmit { commitCaption(item) }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    detailRow("Added", Dates.formatDayLong(item.createdAt) + " · " + Dates.formatTime(item.createdAt))
                    detailRow("Type", item.kindLabel)
                    detailRow("Size", ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))
                    if !item.tags.isEmpty { TagLine(tags: item.tags) }
                }

                if let entryId = item.journalEntryId, env.archive.entryById(entryId) != nil {
                    Button { navigator.push(.entry(entryId)) } label: {
                        Label("Open the entry this belongs to", systemImage: "book.closed")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(Space.page)
            .padding(.bottom, Space.xxl)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    env.toggleMediaFavorite(item)
                } label: {
                    Image(systemName: item.favorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(item.favorite ? "Remove from favorites" : "Add to favorites")
                Menu {
                    Button { Task { await prepareShare(item) } } label: {
                        Label("Share a decrypted copy", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                teardown()
                env.deleteMedia(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The encrypted file is removed from this device.")
        }
        .sheet(item: $shareItem) { shared in
            ShareSheet(items: [shared.url]) {
                try? FileManager.default.removeItem(at: shared.url)
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: item.id) {
            if !captionLoaded {
                caption = item.caption
                captionLoaded = true
            }
            await preparePlayback(item)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.inkTertiary)
            Spacer()
            Text(value).font(Typeface.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func viewer(_ item: MediaItem) -> some View {
        if item.isImage {
            EncryptedMediaImage(item: item, fullSize: true, fit: true)
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .scaleEffect(zoom)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in zoom = min(4, max(1, baseZoom * value.magnification)) }
                        .onEnded { _ in baseZoom = zoom }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) { zoom = 1; baseZoom = 1 }
                }
                .accessibilityLabel(item.displayCaption)
                .accessibilityHint("Pinch to zoom, double tap to reset")
        } else if item.isVideo || item.isAudio {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.surface)
                if let player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if loadFailed {
                    InfoLine(text: "This file could not be opened.", symbol: "exclamationmark.triangle")
                        .padding()
                } else {
                    ProgressView("Decrypting…")
                        .font(Typeface.caption)
                }
            }
            .frame(height: item.isVideo ? 260 : 110)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        } else {
            HStack(spacing: Space.md) {
                Image(systemName: "doc").font(.system(.title)).foregroundStyle(Palette.inkTertiary)
                Text(item.displayCaption).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        }
    }

    // MARK: Actions

    private func commitCaption(_ item: MediaItem) {
        guard captionLoaded else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.caption else { return }
        var updated = item
        updated.caption = trimmed
        env.updateMedia(updated)
    }

    private func decryptedCopy(_ item: MediaItem) async -> URL? {
        let store = env.mediaStore
        let media = item
        return await offMain { () -> URL? in
            guard let data = try? store.readOriginal(media) else { return nil }
            let ext = URL(fileURLWithPath: media.originalName ?? "").pathExtension
            let fallback = media.isVideo ? "mov" : (media.isAudio ? "m4a" : "dat")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lifelog-play-\(media.id).\(ext.isEmpty ? fallback : ext)")
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                return url
            } catch {
                return nil
            }
        }
    }

    private func preparePlayback(_ item: MediaItem) async {
        guard item.isVideo || item.isAudio, player == nil else { return }
        guard let url = await decryptedCopy(item) else {
            loadFailed = true
            return
        }
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        playbackURL = url
        player = AVPlayer(url: url)
    }

    private func prepareShare(_ item: MediaItem) async {
        if let url = await decryptedCopy(item) {
            shareItem = IdentifiableURL(url: url)
        } else {
            env.present("Could not prepare the file to share.")
        }
    }

    private func teardown() {
        if let current = env.archive.media.first(where: { $0.id == itemId }) {
            commitCaption(current)
        }
        player?.pause()
        player = nil
        if let url = playbackURL {
            try? FileManager.default.removeItem(at: url)
            playbackURL = nil
        }
    }
}
