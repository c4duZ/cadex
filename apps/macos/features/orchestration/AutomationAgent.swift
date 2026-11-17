import Foundation

/// The LaunchAgent that wakes the app at the automations' times
/// (docs/adr/0034-scheduled-automations.md; plan 24 E): a plist in
/// ~/Library/LaunchAgents written by the app with StartCalendarInterval
/// (no KeepAlive, RunAtLoad or StartInterval), its program `cadex
/// automations due`; installed with the first automation turned on,
/// rewritten when one changes, removed with the last. A test instance
/// uses its own folder and label (CADEX_LAUNCH_AGENTS_DIR, CADEX_LAUNCH_LABEL).
public struct AutomationAgent {
    public var folder: String
    public var label: String
    /// Runs `launchctl` with these words; answers whether it went (tests: a fake).
    public var launchctl: ([String]) -> Bool = AutomationAgent.runLaunchctl

    public init(folder: String = AutomationAgent.defaultFolder, label: String = AutomationAgent.defaultLabel) {
        self.folder = folder
        self.label = label
    }

    public static var defaultFolder: String {
        if let dir = ProcessInfo.processInfo.environment["CADEX_LAUNCH_AGENTS_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents"
    }

    public static var defaultLabel: String {
        if let label = ProcessInfo.processInfo.environment["CADEX_LAUNCH_LABEL"], !label.isEmpty { return label }
        return (Bundle.main.bundleIdentifier ?? "io.github.c4duz.cadex") + ".automations"
    }

    public var path: String { folder + "/" + label + ".plist" }
    public var isInstalled: Bool { FileManager.default.fileExists(atPath: path) }

    /// The plist: the program and its words, the dates of every automation
    /// turned on (repeats dropped), and the variables the job passes on (a
    /// test instance's folders, so the app it opens is the test one).
    public func plist(cadex: String, dates: [[String: Int]], environment: [String: String]) -> [String: Any] {
        var seen: Set<String> = []
        let unique = dates.filter { seen.insert($0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")).inserted }
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cadex, "automations", "due"],
            "StartCalendarInterval": unique,
            "ProcessType": "Background",
        ]
        if !environment.isEmpty { plist["EnvironmentVariables"] = environment }
        return plist
    }

    /// Writes the plist and (re)loads it, or removes it with no date.
    /// Returns what went wrong, nil when it went.
    @discardableResult
    public func sync(cadex: String?, dates: [[String: Int]], environment: [String: String]) -> String? {
        guard !dates.isEmpty else { return remove() }
        guard let cadex else { return "the cadex program is missing from the app" }
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: plist(cadex: cadex, dates: dates, environment: environment), format: .xml, options: 0)
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return "\(error)"
        }
        // Reloading is how launchd reads a changed plist; bootout of one not
        // loaded fails, and that is fine.
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        return launchctl(["bootstrap", "gui/\(getuid())", path]) ? nil : "launchctl did not load \(path)"
    }

    /// Unloads and deletes the plist; nothing when there is none.
    @discardableResult
    public func remove() -> String? {
        guard isInstalled else { return nil }
        _ = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        do { try FileManager.default.removeItem(atPath: path) } catch { return "\(error)" }
        return nil
    }

    public static func runLaunchctl(_ words: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = words
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
