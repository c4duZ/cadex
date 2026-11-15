import Foundation

/// A terminal the daemon keeps (terminal.keepSessions, plan 19 phase E2):
/// opened by name, taken back after the app comes back, or, when the daemon
/// no longer has it (the Mac restarted), a new shell that first shows the
/// output saved for it. The daemon failing leaves a pty of its own.
extension TerminalView {
    struct Opened {
        let session: TerminalSession?
        /// The daemon's name for it; nil on a pty of its own.
        let keptID: String?
    }

    static func openSession(cols: UInt16, rows: UInt16, cwd: String?, keep: Bool, keptID: String?) -> Opened {
        let p = TerminalPreferences.current
        let shell = p.shell.isEmpty ? nil : p.shell
        let history = UInt32(clamping: p.historyLines)
        let open = { (kept: TerminalSession.Kept?, replay: String?) in
            try? TerminalSession(cols: cols, rows: rows, cwd: cwd, shell: shell, historyLines: history, kept: kept, replayPath: replay)
        }
        let daemon = TerminalDaemon.shared
        guard keep, p.keepSessions, daemon.ready() else { return Opened(session: open(nil, nil), keptID: nil) }
        if let keptID, let session = open(TerminalSession.Kept(socket: daemon.socket, id: keptID, attach: true), nil) {
            return Opened(session: session, keptID: keptID)
        }
        // Gone from the daemon (or never there): a new one, with what was
        // saved for the old name shown first.
        let id = daemon.newID()
        if let session = open(TerminalSession.Kept(socket: daemon.socket, id: id, attach: false), keptID.flatMap(daemon.savedOutput)) {
            return Opened(session: session, keptID: id)
        }
        return Opened(session: open(nil, nil), keptID: nil)
    }

    /// Lets go of the shell, which goes on in the daemon when it keeps it
    /// (the main window closing, the app quitting); else it ends.
    public func detachSession() {
        session?.detach()
    }
}
