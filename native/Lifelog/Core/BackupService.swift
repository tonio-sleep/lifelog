import Foundation

struct BackupMediaFile {
    let id: String
    let original: Data
    let thumbnail: Data?
}

struct BackupContents {
    let archive: Archive
    let createdAt: Date
    let includesMedia: Bool
    let mediaFiles: [BackupMediaFile]

    var counts: [String: Int] {
        [
            "journalEntries": archive.entries.count,
            "photos": archive.media.count,
            "trackers": archive.trackers.count,
            "trackerRecords": archive.trackerRecords.count,
            "timelineEvents": archive.events.count,
            "places": archive.places.count,
            "visits": archive.visits.count,
            "scrobbles": archive.scrobbles.count,
        ]
    }
}

enum BackupService {
    static let format = "lifelog-backup"
    static let version = 2

    static func create(
        archive: Archive,
        passphrase: String,
        mediaStore: MediaStore? = nil
    ) throws -> Data {
        guard passphrase.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else {
            throw LifelogError.passphraseTooShort
        }

        let salt = CryptoService.newSalt()
        let crypto = CryptoService(key: CryptoService.deriveBackupKey(passphrase: passphrase, salt: salt))
        var encodedMedia: [[String: Any]] = []

        if let mediaStore {
            for item in archive.media {
                guard let original = try? mediaStore.readOriginal(item) else { continue }
                let thumbnail = mediaStore.readThumbnailDataIfExists(item)
                encodedMedia.append([
                    "id": item.id,
                    "original": original.base64EncodedString(),
                    "thumb": thumbnail?.base64EncodedString() ?? NSNull(),
                ])
            }
        }

        let archiveData = try JSONEncoder.lifelog.encode(archive)
        let archiveJSON = try JSONSerialization.jsonObject(with: archiveData)
        let payload: [String: Any] = [
            "format": "lifelog-archive",
            "version": 2,
            "createdAt": DateCodec.utcString(Date()),
            "includesMedia": !encodedMedia.isEmpty,
            "archive": archiveJSON,
            "mediaFiles": encodedMedia,
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let encrypted = try crypto.encrypt(payloadData, aad: AAD.backupV2)

        let container: [String: Any] = [
            "format": format,
            "version": version,
            "createdAt": DateCodec.utcString(Date()),
            "includesMedia": !encodedMedia.isEmpty,
            "cipher": "aes-256-gcm",
            "kdf": [
                "name": "argon2id",
                "memory": 19456,
                "iterations": 2,
                "parallelism": 1,
                "salt": salt.base64EncodedString(),
            ],
            "payload": encrypted.base64EncodedString(),
        ]
        let pretty = try JSONSerialization.data(withJSONObject: container, options: [.prettyPrinted, .sortedKeys])
        return pretty
    }

    static func read(data: Data, passphrase: String) throws -> BackupContents {
        do {
            guard let raw = try? JSONSerialization.jsonObject(with: data),
                  let container = raw as? [String: Any],
                  container["format"] as? String == format else {
                throw LifelogError.corruptBackup("This file is not a Lifelog backup.")
            }
            let containerVersion = (container["version"] as? NSNumber)?.intValue ?? 0
            guard containerVersion == 1 || containerVersion == 2 else {
                throw LifelogError.corruptBackup("This backup uses an unsupported format version.")
            }
            guard let kdf = container["kdf"] as? [String: Any],
                  kdf["name"] as? String == "argon2id",
                  let saltString = kdf["salt"] as? String,
                  let salt = Data(base64Encoded: saltString),
                  let payloadString = container["payload"] as? String,
                  let encrypted = Data(base64Encoded: payloadString) else {
                throw LifelogError.corruptBackup("The backup key derivation settings are missing.")
            }
            let memory = (kdf["memory"] as? NSNumber)?.intValue ?? 19456
            let iterations = (kdf["iterations"] as? NSNumber)?.intValue ?? 2
            let parallelism = (kdf["parallelism"] as? NSNumber)?.intValue ?? 1
            guard (8...1_048_576).contains(memory),
                  (1...100).contains(iterations),
                  (1...16).contains(parallelism),
                  (8...1_048_576).contains(salt.count) else {
                throw LifelogError.corruptBackup("This backup uses unsupported key derivation settings.")
            }
            let crypto = CryptoService(key: CryptoService.deriveBackupKey(
                passphrase: passphrase,
                salt: salt,
                memoryKiB: memory,
                iterations: iterations,
                parallelism: parallelism
            ))
            let clear = try crypto.decrypt(
                encrypted,
                aad: containerVersion == 1 ? AAD.backupV1 : AAD.backupV2
            )
            guard let payloadRaw = try? JSONSerialization.jsonObject(with: clear),
                  let payload = payloadRaw as? [String: Any],
                  let archiveJSON = payload["archive"] as? [String: Any] else {
                throw LifelogError.corruptBackup("The backup does not contain an archive.")
            }
            let archiveData = try JSONSerialization.data(withJSONObject: archiveJSON)
            let archive = try JSONDecoder.lifelog.decode(Archive.self, from: archiveData)

            var mediaFiles: [BackupMediaFile] = []
            if let rawMedia = payload["mediaFiles"] as? [[String: Any]] {
                for entry in rawMedia {
                    guard let id = entry["id"] as? String, !id.isEmpty,
                          let originalString = entry["original"] as? String,
                          let original = Data(base64Encoded: originalString) else { continue }
                    let thumbnailString = entry["thumb"] as? String
                    let thumbnail = thumbnailString.flatMap { Data(base64Encoded: $0) }
                    mediaFiles.append(BackupMediaFile(id: id, original: original, thumbnail: thumbnail))
                }
            }

            return BackupContents(
                archive: archive,
                createdAt: DateCodec.parse(payload["createdAt"] as? String) ?? Date(),
                includesMedia: (payload["includesMedia"] as? Bool ?? false) || !mediaFiles.isEmpty,
                mediaFiles: mediaFiles
            )
        } catch let error as LifelogError {
            throw error
        } catch {
            throw LifelogError.corruptBackup("The backup could not be decrypted. Check the passphrase and file.")
        }
    }
}
