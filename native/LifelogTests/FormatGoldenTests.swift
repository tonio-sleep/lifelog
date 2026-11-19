import Foundation
import CryptoKit
import XCTest
@testable import Lifelog

final class FormatGoldenTests: XCTestCase {
    func testDartDateCodecRoundTripIncludesMicrosecondsWhenNeeded() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .current
        components.year = 2026
        components.month = 3
        components.day = 8
        components.hour = 9
        components.minute = 7
        components.second = 5
        components.nanosecond = 123_456_000
        let date = calendar.date(from: components)!

        XCTAssertEqual(DateCodec.string(date), "2026-03-08T09:07:05.123456")

        let parsed = DateCodec.parse("2026-03-08T09:07:05.123456")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.000_001)

        let utc = DateCodec.utcString(date)
        XCTAssertTrue(utc.hasSuffix("Z"))
        XCTAssertTrue(utc.contains(".123456"))
    }

    func testArgon2idGoldenVectorMatchesFlutterParameters() {
        let password = Array("correct horse battery staple".utf8)
        let salt = (0..<16).map { UInt8($0) }
        let digest = Argon2id.hash(
            password: password,
            salt: salt,
            memoryKiB: 19456,
            iterations: 2,
            parallelism: 1,
            outputLength: 32
        )
        let hex = Data(digest).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "818259b6310026a8e0dbac5d2e6927abcfdb07b32258fac4f61b18b80f929085")
    }

    func testCryptoEnvelopeLayoutAndAAD() throws {
        let crypto = CryptoService(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
        let clear = Data("lifelog".utf8)
        let aad = AAD.archive
        let envelope = try crypto.encrypt(clear, aad: aad)

        XCTAssertEqual(envelope.count, 12 + clear.count + 16)
        XCTAssertEqual(try crypto.decrypt(envelope, aad: aad), clear)
        XCTAssertThrowsError(try crypto.decrypt(envelope, aad: AAD.media))
    }

    func testArchiveJSONKeepsFlutterTopLevelSchema() throws {
        let data = try JSONEncoder.lifelog.encode(Archive.empty)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "lifelog-archive")
        XCTAssertEqual(json["version"] as? Int, 1)
        for key in ["savedAt", "entries", "media", "trackers", "trackerRecords",
                    "events", "places", "visits", "scrobbles", "locationSamples"] {
            XCTAssertNotNil(json[key], "Missing archive key: \(key)")
        }
    }

    func testBackupContainerRoundTripsWithVersionTwo() throws {
        let passphrase = "correct horse battery staple"
        let bytes = try BackupService.create(archive: .empty, passphrase: passphrase)
        let container = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(container["format"] as? String, "lifelog-backup")
        XCTAssertEqual(container["version"] as? Int, 2)
        XCTAssertEqual(container["cipher"] as? String, "aes-256-gcm")

        let contents = try BackupService.read(data: bytes, passphrase: passphrase)
        XCTAssertTrue(contents.archive.entries.isEmpty)
        XCTAssertFalse(contents.includesMedia)
    }

    func testPinHasherVerifyRejectsWrongPin() {
        let pin = "2468"
        let hash = PinHasher.create(pin)
        XCTAssertTrue(PinHasher.verify(pin: pin, salt: hash.salt, hash: hash.hash))
        XCTAssertFalse(PinHasher.verify(pin: "2469", salt: hash.salt, hash: hash.hash))
        XCTAssertEqual(Data(base64Encoded: hash.hash)?.count, 32)
    }
}
