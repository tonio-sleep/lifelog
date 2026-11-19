import SwiftUI
import PhotosUI

struct MediaGalleryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var onlyFavorites = false
    @State private var selected: MediaItem?
    @State private var showImport = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    private var items: [MediaItem] {
        let base = env.archive.media.filter { !onlyFavorites || $0.favorite }
        return base.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Encrypted vault")
                    Text("Media")
                        .font(LifelogTheme.serif(29, relativeTo: .largeTitle))
                    Text("Originals are encrypted on this device. Backups carry them only when you choose.")
                        .font(LifelogTheme.sans(12)).foregroundStyle(palette.secondary)
                }
                HStack {
                    Toggle("Favorites only", isOn: $onlyFavorites)
                        .font(LifelogTheme.sans(13))
                    Spacer()
                    Button("Add") { showImport = true }
                }
                if items.isEmpty {
                    EmptyState(title: "No media yet", message: "Photos and videos you add are stored as encrypted files.", systemImage: "photo", action: { showImport = true }, actionTitle: "Add media")
                        .lifelogCard()
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            Button { selected = item } label: {
                                ZStack(alignment: .topTrailing) {
                                    EncryptedMediaImage(item: item)
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    if item.favorite {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.35)))
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Media")
        .sheet(isPresented: $showImport) { PhotoImportView().environmentObject(env) }
        .sheet(item: $selected) { item in MediaDetailView(item: item).environmentObject(env) }
    }
}

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    let item: MediaItem
    @State private var caption: String

    init(item: MediaItem) {
        self.item = item
        _caption = State(initialValue: item.caption)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    EncryptedMediaImage(item: item, thumbnail: false, contentMode: .fit)
                        .frame(maxHeight: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Caption", text: $caption, axis: .vertical)
                            .font(LifelogTheme.sans(15))
                        Text("\(item.kindLabel) · \(Dates.formatDayLong(item.createdAt)) · \(item.bytes / 1024) KB")
                            .font(LifelogTheme.sans(11)).foregroundStyle(palette.secondary)
                        if !item.tags.isEmpty {
                            HStack { ForEach(item.tags, id: \.self) { TagPill(text: $0) } }
                        }
                    }
                    .lifelogCard()
                }
                .padding(20)
            }
            .navigationTitle("Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            var updated = item
                            updated.caption = caption
                            archiveUpdate(updated)
                        } label: { Image(systemName: "checkmark") }
                        Button {
                            env.toggleMediaFavorite(item)
                            dismiss()
                        } label: { Image(systemName: item.favorite ? "heart.fill" : "heart") }
                        Button(role: .destructive) {
                            env.deleteMedia(item)
                            dismiss()
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
    }

    private func archiveUpdate(_ updated: MediaItem) {
        env.archive = env.archive.puttingMedia(updated)
        env.save()
    }
}
