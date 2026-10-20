import Foundation
import Strings

/// Why an update did not install. Nothing in the installed app changes
/// before the last step, so every one of these leaves it as it was.
enum UpdateError: LocalizedError {
    case server(Int)
    case notVerified
    case wrongBundle
    case translocated
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .server(let status):
            T("GitHub answered with error \(status).", "O GitHub respondeu com erro \(status).")
        case .notVerified:
            T("The downloaded update does not check out and was not installed.",
              "A atualização baixada não confere e não foi instalada.")
        case .wrongBundle:
            T("The downloaded file is not the expected Cadex version.",
              "O arquivo baixado não é a versão esperada do Cadex.")
        case .translocated:
            T("Cadex is running from the disk image or Downloads. Move it to Applications, open it from there and update again.",
              "O Cadex está rodando da imagem de disco ou de Downloads. Mova para Aplicativos, abra de lá e atualize de novo.")
        case .notWritable(let folder):
            T("Cadex cannot write to \(folder). Move it to Applications or update with install.sh.",
              "O Cadex não pode escrever em \(folder). Mova para Aplicativos ou atualize com o install.sh.")
        }
    }
}

/// Downloads a release, checks it and puts it in place of the running app
/// (docs/adr/0016-in-app-updates.md). The old bundle stays readable for
/// the running process until it quits, which is what the app does next.
struct UpdateInstaller: Sendable {
    /// The installed Cadex.app this replaces.
    let app: URL
    let bundleID: String
    var verifier = UpdateVerifier()

    /// Why this app cannot replace itself, before anything is downloaded.
    func blocker() -> UpdateError? {
        // macOS runs a quarantined app opened from Downloads or a disk image
        // from a read-only random path (App Translocation).
        if app.path.contains("/AppTranslocation/") { return .translocated }
        let folder = app.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: folder.path) { return .notWritable(folder.path) }
        return nil
    }

    func install(_ release: UpdateRelease, progress: @escaping UpdateDownload.Progress) async throws {
        if let blocker = blocker() { throw blocker }
        // On the app's volume, so the swap is a rename.
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: app, create: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let zip = work.appendingPathComponent("Cadex.zip")
        try await UpdateDownload.fetch(release.url, to: zip, progress: progress)
        let fresh = try await unpack(zip, release: release, in: work)
        _ = try FileManager.default.replaceItemAt(app, withItemAt: fresh)
    }

    /// The checked Cadex.app out of the zip, ready to move.
    private func unpack(_ zip: URL, release: UpdateRelease, in work: URL) async throws -> URL {
        guard let data = try? Data(contentsOf: zip), verifier.verify(data, against: release) else {
            throw UpdateError.notVerified
        }
        let folder = work.appendingPathComponent("unpacked")
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let fresh = folder.appendingPathComponent(app.lastPathComponent)
        let info = Bundle(url: fresh)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == bundleID,
              info?["CFBundleShortVersionString"] as? String == release.version
        else { throw UpdateError.wrongBundle }
        // The app downloaded it, so there should be no quarantine; a copy
        // made some other way could carry it (install.sh does the same).
        try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", fresh.path])
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path])
        } catch {
            throw UpdateError.wrongBundle
        }
        return fresh
    }

    struct ToolFailed: Error {
        let tool: String
        let status: Int32
    }

    /// A system tool, off the main thread; fails on a non-zero exit.
    static func run(_ tool: String, _ arguments: [String]) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { throw ToolFailed(tool: tool, status: process.terminationStatus) }
        }.value
    }
}
