import Checks
import CryptoKit
import Foundation
@testable import Updates

// Tests of the updates feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let key = Curve25519.Signing.PrivateKey()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
let bundleID = "io.github.c4duz.cadex.test"

func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-updates-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

/// A tiny signed Cadex.app of `version` in `folder`: /usr/bin/true as the
/// executable, so codesign has something to sign.
func makeApp(in folder: URL, version: String) async throws -> URL {
    let app = folder.appendingPathComponent("Cadex.app")
    let macos = app.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
    try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macos.appendingPathComponent("Cadex").path)
    let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                               "CFBundleExecutable": "Cadex", "CFBundlePackageType": "APPL"]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
    try await UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
    return app
}

/// A zip of a new Cadex.app and the latest.json for it, signed with `key`.
func makeRelease(version: String, in folder: URL) async throws -> UpdateRelease {
    let build = folder.appendingPathComponent("build")
    let app = try await makeApp(in: build, version: version)
    let zip = folder.appendingPathComponent("Cadex.zip")
    try await UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    let data = try Data(contentsOf: zip)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let signature = try key.signature(for: data).base64EncodedString()
    let json = """
    {"version": "\(version)", "notes": "Novidades", "url": "\(zip.absoluteString)",
     "sha256": "\(digest)", "signature": "\(signature)"}
    """
    return try JSONDecoder().decode(UpdateRelease.self, from: Data(json.utf8))
}

func installedVersion(_ app: URL) -> String? {
    NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
}

let exitCode = await Checks.run([
    ("versions compare number by number", {
        expect(UpdateVersion.isNewer("1.10.0", than: "1.9.2"))
        expect(UpdateVersion.isNewer("v1.3.0", than: "1.2.0"))
        expect(UpdateVersion.isNewer("1.2.1", than: "1.2"))
        expect(!UpdateVersion.isNewer("1.2.0", than: "1.2.0"))
        expect(!UpdateVersion.isNewer("1.2.0-beta", than: "1.2.0"))
        expect(!UpdateVersion.isNewer("1.1.9", than: "1.2.0"))
    }),
    ("the signature and the checksum must both match", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let release = try await makeRelease(version: "2.0.0", in: folder)
        let zip = try Data(contentsOf: release.url)
        expect(UpdateVerifier(publicKey: publicKey).verify(zip, against: release))
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        expect(!UpdateVerifier(publicKey: other).verify(zip, against: release), "another key")
        expect(!UpdateVerifier(publicKey: publicKey).verify(zip + Data([0]), against: release), "a changed zip")
    }),
    ("installs over the app and keeps its place", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try await makeApp(in: folder.appendingPathComponent("Applications"), version: "1.0.0")
        let release = try await makeRelease(version: "2.0.0", in: folder)
        let installer = UpdateInstaller(app: installed, bundleID: bundleID, verifier: UpdateVerifier(publicKey: publicKey))
        try await installer.install(release) { _, _ in }
        expect(installedVersion(installed) == "2.0.0", "got \(installedVersion(installed) ?? "nothing")")
    }),
    ("a zip signed by someone else changes nothing", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try await makeApp(in: folder.appendingPathComponent("Applications"), version: "1.0.0")
        let release = try await makeRelease(version: "2.0.0", in: folder)
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let installer = UpdateInstaller(app: installed, bundleID: bundleID, verifier: UpdateVerifier(publicKey: stranger))
        var refused = false
        do { try await installer.install(release) { _, _ in } } catch UpdateError.notVerified { refused = true }
        expect(refused && installedVersion(installed) == "1.0.0")
    }),
    ("a zip of another version changes nothing", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let installed = try await makeApp(in: folder.appendingPathComponent("Applications"), version: "1.0.0")
        let built = try await makeRelease(version: "2.0.0", in: folder)
        let release = UpdateRelease(version: "3.0.0", notes: "", url: built.url, sha256: built.sha256, signature: built.signature)
        let installer = UpdateInstaller(app: installed, bundleID: bundleID, verifier: UpdateVerifier(publicKey: publicKey))
        var refused = false
        do { try await installer.install(release) { _, _ in } } catch UpdateError.wrongBundle { refused = true }
        expect(refused && installedVersion(installed) == "1.0.0")
    }),
    ("a translocated app does not try", {
        let installer = UpdateInstaller(app: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Cadex.app"), bundleID: bundleID)
        guard case .translocated = installer.blocker() else { return expect(false, "not refused") }
    }),
    ("a check finds a newer version, then none", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let feed = folder.appendingPathComponent("latest.json")
        try Data(#"{"version":"1.3.0","notes":"","url":"https://example.com/Cadex.zip","sha256":"","signature":""}"#.utf8).write(to: feed)
        let newer = UpdateController(currentVersion: "1.2.0", feed: feed, installer: nil)
        newer.prompt = {}
        await newer.check(manual: false)
        expect(newer.pendingVersion == "1.3.0" && newer.showsButton)
        let same = UpdateController(currentVersion: "1.3.0", feed: feed, installer: nil)
        await same.check(manual: true)
        expect(same.state == .upToDate && !same.showsButton)
    }),
    ("a found version opens the panel once per run; skipped, it stays quiet", {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let feed = folder.appendingPathComponent("latest.json")
        try Data(#"{"version":"1.3.0","notes":"","url":"https://example.com/Cadex.zip","sha256":"","signature":""}"#.utf8).write(to: feed)
        let suite = "cadex-updates-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var prompts = 0
        let updates = UpdateController(currentVersion: "1.2.0", feed: feed, installer: nil, defaults: defaults)
        updates.prompt = { prompts += 1 }
        await updates.check(manual: false)
        await updates.check(manual: false)
        expect(prompts == 1 && updates.showsButton, "\(prompts) prompts")
        updates.skip()
        expect(!updates.showsButton && updates.skippedVersion == "1.3.0")
        // The next launch: still quiet for 1.3.0, but a manual check offers it.
        let next = UpdateController(currentVersion: "1.2.0", feed: feed, installer: nil, defaults: defaults)
        next.prompt = { prompts += 1 }
        await next.check(manual: false)
        expect(prompts == 1 && !next.showsButton)
        await next.check(manual: true)
        expect(next.pendingVersion == "1.3.0" && prompts == 1)
        // A newer version than the skipped one speaks up again.
        try Data(#"{"version":"1.4.0","notes":"","url":"https://example.com/Cadex.zip","sha256":"","signature":""}"#.utf8).write(to: feed)
        let later = UpdateController(currentVersion: "1.2.0", feed: feed, installer: nil, defaults: defaults)
        later.prompt = { prompts += 1 }
        await later.check(manual: false)
        expect(prompts == 2 && later.pendingVersion == "1.4.0")
    }),
    ("an automatic check that fails keeps quiet; a manual one says why", {
        let missing = URL(fileURLWithPath: "/nonexistent/latest.json")
        let quiet = UpdateController(currentVersion: "1.2.0", feed: missing, installer: nil)
        await quiet.check(manual: false)
        expect(quiet.state == .idle)
        await quiet.check(manual: true)
        guard case .failed = quiet.state else { return expect(false, "no failure shown") }
    }),
])
exit(exitCode)
