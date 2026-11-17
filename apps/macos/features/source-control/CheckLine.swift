import Foundation
import Strings

/// Changes' footer line, "make check passed · 2 min ago" (the Inspector mockup): the last
/// project check that ended in a terminal of the task or project, as its shell reported it
/// (the terminal's OSC 133 marks). Pure: the app gives the commands, this says which counts.
public enum CheckLine {
    /// The programs a check runs with, and the words that make a command of theirs a check.
    static let tools: Set<String> = ["make", "npm", "pnpm", "yarn", "bun", "cargo", "swift", "go", "zig", "just", "gradle", "mvn",
                                     "xcodebuild", "deno", "tox", "nox", "rake", "mix"]
    static let words = ["check", "test", "lint", "build", "verify", "typecheck"]
    static let runners: Set<String> = ["pytest", "jest", "vitest", "mocha", "rspec", "phpunit"]

    /// `make check`, `npm test`, `swift build`, `pytest -q`: a check; `ls`, `git status`: not.
    public static func isCheck(_ line: String) -> Bool {
        let parts = line.split(separator: " ").map { String($0).lowercased() }
        guard let first = parts.first.map({ ($0 as NSString).lastPathComponent }) else { return false }
        if runners.contains(first) { return true }
        guard tools.contains(first) else { return false }
        return parts.dropFirst().contains { word in words.contains { word.contains($0) } }
    }

    /// "make check passed · 2 min ago", "npm test failed · now".
    public static func text(_ name: String, passed: Bool, endedAt: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(endedAt)) / 60)
        let when = minutes < 1 ? T("now", "agora")
            : minutes < 60 ? T("\(minutes) min ago", "há \(minutes) min") : T("\(minutes / 60) h ago", "há \(minutes / 60) h")
        return name + (passed ? T(" passed", " passou") : T(" failed", " falhou")) + " · " + when
    }
}
