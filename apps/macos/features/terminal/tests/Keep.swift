import Checks
import Foundation
@testable import Terminal

/// terminal.keepSessions (plan 19 phase E2) with the real cadex-terminald
/// of the core's build, on a socket of the test's own.
@MainActor let keepChecks: [(name: String, body: Checks.Body)] = [
    ("a kept terminal opens in the daemon, lets go, and is taken back by its name", {
        let socket = "/tmp/cadex-tt-\(getpid()).sock"
        setenv("CADEX_TERMINAL_SOCKET", socket, 1)
        defer { unsetenv("CADEX_TERMINAL_SOCKET") }
        var preferences = TerminalPreferences.current
        preferences.keepSessions = true
        preferences.shell = "/bin/sh"
        let before = TerminalPreferences.current
        TerminalPreferences.current = preferences
        defer { TerminalPreferences.current = before }
        guard TerminalDaemon.shared.helper != nil else { return expect(false, "no cadex-terminald in core/zig-out/bin") }

        let first = TerminalView.openSession(cols: 80, rows: 24, cwd: "/tmp", keep: true, keptID: nil)
        guard let id = first.keptID, let session = first.session else { return expect(false, "not kept: \(first)") }
        session.write("echo kept-$((6*7))\n")
        try await waitFor { screen(session).contains("kept-42") }
        session.detach()

        let back = TerminalView.openSession(cols: 80, rows: 24, cwd: "/tmp", keep: true, keptID: id)
        expect(back.keptID == id, "taken back under another name: \(String(describing: back.keptID))")
        try await waitFor { back.session.map(screen)?.contains("kept-42") == true }

        // A window that does not keep (⌘N) gets a pty of its own.
        let plain = TerminalView.openSession(cols: 80, rows: 24, cwd: "/tmp", keep: false, keptID: nil)
        expect(plain.keptID == nil && plain.session != nil)
        plain.session?.close()
        back.session?.close()
    }),
]

/// The text of the session's screen, as drawn.
@MainActor func screen(_ session: TerminalSession) -> String {
    guard let frame = session.currentFrame(), let text = frame.pointee.text else { return "" }
    return String(decoding: UnsafeBufferPointer(start: text, count: Int(frame.pointee.text_len)), as: UTF8.self)
}

/// Polls `done` every 20 ms for up to 5 s.
@MainActor func waitFor(_ done: () -> Bool) async throws {
    for _ in 0..<250 where !done() {
        try await Task.sleep(for: .milliseconds(20))
    }
    expect(done(), "never happened")
}
