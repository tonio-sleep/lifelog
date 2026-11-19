import Foundation
import CryptoKit

/// Salted Argon2id PIN hash, byte-for-byte compatible with Flutter's `PinHasher`.
enum PinHasher {
    static func create(_ pin: String) -> (salt: String, hash: String) {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = CryptoService.deriveBackupKey(passphrase: pin, salt: salt)
        return (salt.base64EncodedString(), key.base64EncodedString())
    }

    static func verify(pin: String, salt: String, hash: String) -> Bool {
        guard let saltData = Data(base64Encoded: salt),
              let expected = Data(base64Encoded: hash) else { return false }
        let candidate = CryptoService.deriveBackupKey(passphrase: pin, salt: saltData)
        return candidate.withUnsafeBytes { candidateBytes in
            expected.withUnsafeBytes { expectedBytes in
                constantTimeEquals(Array(candidateBytes), Array(expectedBytes))
            }
        }
    }
}

private extension SymmetricKey {
    func base64EncodedString() -> String {
        withUnsafeBytes { Data($0).base64EncodedString() }
    }
}
