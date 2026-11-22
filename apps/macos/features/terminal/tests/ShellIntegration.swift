import Checks
import Foundation
@testable import Terminal

// The zsh integration (plan 22, phase C) with a real zsh: the owner's files
// run from the owner's folder, and the typed `claude` reaches `cadex claude`.

/// Runs zsh with only `env`; its output.
func runZsh(_ env: [String: String], _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = arguments
    process.environment = env
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

@MainActor let shellIntegrationChecks: [(name: String, body: Checks.Body)] = [
    ("the zsh folder is found beside the source and set only when it exists", {
        let folder = TerminalShellIntegration.zshFolder(resources: nil)
        expect(folder?.hasSuffix("features/terminal/shell-integration/zsh") == true, "\(String(describing: folder))")
        expect(TerminalShellIntegration.environment(zshFolder: nil, tools: "/c") == [:])
        expect(TerminalShellIntegration.environment(zshFolder: "/z", tools: "/c") == ["CADEX_ZSH_INTEGRATION": "/z", "CADEX_TOOLS": "/c"])
        expect(TerminalShellIntegration.environment(zshFolder: "/z", tools: nil) == ["CADEX_ZSH_INTEGRATION": "/z"])
    }),
    ("a zsh tab gives the owner's ZDOTDIR back, reads the owner's files and sends claude to cadex", {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "cadex-zsh-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: dir) }
        try fm.createDirectory(atPath: dir + "/home", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dir + "/own", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/home/.zshrc", contents: Data("echo home-zshrc\n".utf8))
        fm.createFile(atPath: dir + "/own/.zshenv", contents: Data("echo own-zshenv\n".utf8))
        fm.createFile(atPath: dir + "/own/.zshrc", contents: Data("echo own-zshrc\n".utf8))
        fm.createFile(atPath: dir + "/cadex", contents: Data("#!/bin/sh\necho \"cadex $*\"\n".utf8), attributes: [.posixPermissions: 0o755])
        guard let zsh = TerminalShellIntegration.zshFolder(resources: nil) else { return expect(false, "no zsh folder") }
        let script = "whence -w claude; echo \"Z=${ZDOTDIR-unset} U=${CADEX_USER_ZDOTDIR-unset}\"; claude --version"
        let plain = runZsh(["HOME": dir + "/home", "ZDOTDIR": zsh, "CADEX_TOOLS": dir + "/cadex"], ["-i", "-c", script])
        expect(plain.contains("home-zshrc") && plain.contains("claude: function") && plain.contains("Z=unset U=unset")
               && plain.contains("cadex claude --version"), plain)
        let own = runZsh(["HOME": dir + "/home", "ZDOTDIR": zsh, "CADEX_USER_ZDOTDIR": dir + "/own", "CADEX_TOOLS": dir + "/cadex"],
                         ["-i", "-c", script])
        expect(own.contains("own-zshenv") && own.contains("own-zshrc") && !own.contains("home-zshrc")
               && own.contains("Z=\(dir)/own U=unset") && own.contains("cadex claude --version"), own)
    }),
    ("the interactive claude opens at the foot of the pane: one newline per row first, none for print mode", {
        // Claude Code draws where the cursor is; at the top its box slid down as the talk grew (2026-11-22).
        guard let zsh = TerminalShellIntegration.zshFolder(resources: nil) else { return expect(false, "no zsh folder") }
        let dir = NSTemporaryDirectory() + "cadex-zsh-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir + "/cadex", contents: Data("#!/bin/sh\necho \"cadex $*\"\n".utf8), attributes: [.posixPermissions: 0o755])
        // `script` gives the zsh a terminal: the newlines go only to one.
        func run(_ line: String) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", "/bin/zsh", "-f", "-c", "source \(zsh)/.zshenv; LINES=4; \(line)"]
            process.environment = ["HOME": dir, "CADEX_TOOLS": dir + "/cadex"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardInput = FileHandle.nullDevice
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let open = run("X=1 claude --settings s")
        expect(open.contains("\r\n\r\n\r\n\r\ncadex claude --settings s"), open.debugDescription)
        let printed = run("claude -p hi")
        expect(printed.contains("cadex claude -p hi") && !printed.contains("\r\n\r\ncadex"), printed.debugDescription)
        let sub = run("claude mcp list")
        expect(!sub.contains("\r\n\r\ncadex"), sub.debugDescription)
    }),
]
