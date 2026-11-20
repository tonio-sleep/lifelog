import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import UIKit

struct PickedMedia {
    var data: Data
    var fileName: String
    var mimeType: String
}

// MARK: - Loading

/// A movie handed over by the photo picker as a temporary file.
private struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("lifelog-import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return MovieFile(url: copy)
        }
    }
}

enum MediaLoader {
    /// Detects the real image type from the bytes, so photos are stored as images
    /// (with thumbnails) instead of an anonymous binary file.
    static func imageInfo(_ data: Data) -> (mime: String, ext: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return nil }
        return (type.preferredMIMEType ?? "image/jpeg", type.preferredFilenameExtension ?? "jpg")
    }

    static func load(_ item: PhotosPickerItem) async -> PickedMedia? {
        let isMovie = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isMovie {
            guard let movie = try? await item.loadTransferable(type: MovieFile.self) else { return nil }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return loadFile(movie.url, scoped: false)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let info = imageInfo(data)
        return PickedMedia(
            data: data,
            fileName: "photo." + (info?.ext ?? "jpg"),
            mimeType: info?.mime ?? "image/jpeg"
        )
    }

    static func load(fileURL: URL) async -> PickedMedia? {
        loadFile(fileURL, scoped: true)
    }

    static func load(capture: CaptureResult) async -> PickedMedia? {
        switch capture {
        case .photo(let data):
            return PickedMedia(data: data, fileName: "photo.jpg", mimeType: "image/jpeg")
        case .video(let url):
            defer { try? FileManager.default.removeItem(at: url) }
            return loadFile(url, scoped: false)
        case .cancelled:
            return nil
        }
    }

    private static func loadFile(_ url: URL, scoped: Bool) -> PickedMedia? {
        let opened = scoped && url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        var mime = type?.preferredMIMEType ?? "application/octet-stream"
        if mime == "application/octet-stream", let info = imageInfo(data) { mime = info.mime }
        let name = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        return PickedMedia(data: data, fileName: name, mimeType: mime)
    }
}

// MARK: - Camera

enum CaptureResult {
    case photo(Data)
    case video(URL)
    case cancelled
}

struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (CaptureResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (CaptureResult) -> Void

        init(onFinish: @escaping (CaptureResult) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                onFinish(.video(url))
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.92) {
                onFinish(.photo(data))
            } else {
                onFinish(.cancelled)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(.cancelled)
        }
    }
}

// MARK: - Sources

enum MediaSourceStyle {
    case rows
    case icons
}

/// Photo library, camera and Files, each asking for permission only when used.
/// The photo library needs none: the system picker shows only what is chosen.
struct MediaSourceButtons: View {
    @EnvironmentObject private var env: AppEnvironment

    let day: Date
    var entryId: String?
    var style: MediaSourceStyle = .rows
    var onImported: ([MediaItem]) -> Void

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var showCameraDenied = false
    @State private var working = false

    private var layout: AnyLayout {
        switch style {
        case .rows: return AnyLayout(VStackLayout(alignment: .leading, spacing: Space.sm))
        case .icons: return AnyLayout(HStackLayout(spacing: 0))
        }
    }

    var body: some View {
        layout {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 20,
                matching: .any(of: [.images, .videos])
            ) {
                tile("photo.on.rectangle", "Photo library", "Choose photos or videos")
            }
            .disabled(working)

            Button(action: cameraTapped) {
                tile("camera", "Take photo or video", "Uses the camera only when you do")
            }
            .buttonStyle(.plain)
            .disabled(working)

            Button { showFiles = true } label: {
                tile("folder", "Files", "Images, video, audio, PDF")
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            let chosen = items
            pickerItems = []
            Task {
                var picks: [PickedMedia] = []
                for item in chosen {
                    if let pick = await MediaLoader.load(item) { picks.append(pick) }
                }
                await finish(picks, requested: chosen.count)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { result in
                showCamera = false
                Task {
                    if let pick = await MediaLoader.load(capture: result) {
                        await finish([pick], requested: 1)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.image, .movie, .audio, .pdf, .plainText],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            Task {
                var picks: [PickedMedia] = []
                for url in urls {
                    if let pick = await MediaLoader.load(fileURL: url) { picks.append(pick) }
                }
                await finish(picks, requested: urls.count)
            }
        }
        .alert("Camera access is off", isPresented: $showCameraDenied) {
            Button("Open Settings") { PermissionCenter.openSystemSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Allow the camera in Settings to take photos and videos inside Lifelog. You can still add from your library.")
        }
    }

    @ViewBuilder
    private func tile(_ symbol: String, _ title: String, _ detail: String) -> some View {
        switch style {
        case .rows:
            HStack(spacing: Space.md) {
                Image(systemName: symbol)
                    .font(.system(.body))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                    Text(detail).font(Typeface.caption).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        case .icons:
            Image(systemName: symbol)
                .font(.system(.body))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
        }
    }

    private func cameraTapped() {
        Task {
            guard env.permissions.cameraHardwareAvailable else {
                env.present("The camera is not available on this device.")
                return
            }
            await env.permissions.refresh()
            if await env.permissions.requestCamera() {
                showCamera = true
            } else {
                showCameraDenied = true
            }
        }
    }

    private func finish(_ picks: [PickedMedia], requested: Int) async {
        working = true
        defer { working = false }
        var imported: [MediaItem] = []
        let created = day.momentForDay
        for pick in picks {
            if let item = await env.importMediaAsync(
                pick.data,
                fileName: pick.fileName,
                mimeType: pick.mimeType,
                journalEntryId: entryId,
                createdAt: created
            ) {
                imported.append(item)
            }
        }
        if imported.count < requested, !imported.isEmpty {
            env.present("Added \(imported.count) of \(requested). Some files could not be read.")
        } else if imported.isEmpty, requested > 0 {
            env.present("Nothing could be added. The file may be unreadable or larger than 250 MB.")
        }
        onImported(imported)
    }
}

// MARK: - Sheet

/// Adds media to a day, outside of any entry.
struct MediaAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    MediaSourceButtons(day: day, style: .rows) { items in
                        if !items.isEmpty { dismiss() }
                    }
                    .surface()
                    InfoLine(
                        text: "Media is encrypted on this device. Photo locations are not read or stored.",
                        symbol: "lock"
                    )
                }
                .padding(Space.page)
            }
            .paperScreen()
            .navigationTitle("Add media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
