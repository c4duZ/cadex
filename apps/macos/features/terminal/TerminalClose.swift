import AppKit

/// What whoever closes a terminal (a tab, a pane) needs to know and do. The
/// question before closing over a running program is the tabs feature's
/// (docs/spec/tabs.md, "Fechar").
extension TerminalView {
    /// A program other than the shell runs in the foreground.
    public var hasForegroundProcess: Bool { session?.hasForegroundProcess == true }

    /// The current directory of the session (OSC 7 or the foreground
    /// program's); new tabs and panes open there.
    public var currentDirectory: String? { session?.workingDirectory() }

    /// Takes the shell to `path` by typing `cd` with the path escaped, as if
    /// the user did it (the status bar's folder menu).
    public func changeDirectory(to path: String) {
        guard let session, !session.hasForegroundProcess else { return }
        session.write("cd " + TerminalSession.quotePaths([path]) + "\r")
    }

    /// Ends the shell now, without asking (the caller asked already).
    public func closeSession() {
        session?.close()
    }
}
