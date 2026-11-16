import Foundation

/// The first launch of a new version runs the engine once in the
/// background (`cadex-memory --warm`): the store's migrations and macOS's
/// first-run check of the new binary are paid then, not inside the first
/// SessionStart's 1 s (plan 22, phase C). Once per version, kept in a file
/// inside the memory folder (`warmed-version`), not in UserDefaults: a test
/// instance with its own CADEX_MEMORY_DIR shared the real app's defaults and
/// warmed the owner's real folder (make perf, 2026-11-16). `make run` is
/// version "0", warmed once too.
@MainActor
public enum MemoryWarmUp {
    public nonisolated static let versionFile = "warmed-version"
    /// The run in progress, kept alive until it ends; a second call waits for it.
    private static var running: Process?

    public static func isNeeded(version: String, folder: String) -> Bool {
        let stamp = try? String(contentsOfFile: folder + "/" + versionFile, encoding: .utf8)
        return stamp?.trimmingCharacters(in: .whitespacesAndNewlines) != version
    }

    /// Starts the warm-up unless this version had one or one is running.
    /// `done` (on the main thread) says whether it worked; the version is
    /// kept only then, so a failure tries again at the next launch.
    @discardableResult
    public static func start(engine: String, folder: String, version: String,
                             done: (@MainActor (Bool) -> Void)? = nil) -> Bool {
        guard running == nil, isNeeded(version: version, folder: folder) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: engine)
        process.arguments = ["--warm", "--data-dir", folder]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        process.terminationHandler = { ended in
            let ok = ended.terminationReason == .exit && ended.terminationStatus == 0
            if ok { try? (version + "\n").write(toFile: folder + "/" + versionFile, atomically: true, encoding: .utf8) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    running = nil
                    done?(ok)
                }
            }
        }
        do { try process.run() } catch { return false }
        running = process
        return true
    }
}
