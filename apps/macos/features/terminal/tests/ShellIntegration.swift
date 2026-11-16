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
]
