import Foundation

/// The first launch of a new version runs the engine once in the
/// background (`cadex-memory --warm`): the store's migrations and macOS's
/// first-run check of the new binary are paid then, not inside the first
/// SessionStart's 1 s (plan 22, phase C). Once per version, kept in
/// UserDefaults; `make run` is version "0", warmed once too.
@MainActor
public enum MemoryWarmUp {
    public static let versionKey = "memory.warmedVersion"
    /// The run in progress, kept alive until it ends; a second call waits for it.
    private static var running: Process?

    public static func isNeeded(version: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: versionKey) != version
    }

    /// Starts the warm-up unless this version had one or one is running.
    /// `done` (on the main thread) says whether it worked; the version is
    /// kept only then, so a failure tries again at the next launch.
    @discardableResult
    public static func start(engine: String, folder: String, version: String, defaults: UserDefaults = .standard,
                             done: (@MainActor (Bool) -> Void)? = nil) -> Bool {
        guard running == nil, isNeeded(version: version, defaults: defaults) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: engine)
        process.arguments = ["--warm", "--data-dir", folder]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        nonisolated(unsafe) let store = defaults
        process.terminationHandler = { ended in
            let ok = ended.terminationReason == .exit && ended.terminationStatus == 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if ok { store.set(version, forKey: versionKey) }
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
