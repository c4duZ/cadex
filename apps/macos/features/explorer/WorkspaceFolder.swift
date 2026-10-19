import AppKit
import CCadex

/// The folder open in the window: the root of the explorer and of the
/// search (docs/spec/workspace.md). Every folder that becomes the root is
/// authorized in the core first; the core refuses file operations outside
/// the authorized ones.
@MainActor
public final class WorkspaceFolder {
    /// Canonical path of the current root.
    public private(set) var root: String
    /// Called after the root changes, with the new root.
    public var onChange: ((String) -> Void)?

    /// Starts at the folder the app was opened with, or the home folder.
    public init(arguments: [String] = CommandLine.arguments,
                cwd: String = FileManager.default.currentDirectoryPath) {
        let start = Self.launchDirectory(arguments: arguments, cwd: cwd) ?? NSHomeDirectory()
        root = Self.authorize(start) ?? start
    }

    /// Makes `path` the root. False (and no change) when it is not an
    /// existing folder.
    @discardableResult
    public func open(_ path: String) -> Bool {
        guard let real = Self.authorize(path) else { return false }
        if real != root {
            root = real
            onChange?(real)
        }
        return true
    }

    /// The system folder picker, as a sheet on `window`; the chosen folder
    /// becomes the root.
    public func chooseFolder(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: root)
        panel.prompt = "Abrir"
        let pick: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            self?.open(url.path)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: pick) } else { pick(panel.runModal()) }
    }

    /// The canonical path once authorized, or nil.
    static func authorize(_ path: String) -> String? {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard cadex_workspace_authorize(path, &bytes, &length) == CADEX_OK, let bytes else { return nil }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    /// The first argument naming an existing folder (core/features/workspace/launch.zig).
    static func launchDirectory(arguments: [String], cwd: String) -> String? {
        var cStrings = arguments.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = cStrings.withUnsafeMutableBufferPointer { argv in
            argv.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: argv.count) {
                cadex_workspace_launch_directory($0, argv.count, cwd, &bytes, &length)
            }
        }
        guard status == CADEX_OK, let bytes else { return nil }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }
}
