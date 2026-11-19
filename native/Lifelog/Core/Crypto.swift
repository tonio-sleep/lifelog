import Foundation
import CryptoKit
import Security

enum LifelogError: LocalizedError {
    case archiveUnreadable
    case mediaUnavailable(String)
    case mediaTooLarge
    case invalidEnvelope
    case passphraseTooShort
    case corruptBackup(String)
    case keychainUnavailable

    var errorDescription: String? {
        switch self {
        case .archiveUnreadable:
            return "The encrypted archive could not be opened. It may have been written with a different key, or the file may be damaged."
        case .mediaUnavailable(let id):
            return "The encrypted media file for \(id) is not available."
        case .mediaTooLarge:
            return "This file is too large to attach."
        case .invalidEnvelope:
            return "The encrypted data is damaged."
        case .passphraseTooShort:
            return "Use a backup passphrase of at least 8 characters."
        case .corruptBackup(let message):
            return message
        case .keychainUnavailable:
            return "Secure storage is unavailable on this device."
        }
    }
}

enum AAD {
    static let archive = Data("lifelog-archive-v1".utf8)
    static let media = Data("lifelog-media-v1".utf8)
    static let mediaThumbnail = Data("lifelog-media-thumb-v1".utf8)
    static let backupV1 = Data("lifelog-backup-v1".utf8)
    static let backupV2 = Data("lifelog-backup-v2".utf8)
    static let lastfmKey = Data("lifelog-lastfm-key-v1".utf8)
    static let cloudflareSession = Data("lifelog-cloudflare-session-v1".utf8)
}

/// AES-256-GCM with the envelope layout nonce(12) || ciphertext || tag(16).
/// Identical to the `cryptography` package format used by the Flutter app.
struct CryptoService {
    let key: SymmetricKey

    func encrypt(_ clear: Data, aad: Data = Data()) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(clear, using: key, nonce: nonce, authenticating: aad)
        var envelope = Data()
        envelope.append(contentsOf: nonce.withUnsafeBytes { Array($0) })
        envelope.append(box.ciphertext)
        envelope.append(box.tag)
        return envelope
    }

    func decrypt(_ envelope: Data, aad: Data = Data()) throws -> Data {
        guard envelope.count >= 28 else { throw LifelogError.invalidEnvelope }
        let nonce = try AES.GCM.Nonce(data: Data(envelope.prefix(12)))
        let ciphertext = envelope.subdata(in: 12..<(envelope.count - 16))
        let tag = Data(envelope.suffix(16))
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }

    func encryptString(_ clear: String, aad: Data = Data()) throws -> String {
        try encrypt(Data(clear.utf8), aad: aad).base64EncodedString()
    }

    func decryptString(_ encoded: String, aad: Data = Data()) throws -> String {
        guard let data = Data(base64Encoded: encoded) else { throw LifelogError.invalidEnvelope }
        return String(decoding: try decrypt(data, aad: aad), as: UTF8.self)
    }

    static func deriveBackupKey(
        passphrase: String,
        salt: Data,
        memoryKiB: Int = 19456,
        iterations: Int = 2,
        parallelism: Int = 1
    ) -> SymmetricKey {
        SymmetricKey(data: Argon2id.hash(
            password: Array(passphrase.utf8),
            salt: Array(salt),
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism
        ))
    }

    static func newSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }
}

/// Keychain-backed master key with a documented file fallback, matching Flutter's KeyVault.
enum KeyVault {
    static let secureKeyName = "lifelog.master_key.v1"
    static let legacyService = "lifelog"
    static let fallbackFileName = "master.key"

    /// flutter_secure_storage currently defaults to `flutter_secure_storage_service`
    /// on iOS. New keys are written there and to the bundle identifier so either
    /// reader can find them; reads also check the legacy `lifelog` service.
    static var primaryService: String { "flutter_secure_storage_service" }

    static var bundleService: String {
        Bundle.main.bundleIdentifier ?? "com.logginglife.lifelog"
    }

    private static var readableServices: [String] {
        var seen = Set<String>()
        return [primaryService, bundleService, legacyService]
            .filter { seen.insert($0).inserted }
    }

    private static var writableServices: [String] {
        var seen = Set<String>()
        return [primaryService, bundleService].filter { seen.insert($0).inserted }
    }

    private static func writeSecureAll(_ encoded: String) -> Bool {
        var wrote = false
        for service in writableServices {
            if writeSecure(encoded, service: service) { wrote = true }
        }
        return wrote
    }

    static func loadOrCreate(in directory: URL) throws -> (key: SymmetricKey, usedFallback: Bool) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let stored = readSecure(), stored.data.count == 32 {
            if stored.service != primaryService {
                _ = writeSecureAll(stored.data.base64EncodedString())
            }
            return (SymmetricKey(data: stored.data), false)
        }
        let fallbackURL = directory.appendingPathComponent(fallbackFileName)
        if let data = try? Data(contentsOf: fallbackURL),
           let encoded = String(data: data, encoding: .utf8),
           let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
           decoded.count == 32 {
            return (SymmetricKey(data: decoded), true)
        }

        var random = [UInt8](repeating: 0, count: 32)
        for i in 0..<random.count { random[i] = UInt8.random(in: 0...255) }
        let bytes = Data(random)
        let encoded = bytes.base64EncodedString()
        if writeSecureAll(encoded), let verify = readSecure(), verify.data == bytes {
            return (SymmetricKey(data: bytes), false)
        }
        try Data(encoded.utf8).write(to: fallbackURL, options: [.atomic])
        return (SymmetricKey(data: bytes), true)
    }

    private static func baseQuery(service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secureKeyName,
        ]
    }

    private static func readSecure() -> (data: Data, service: String)? {
        for service in readableServices {
            var query = baseQuery(service: service)
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let encoded = String(data: data, encoding: .utf8),
                  let decoded = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
                  decoded.count == 32 else {
                continue
            }
            return (decoded, service)
        }
        return nil
    }

    private static func writeSecure(_ encoded: String, service: String) -> Bool {
        let existing = baseQuery(service: service)
        let attributes: [CFString: Any] = [
            kSecValueData: Data(encoded.utf8),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd((existing.merging(attributes) { _, new in new }) as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            return SecItemUpdate(existing as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        return false
    }
}

// MARK: - Constant-time comparison (PIN verification)

func constantTimeEquals(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
    var diff = lhs.count ^ rhs.count
    for i in 0..<max(lhs.count, rhs.count) {
        let left = i < lhs.count ? Int(lhs[i]) : 0
        let right = i < rhs.count ? Int(rhs[i]) : 0
        diff |= left ^ right
    }
    return diff == 0
}
