import Foundation

/// Where a prompt waits for `cadex claude --cadex-prompt-file` (plan 24,
/// docs/adr/0033-cadex-launches-agents.md): one file per session, 0600, in
/// a 0700 folder that `cadex claude` alone accepts. It reads, removes and
/// passes the text as one word of the exec; the text is never typed.
public enum PromptFiles {
    /// The system's argument limit is far above; the core refuses more too
    /// (`core/features/agent-tools/prompt_file.zig`, max_bytes).
    public static let maxBytes = 100 * 1024

    /// `…/Cadex/orchestration/prompts`, or CADEX_PROMPTS_DIR (a test
    /// instance; the `cadex` it runs reads the same variable).
    public static var folder: String {
        if let dir = ProcessInfo.processInfo.environment["CADEX_PROMPTS_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/orchestration/prompts"
    }

    public enum Refusal: Error, Equatable {
        case empty
        case tooBig(Int)
        case notWritten
    }

    /// Writes `text` under a new name in `folder`; the path, typed in the tab.
    public static func write(_ text: String, in folder: String = PromptFiles.folder) -> Result<String, Refusal> {
        let data = Data(text.utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        guard data.count <= maxBytes else { return .failure(.tooBig(data.count)) }
        // A NUL would cut the argument short: the core refuses it too.
        guard !data.contains(0) else { return .failure(.notWritten) }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(folder, 0o700)
        let path = folder + "/" + UUID().uuidString.lowercased() + ".md"
        guard fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600]) else { return .failure(.notWritten) }
        return .success(path)
    }

    /// Prompts no session took (a tab that never opened, the app closed
    /// first) are removed after a day.
    public static func prune(in folder: String = PromptFiles.folder, olderThan age: TimeInterval = 86_400, now: Date = Date()) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] {
            let path = folder + "/" + name
            if let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, now.timeIntervalSince(date) > age {
                try? fm.removeItem(atPath: path)
            }
        }
    }
}
