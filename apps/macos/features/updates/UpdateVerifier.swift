import CryptoKit
import Foundation

/// Checks a downloaded zip against latest.json before anything is replaced
/// (docs/adr/0016-in-app-updates.md): the SHA-256 catches a broken
/// download, the signature a file someone else put in the release.
struct UpdateVerifier {
    /// The public half of the Keychain item "cadex-update-signing" on the
    /// Mac that publishes, made by `swift packaging/sign-update.swift keygen`
    /// on 2026-10-20. A new key here leaves older versions unable to update.
    static let releaseKey = "AxyjmmnzlQBrj7naj16EFNgKZDRSZK/QdJ7zdcQ7R/g="

    let publicKey: String

    init(publicKey: String = Self.releaseKey) {
        self.publicKey = publicKey
    }

    func verify(_ zip: Data, against release: UpdateRelease) -> Bool {
        let digest = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256.lowercased(),
              let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let signature = Data(base64Encoded: release.signature)
        else { return false }
        return key.isValidSignature(signature, for: zip)
    }
}
