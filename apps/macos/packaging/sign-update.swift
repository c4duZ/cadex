// Signs a release for the in-app updater (docs/adr/0016-in-app-updates.md):
// an Ed25519 signature of Cadex.zip, which the app checks with the public key
// in features/updates/UpdateVerifier.swift before replacing itself.
//
//   swift sign-update.swift keygen
//       prints a new private and public key (base64); the private one goes
//       to the Keychain, the public one into UpdateVerifier.swift.
//   security find-generic-password -s cadex-update-signing -a cadex -w | \
//       swift sign-update.swift manifest <Cadex.zip> <version> <zip url> <notes>
//       prints latest.json: the version, the notes, the zip's address,
//       SHA-256 and signature. The private key comes on stdin, so it never
//       shows in the process list.
import CryptoKit
import Foundation

struct Manifest: Encodable {
    let version: String
    let notes: String
    let url: String
    let sha256: String
    let signature: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign-update: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    let key = Curve25519.Signing.PrivateKey()
    print("private: \(key.rawRepresentation.base64EncodedString())")
    print("public:  \(key.publicKey.rawRepresentation.base64EncodedString())")
case "manifest":
    let rest = Array(args.dropFirst())
    guard rest.count == 4 else { fail("manifest <zip> <version> <url> <notes>") }
    let encoded = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("a entrada não tem uma chave privada válida") }
    guard let zip = FileManager.default.contents(atPath: rest[0]) else { fail("não li \(rest[0])") }
    let digest = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
    guard let signature = try? key.signature(for: zip) else { fail("não consegui assinar") }
    let manifest = Manifest(version: rest[1], notes: rest[3], url: rest[2], sha256: digest,
                            signature: signature.base64EncodedString())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try! encoder.encode(manifest), as: UTF8.self))
default:
    fail("uso: sign-update.swift keygen | manifest <zip> <version> <url> <notes>")
}
