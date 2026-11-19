import Foundation
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

enum Paths {
    static let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("lifelog", isDirectory: true)
    }()

    static let media: URL = root.appendingPathComponent("media", isDirectory: true)
    static let settings: URL = root.appendingPathComponent("settings.json")
    static let backups: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Backups", isDirectory: true)
    }()

    static func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
    }
}

private func writeProtected(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic])
    try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
    )
}

// MARK: - Archive document

struct ArchiveStore {
    static let fileName = "archive.lifelog"

    static var file: URL { Paths.root.appendingPathComponent(fileName) }

    static func load(crypto: CryptoService) throws -> Archive? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let envelope = try Data(contentsOf: file)
            let clear = try crypto.decrypt(envelope, aad: AAD.archive)
            return try JSONDecoder.lifelog.decode(Archive.self, from: clear)
        } catch {
            throw LifelogError.archiveUnreadable
        }
    }

    static func save(_ archive: Archive, crypto: CryptoService) throws {
        let clear = try JSONEncoder.lifelog.encode(archive)
        try writeProtected(try crypto.encrypt(clear, aad: AAD.archive), to: file)
    }

    static func delete() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}

// MARK: - Encrypted media vault

struct MediaStore {
    static let maxBytes = 250 * 1024 * 1024
    private static let cache = NSCache<NSString, NSData>()

    static func clearCache() { cache.removeAllObjects() }

    let directory: URL
    let crypto: CryptoService

    private func originalURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).bin") }
    private func thumbnailURL(_ id: String) -> URL { directory.appendingPathComponent("\(id).thumb.bin") }

    static func mimeTypeForFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    @discardableResult
    func importBytes(
        _ bytes: Data,
        fileName: String,
        mimeType suppliedMime: String? = nil,
        caption: String = "",
        tags: [String] = [],
        journalEntryId: String? = nil,
        createdAt: Date? = nil
    ) throws -> MediaItem {
        guard bytes.count <= Self.maxBytes else { throw LifelogError.mediaTooLarge }
        let type = suppliedMime ?? Self.mimeTypeForFileName(fileName)
        let id = UUID().uuidString.lowercased()
        try writeProtected(crypto.encrypt(bytes, aad: AAD.media), to: originalURL(id))

        var hasThumbnail = false
        var width: Int?
        var height: Int?
        if type.hasPrefix("image/"), bytes.count < 60 * 1024 * 1024,
           let thumbnail = Self.makeThumbnail(bytes),
           let source = CGImageSourceCreateWithData(bytes as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
            height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
            try writeProtected(crypto.encrypt(thumbnail, aad: AAD.mediaThumbnail), to: thumbnailURL(id))
            hasThumbnail = true
        }

        return MediaItem(
            id: id, createdAt: createdAt ?? Date(), mimeType: type, bytes: bytes.count,
            caption: caption, tags: tags, journalEntryId: journalEntryId,
            hasThumbnail: hasThumbnail, width: width, height: height, originalName: fileName
        )
    }

    func readOriginal(_ item: MediaItem) throws -> Data {
        let key = "full:\(item.id)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached as Data }
        guard let envelope = try? Data(contentsOf: originalURL(item.id)) else {
            throw LifelogError.mediaUnavailable(item.id)
        }
        let clear = try crypto.decrypt(envelope, aad: AAD.media)
        Self.cache.setObject(clear as NSData, forKey: key)
        return clear
    }

    func readThumbnail(_ item: MediaItem) throws -> Data {
        let key = "thumb:\(item.id)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached as Data }
        if item.hasThumbnail, let envelope = try? Data(contentsOf: thumbnailURL(item.id)) {
            let clear = try crypto.decrypt(envelope, aad: AAD.mediaThumbnail)
            Self.cache.setObject(clear as NSData, forKey: key)
            return clear
        }
        return try readOriginal(item)
    }

    func readThumbnailDataIfExists(_ item: MediaItem) -> Data? {
        guard item.hasThumbnail, let envelope = try? Data(contentsOf: thumbnailURL(item.id)) else { return nil }
        return try? crypto.decrypt(envelope, aad: AAD.mediaThumbnail)
    }

    func readEncryptedOriginal(_ item: MediaItem) -> Data? {
        try? Data(contentsOf: originalURL(item.id))
    }

    func writeRestoredItem(_ item: MediaItem, original: Data, thumbnail: Data?) throws {
        try writeProtected(crypto.encrypt(original, aad: AAD.media), to: originalURL(item.id))
        Self.cache.removeObject(forKey: "full:\(item.id)" as NSString)
        Self.cache.removeObject(forKey: "thumb:\(item.id)" as NSString)
        let thumbURL = thumbnailURL(item.id)
        if let thumbnail {
            try writeProtected(crypto.encrypt(thumbnail, aad: AAD.mediaThumbnail), to: thumbURL)
        } else {
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }

    func delete(_ item: MediaItem) {
        Self.cache.removeObject(forKey: "full:\(item.id)" as NSString)
        Self.cache.removeObject(forKey: "thumb:\(item.id)" as NSString)
        try? FileManager.default.removeItem(at: originalURL(item.id))
        try? FileManager.default.removeItem(at: thumbnailURL(item.id))
    }

    func deleteAll() {
        Self.cache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func makeThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0 else { return nil }
        let targetWidth = min(image.width, 900)
        let targetHeight = max(1, Int(CGFloat(image.height) * CGFloat(targetWidth) / CGFloat(image.width)))
        guard let context = CGContext(
            data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8,
            bytesPerRow: 0, space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resized = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, resized,
                                   [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - Settings document

struct SettingsStore {
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: Paths.settings),
              let settings = try? JSONDecoder.lifelog.decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    static func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder.lifelog.encode(settings)
        try writeProtected(data, to: Paths.settings)
    }
}
