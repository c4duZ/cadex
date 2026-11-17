import Checks
import Foundation
@testable import Terminal

/// terminal.keepSessions (plan 19 phase E2) with the real cadex-terminald
/// of the core's build, on a socket of the test's own.
@MainActor let keepChecks: [(name: String, body: Checks.Body)] = [
    ("typed into a shell that just opened, the text waits for its prompt and runs (plan 24 F: zsh flushed it)", {
        var preferences = TerminalPreferences.current
        preferences.shell = "/bin/zsh"
        let before = TerminalPreferences.current
        TerminalPreferences.current = preferences
        defer { TerminalPreferences.current = before }
        let out = NSTemporaryDirectory() + "cadex-typeahead-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: out) }
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500), cwd: "/tmp")
        defer { view.closeSession() }
        view.typeWhenReady("echo typed > \(out)\n")
        try await waitFor { FileManager.default.fileExists(atPath: out) }
        let settled = Date()
        let later = out + "-2"
        defer { try? FileManager.default.removeItem(atPath: later) }
        view.typeWhenReady("echo again > \(later)\n")
        try await waitFor { FileManager.default.fileExists(atPath: later) }
        expect(Date().timeIntervalSince(settled) < 2, "a settled shell gets it at once")
    }),
    ("an agent's quiet time runs from done or idle and stops while it works; Restart shows and goes (plan 19 F)", {
        var preferences = TerminalPreferences.current
        preferences.shell = "/bin/sh"
        let before = TerminalPreferences.current
        TerminalPreferences.current = preferences
        defer { TerminalPreferences.current = before }
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500), cwd: "/tmp")
        defer { view.closeSession() }
        // Each report then a marker, so the next check sees this one applied.
        var count = 0
        @MainActor func report(_ state: String) async throws {
            count += 1
            let marker = "mark-\(count)"
            view.session?.write("printf '\\033]7501;state=\(state):app=claude-code\\007'; echo \(marker)\n")
            try await waitFor { screen(view.session!).components(separatedBy: marker).count > 2 }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await report("working")
        expect(view.agentQuietSince == nil, "working: not quiet")
        try await report("idle")
        let quiet = view.agentQuietSince
        expect(quiet != nil, "idle: quiet from now")
        try await report("done")
        expect(view.agentQuietSince == quiet, "done after idle: still the same quiet time")
        try await report("working")
        expect(view.agentQuietSince == nil, "working again: not quiet")
        // Restart only with someone to run it; false takes it away.
        view.offerRestart(true)
        expect(!view.subviews.contains { $0 is TerminalOffer }, "no agents.restart wired: no button")
        view.onRestartAgent = {}
        view.offerRestart(true)
        expect(view.subviews.contains { ($0 as? TerminalOffer)?.isRestart == true })
        view.offerRestart(false)
        expect(!view.subviews.contains { $0 is TerminalOffer })
    }),
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
