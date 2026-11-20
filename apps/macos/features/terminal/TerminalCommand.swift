import CCadex
import Foundation
import Strings

/// The command the shell runs in a terminal, and the last one that ended (the core's OSC 133
/// marks from Cadex's zsh integration; plan 29's review against the mockups). The tabs show it
/// ("npm run dev", "running 38 s", "Open :5173 in preview"), and so do the tree and the right
/// panel's check line ("make check passed · 2 min ago").
public struct TerminalCommand: Equatable, Sendable {
    /// The line running now, nil at the prompt.
    public var running: String?
    public var startedAt: Date?
    /// The last line that ended, its exit code (nil when the shell gave none) and when.
    public var last: String?
    public var lastExit: Int32?
    public var endedAt: Date?
    /// The local address the running command printed (a dev server), for the header's offer.
    public var served: String?

    public init() {}

    /// The line as a short name: no variables before it (`PATH=… X=1`), no `env -u …`, the
    /// program's own name (`/usr/bin/make` is "make"; `cadex claude` is "claude"), at most 40
    /// characters.
    public static func shortName(_ line: String) -> String {
        // `cd <folder> && …` names what comes after: the Claude the app brings back types
        // `cd '<folder>' && … claude --resume`, and the tab said "cd /Users/…" (2026-11-20).
        var rest = Substring(line)
        while rest.hasPrefix("cd "), let and = rest.range(of: "&&") { rest = rest[and.upperBound...].drop { $0 == " " } }
        var words = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let first = words.first, first.contains("="), !first.hasPrefix("-"), first.first?.isLetter == true || first.first == "_" {
            words.removeFirst()
        }
        if words.first == "env" {
            words.removeFirst()
            while let first = words.first, first.hasPrefix("-") || first.contains("=") {
                words.removeFirst()
                // `-u NAME`: the name goes too.
                if first == "-u", !words.isEmpty { words.removeFirst() }
            }
        }
        while let first = words.first, ["sudo", "nohup", "exec", "time", "command"].contains(first) { words.removeFirst() }
        guard var program = words.first else { return line }
        program = (program as NSString).lastPathComponent
        words[0] = program
        if program == "cadex", words.count > 1, ["claude", "codex"].contains(words[1]) { words.removeFirst() }
        // The agents' own flags are noise in a tab's name.
        if ["claude", "codex"].contains(words[0]) { words = [words[0]] }
        let name = words.joined(separator: " ")
        return name.count > 40 ? String(name.prefix(39)) + "…" : name
    }

    /// "38 s", "4 min", "2 h": how long it has run.
    public static func duration(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }

    /// ":5173" of "http://localhost:5173/".
    public static func port(_ url: String) -> String {
        guard let port = URL(string: url.contains("://") ? url : "http://" + url)?.port else { return url }
        return ":\(port)"
    }
}

extension TerminalSession {
    /// The core's record of the shell's command: running, its text, the last one and its code.
    func shellCommand() -> (seq: UInt32, running: String?, last: String?, lastExit: Int32?)? {
        guard let handle else { return nil }
        var raw = cadex_shell_command()
        guard cadex_terminal_shell_command(handle, &raw) == CADEX_OK else { return nil }
        let text = withUnsafeBytes(of: &raw.text) { String(decoding: $0.prefix(Int(raw.text_len)), as: UTF8.self) }
        let last = withUnsafeBytes(of: &raw.last) { String(decoding: $0.prefix(Int(raw.last_len)), as: UTF8.self) }
        return (raw.seq, raw.running != 0 ? text : nil, last.isEmpty ? nil : last, raw.has_exit != 0 ? raw.exit_code : nil)
    }
}

extension TerminalView {
    /// A start or an end since the last look (the core told it as a title change): stamped now.
    func readCommand(now: Date = Date()) {
        guard let read = session?.shellCommand(), read.seq != commandSeq else { return }
        commandSeq = read.seq
        var next = command
        if let running = read.running {
            if running != next.running || next.startedAt == nil { next.startedAt = now; next.served = nil }
            next.running = running
        } else if next.running != nil || read.last != next.last {
            next.running = nil
            next.startedAt = nil
            next.served = nil
            next.last = read.last
            next.lastExit = read.lastExit
            next.endedAt = now
        }
        command = next
    }

    /// A local address printed while a command runs: the header offers it.
    func noteServed(_ url: String) {
        guard command.running != nil else { return }
        command.served = url
        onProgramTitle?(programTitle)
    }

    /// The header's "Open :5173 in preview".
    public func openServed() {
        guard let url = command.served else { return }
        onOpenPreview?(url)
    }
}
